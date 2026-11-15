import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/client_service.dart';
import '../services/monitorizare_service.dart';
import '../services/raport_service.dart' show numarCu;
import '../theme/app_theme.dart';

/// Filtrele ecranului de selecție: instanța (cod) și dosarele fără „clientul
/// meu” marcat (de obicei cele în care utilizatorul nu e parte).
List<DosarSalvat> filtreazaPentruSelectie(
  List<DosarSalvat> dosare, {
  String? institutie,
  bool faraClient = false,
  required ClientService clienti,
}) => [
  for (final s in dosare)
    if ((institutie == null || s.dosar.institutie == institutie) &&
        (!faraClient || clienti.client(s.dosar.numar) == null))
      s,
];

/// „Selectează dosare”: scoate dintr-o dată mai multe dosare din monitorizate,
/// de exemplu după un „Monitorizează toate” din greșeală. Ștergerea se poate
/// anula din mesajul de jos.
class SelecteazaMonitorizateScreen extends StatefulWidget {
  /// Dosarul de pe care s-a ajuns aici (apăsare lungă), bifat de la început.
  final String? cheieInitiala;

  const SelecteazaMonitorizateScreen({super.key, this.cheieInitiala});

  @override
  State<SelecteazaMonitorizateScreen> createState() => _SelecteazaMonitorizateScreenState();
}

class _SelecteazaMonitorizateScreenState extends State<SelecteazaMonitorizateScreen> {
  late final Set<String> _alese = {if (widget.cheieInitiala case final c?) c};
  String? _institutie;
  bool _faraClient = false;

  List<DosarSalvat> get _afisate => filtreazaPentruSelectie(
    BibliotecaService.instance.dosare,
    institutie: _institutie,
    faraClient: _faraClient,
    clienti: ClientService.instance,
  );

  String _dosareText(int n) => n == 1 ? 'un dosar' : numarCu(n, 'dosare');

  Future<void> _alegeInstanta() async {
    final numar = <String, int>{};
    final nume = <String, String>{};
    for (final s in BibliotecaService.instance.dosare) {
      numar.update(s.dosar.institutie, (n) => n + 1, ifAbsent: () => 1);
      nume[s.dosar.institutie] = s.dosar.instanta;
    }
    final coduri = numar.keys.toList()
      ..sort((a, b) {
        final c = numar[b]!.compareTo(numar[a]!);
        return c != 0 ? c : nume[a]!.compareTo(nume[b]!);
      });
    final ales = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Toate instanțele'),
                trailing: _institutie == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final c in coduri)
                ListTile(
                  title: Text(nume[c]!),
                  subtitle: Text(numar[c] == 1 ? '1 dosar' : numarCu(numar[c]!, 'dosare')),
                  trailing: _institutie == c ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (ales == null) return;
    setState(() => _institutie = ales.isEmpty ? null : ales);
  }

  Future<void> _sterge() async {
    final n = _alese.length;
    final messenger = ScaffoldMessenger.of(context);
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nu mai urmărești ${_dosareText(n)}?'),
        content: const Text(
          'Nu mai primești notificări pentru ele. Le poți pune la loc imediat din mesajul de jos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nu mai urmări'),
          ),
        ],
      ),
    );
    if (da != true) return;
    final scoase = await BibliotecaService.instance.stergeToate(_alese);
    if (!mounted) return;
    setState(_alese.clear);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        showCloseIcon: true,
        duration: const Duration(seconds: 8),
        content: Text(
          scoase.length == 1
              ? 'Un dosar scos din monitorizate.'
              : '${numarCu(scoase.length, 'dosare')} scoase din monitorizate.',
        ),
        action: SnackBarAction(
          label: 'Anulează',
          onPressed: () => BibliotecaService.instance.restaureaza(scoase),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([BibliotecaService.instance, ClientService.instance]),
      builder: (context, _) {
        final toate = BibliotecaService.instance.dosare;
        // Un dosar dispărut între timp (șters din altă parte) nu rămâne bifat.
        _alese.removeWhere((c) => !toate.any((s) => s.dosar.cheie == c));
        if (_institutie != null && !toate.any((s) => s.dosar.institutie == _institutie)) {
          _institutie = null;
        }
        final afisate = _afisate;
        final toateBifate =
            afisate.isNotEmpty && afisate.every((s) => _alese.contains(s.dosar.cheie));
        final numeInstanta = _institutie == null
            ? null
            : toate.firstWhere((s) => s.dosar.institutie == _institutie).dosar.instanta;

        return Scaffold(
          appBar: AppBar(
            title: Text(_alese.isEmpty ? 'Selectează dosare' : '${_alese.length} selectate'),
            actions: [
              TextButton(
                onPressed: afisate.isEmpty
                    ? null
                    : () => setState(() {
                        final chei = afisate.map((s) => s.dosar.cheie);
                        toateBifate ? _alese.removeAll(chei) : _alese.addAll(chei);
                      }),
                child: Text(toateBifate ? 'Deselectează' : 'Selectează tot'),
              ),
            ],
          ),
          body: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(numeInstanta ?? 'Toate instanțele'),
                      avatar: const Icon(Icons.account_balance_outlined, size: 18),
                      selected: _institutie != null,
                      showCheckmark: false,
                      onSelected: (_) => _alegeInstanta(),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Fără „clientul meu”'),
                      selected: _faraClient,
                      onSelected: (v) => setState(() => _faraClient = v),
                    ),
                  ],
                ),
              ),
              if (toate.length > plafonDosare)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: AvertizarePlafon(dosare: toate.length),
                ),
              Expanded(
                child: afisate.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Niciun dosar nu se potrivește filtrelor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: afisate.length,
                        itemBuilder: (context, i) {
                          final s = afisate[i];
                          final cheie = s.dosar.cheie;
                          final client = ClientService.instance.client(s.dosar.numar);
                          return CheckboxListTile(
                            value: _alese.contains(cheie),
                            onChanged: (v) => setState(
                              () => v == true ? _alese.add(cheie) : _alese.remove(cheie),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(s.dosar.numar),
                            subtitle: Text(
                              [
                                s.dosar.instanta,
                                if (s.dosar.obiect.isNotEmpty) s.dosar.obiect,
                                if (client != null) 'Clientul meu',
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: _alese.isEmpty ? null : _sterge,
                icon: const Icon(Icons.bookmark_remove_outlined),
                label: Text(_alese.isEmpty ? 'Nu mai urmări' : 'Nu mai urmări (${_alese.length})'),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mesajul afișat când sunt urmărite mai multe dosare decât [plafonDosare];
/// apare și pe ecranul Monitorizate.
class AvertizarePlafon extends StatelessWidget {
  final int dosare;
  final VoidCallback? onAlege;

  /// X-ul din colț: ascunde avertizarea.
  final VoidCallback? onInchide;

  const AvertizarePlafon({super.key, required this.dosare, this.onAlege, this.onInchide});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.accentContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 14, onInchide == null ? 14 : 4, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Urmărești ${numarCu(dosare, 'dosare')}. Peste $plafonDosare le verificăm '
                    'de două ori mai rar, ca portalul să nu ne blocheze. Scoate-le pe cele '
                    'care nu te interesează.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (onAlege != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: onAlege,
                        child: const Text('Alege ce scoți'),
                      ),
                    ),
                ],
              ),
            ),
            if (onInchide != null)
              IconButton(
                tooltip: 'Ascunde avertizarea',
                visualDensity: VisualDensity.compact,
                color: AppColors.onSurfaceVariant,
                icon: const Icon(Icons.close, size: 20),
                onPressed: onInchide,
              ),
          ],
        ),
      ),
    );
  }
}
