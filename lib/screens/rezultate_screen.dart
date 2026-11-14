import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/cautari_recente_service.dart';
import '../services/parti_urmarite_service.dart';
import '../services/soap_service.dart';
import '../theme/app_theme.dart';
import '../utils/instante.dart';
import '../utils/sortare_rezultate.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';
import '../widgets/parcurs_dosar.dart';

/// Rezultatele unei căutări (Figma: „02 · Rezultate”, „06 · se încarcă”,
/// „07 · eroare & fără rezultate”).
class RezultateScreen extends StatefulWidget {
  final CautareRecenta criterii;

  /// Se poate înlocui în teste.
  final SoapService? soap;

  RezultateScreen({
    super.key,
    String numar = '',
    String obiect = '',
    CautareRecenta? criterii,
    this.soap,
  }) : criterii = criterii ?? CautareRecenta(numar: numar, obiect: obiect);

  String get numar => criterii.numar;
  String get obiect => criterii.obiect;

  @override
  State<RezultateScreen> createState() => _RezultateScreenState();
}

class _RezultateScreenState extends State<RezultateScreen> {
  late final SoapService _soap = widget.soap ?? SoapService();

  List<Dosar> _dosare = [];
  bool _limitaAtinsa = false;
  bool _seIncarca = true;
  Object? _eroare;
  String? _filtru;
  SortareRezultate _sortare = SortareRezultate.portal;
  int? _an;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cauta();
    if (widget.criterii.parte.trim().isNotEmpty) PartiUrmariteService.instance.incarca();
  }

  Future<void> _cauta() async {
    setState(() {
      _seIncarca = true;
      _eroare = null;
    });
    try {
      final c = widget.criterii;
      final r = await _soap.cautaDosare(
        numarDosar: c.numar,
        obiectDosar: c.obiect,
        numeParte: c.parte,
        institutie: c.institutie,
        dataStart: c.dataStart,
        dataStop: c.dataStop,
      );
      // Căutarea după număr aduce toate instanțele dosarului: le păstrăm
      // pentru „Parcursul dosarului” din detaliu.
      if (widget.numar.trim().isNotEmpty) ParcursDosar.memoreaza(r.dosare);
      if (!mounted) return;
      setState(() {
        _dosare = r.dosare;
        _limitaAtinsa = r.limitaAtinsa;
        _filtru = null;
        _an = null;
      });
    } catch (e) {
      if (mounted) setState(() => _eroare = e);
    } finally {
      if (mounted) setState(() => _seIncarca = false);
    }
  }

  bool _seAdaugaParte = false;

  /// Pornește alerta la dosarele noi pe numele părții căutate.
  Future<void> _urmaresteParte() async {
    final c = widget.criterii;
    final parti = PartiUrmariteService.instance;
    final messenger = ScaffoldMessenger.of(context);
    if (parti.urmareste(c.parte, c.institutie)) {
      await parti.sterge(ParteUrmarita.cheiePentru(c.parte, c.institutie));
      messenger.showSnackBar(SnackBar(content: Text('Nu mai urmărești „${c.parte.trim()}”.')));
      return;
    }
    setState(() => _seAdaugaParte = true);
    try {
      final preaGeneral = await parti.adauga(c.parte, institutie: c.institutie, soap: _soap);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            preaGeneral
                ? 'Urmărești „${c.parte.trim()}”, dar numele e foarte des întâlnit și portalul '
                      'întoarce cel mult 1.000 de dosare. Alege o instanță ca alertele să fie sigure.'
                : 'Urmărești „${c.parte.trim()}”. Vei primi o notificare la fiecare dosar nou pe acest nume.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Partea nu a putut fi urmărită: $e')));
    } finally {
      if (mounted) setState(() => _seAdaugaParte = false);
    }
  }

  Widget _butonParte() {
    return ListenableBuilder(
      listenable: PartiUrmariteService.instance,
      builder: (context, _) {
        if (_seAdaugaParte) {
          return const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final c = widget.criterii;
        final urmarita = PartiUrmariteService.instance.urmareste(c.parte, c.institutie);
        return IconButton(
          tooltip: urmarita ? 'Nu mai urmări partea' : 'Urmărește partea',
          icon: Icon(urmarita ? Icons.notifications_active : Icons.notification_add_outlined),
          color: AppColors.primary,
          onPressed: _urmaresteParte,
        );
      },
    );
  }

  String get _subtitlu {
    final c = widget.criterii;
    return [
      if (c.numar.isNotEmpty) 'Număr: ${c.numar}',
      if (c.obiect.isNotEmpty) 'Obiect: „${c.obiect}”',
      if (c.parte.isNotEmpty) 'Parte: „${c.parte}”',
      if (c.institutie.isNotEmpty) numeInstanta(c.institutie),
      if (c.interval.isNotEmpty) 'Înregistrat ${c.interval}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final stadii = <String>{
      for (final d in _dosare)
        if (d.stadiuProcesual.isNotEmpty) d.stadiuProcesual,
    }.toList();
    final afisate = ordoneazaRezultate(
      _filtru == null ? _dosare : _dosare.where((d) => d.stadiuProcesual == _filtru).toList(),
      _sortare,
      an: _an,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rezultate'),
            if (_subtitlu.isNotEmpty)
              Text(
                _subtitlu,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [if (widget.criterii.parte.trim().isNotEmpty) _butonParte()],
        bottom: !_seIncarca && _eroare == null && stadii.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      Pastila(
                        'Toate',
                        activ: _filtru == null,
                        onTap: () => setState(() => _filtru = null),
                      ),
                      for (final s in stadii) ...[
                        const SizedBox(width: 8),
                        Pastila(s, activ: _filtru == s, onTap: () => setState(() => _filtru = s)),
                      ],
                    ],
                  ),
                ),
              )
            : null,
        shape: const Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      body: _continut(afisate),
    );
  }

  Widget _continut(List<Dosar> afisate) {
    const padding = EdgeInsets.fromLTRB(16, 16, 16, 24);

    if (_seIncarca) {
      return ListView(
        padding: padding,
        children: const [
          IncarcarePortal(),
          SizedBox(height: 12),
          CardSchelet(),
          SizedBox(height: 12),
          CardSchelet(),
          SizedBox(height: 12),
          CardSchelet(),
        ],
      );
    }

    if (_eroare != null) {
      return ListView(
        padding: padding,
        children: [
          StareMesaj(
            icon: Icons.cloud_off,
            fundal: AppColors.warningContainer,
            culoare: AppColors.warning,
            titlu: 'Portalul nu răspunde',
            text:
                'Nu am putut obține datele de pe portal.just.ro. '
                'Dosarele monitorizate rămân disponibile.\n\n$_eroare',
            buton: 'Încearcă din nou',
            butonPrincipal: true,
            onButon: _cauta,
          ),
        ],
      );
    }

    if (_dosare.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          StareMesaj(
            icon: Icons.search_off,
            titlu: 'Niciun dosar găsit',
            text: widget.criterii.parte.isNotEmpty
                ? 'Verifică numele părții exact cum apare pe portal (de ex. denumirea '
                      'completă a firmei) sau renunță la filtrul de instanță ori de dată.'
                : 'Verifică numărul (ex. 14993/299/2026) sau încearcă doar după '
                      'obiectul dosarului.',
            buton: 'Modifică căutarea',
            onButon: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _cauta,
      // Bara din dreapta se poate trage, util la sute de rezultate.
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        interactive: true,
        thickness: 6,
        radius: const Radius.circular(3),
        child: ListView.separated(
          controller: _scroll,
          padding: padding,
          itemCount: afisate.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            if (i == 0) return _rezumat(afisate);
            final d = afisate[i - 1];
            return DosarCardWidget(key: ValueKey(d.cheie), dosar: d, cuBiblioteca: true);
          },
        ),
      ),
    );
  }

  /// „5 dosare”, „25 de dosare” (de la 20 în sus româna cere „de”).
  static String _dosareText(int n) =>
      n % 100 >= 20 || (n >= 100 && n % 100 == 0) ? '$n de dosare' : '$n dosare';

  /// Pune în bibliotecă toate dosarele afișate (cu filtrul de stadiu aplicat).
  Future<void> _monitorizeazaToate(List<Dosar> afisate) async {
    final messenger = ScaffoldMessenger.of(context);
    if (afisate.length > 20) {
      final da = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Monitorizezi ${_dosareText(afisate.length)}?'),
          content: const Text(
            'Le verificăm pe toate la fiecare oră și primești notificări la orice schimbare.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Renunță'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Monitorizează'),
            ),
          ],
        ),
      );
      if (da != true) return;
    }
    final noi = await BibliotecaService.instance.adaugaToate(afisate);
    final deja = afisate.length - noi;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${noi == 1 ? 'Un dosar adăugat' : '${_dosareText(noi)} adăugate'} la monitorizate'
          '${deja == 0 ? '' : ' ($deja erau deja)'}.',
        ),
      ),
    );
  }

  Widget _butonToate(List<Dosar> afisate) {
    return ListenableBuilder(
      listenable: BibliotecaService.instance,
      builder: (context, _) {
        final toate = afisate.every((d) => BibliotecaService.instance.contine(d.cheie));
        return TextButton.icon(
          onPressed: toate ? null : () => _monitorizeazaToate(afisate),
          icon: Icon(toate ? Icons.library_add_check : Icons.library_add_outlined, size: 18),
          label: Text(toate ? 'Toate monitorizate' : 'Monitorizează toate'),
        );
      },
    );
  }

  Widget _ordonare() {
    final ani = aniRezultate(_dosare);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PopupMenuButton<SortareRezultate>(
          tooltip: 'Ordonează',
          initialValue: _sortare,
          onSelected: (v) => setState(() => _sortare = v),
          itemBuilder: (_) => [
            for (final v in SortareRezultate.values)
              PopupMenuItem(value: v, child: Text(v.eticheta)),
          ],
          child: _Meniu(icon: Icons.sort, text: _sortare.eticheta),
        ),
        if (ani.length > 1)
          PopupMenuButton<int>(
            tooltip: 'Filtrează pe an',
            initialValue: _an ?? 0,
            onSelected: (v) => setState(() => _an = v == 0 ? null : v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 0, child: Text('Toți anii')),
              for (final a in ani) PopupMenuItem(value: a, child: Text('$a')),
            ],
            child: _Meniu(
              icon: Icons.calendar_today,
              text: _an == null ? 'Toți anii' : 'Anul $_an',
              activ: _an != null,
            ),
          ),
      ],
    );
  }

  Widget _rezumat(List<Dosar> afisate) {
    final numar = Row(
      children: [
        Expanded(
          child: Text(
            afisate.length == 1 ? 'Un dosar găsit' : '${afisate.length} dosare găsite',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        _butonToate(afisate),
      ],
    );
    final cuOrdonare = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_ordonare(), const SizedBox(height: 4), numar],
    );
    if (!_limitaAtinsa) return cuOrdonare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.warningContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info, size: 20, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Afișate primele ${_dosare.length} dosare (limita portalului). '
                  'Restrânge căutarea pentru rezultate complete.',
                  style: const TextStyle(fontSize: 13, height: 1.38, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        cuOrdonare,
      ],
    );
  }
}

/// Eticheta unui meniu de ordonare/filtrare, în stilul pastilelor.
class _Meniu extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool activ;
  const _Meniu({required this.icon, required this.text, this.activ = false});

  @override
  Widget build(BuildContext context) {
    final culoare = activ ? AppColors.primary : AppColors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: activ ? AppColors.primary : AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: culoare),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: culoare),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: culoare),
        ],
      ),
    );
  }
}
