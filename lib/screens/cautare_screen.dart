import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/instante_portal.dart';
import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/cautari_recente_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/termene.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';
import 'rezultate_screen.dart';

/// Ecranul principal de căutare (Figma: „01 · Căutare”).
class CautareScreen extends StatefulWidget {
  /// Deschide fila „Monitorizate” (butonul „Vezi toate”).
  final VoidCallback? onVeziMonitorizate;

  /// Pornește căutarea din afara ecranului (butonul rotund cu lupa, când bara
  /// de jos e strânsă): fiecare incrementare înseamnă o apăsare.
  final ValueListenable<int>? cereriCautare;

  const CautareScreen({super.key, this.onVeziMonitorizate, this.cereriCautare});

  @override
  State<CautareScreen> createState() => _CautareScreenState();
}

class _CautareScreenState extends State<CautareScreen> {
  final _numarController = TextEditingController();
  final _obiectController = TextEditingController();
  final _parteController = TextEditingController();

  /// Codurile SOAP ale instanțelor alese, în ordinea alegerii; gol = toate.
  List<String> _institutii = [];
  DateTimeRange? _interval;
  bool _maiMulte = false;

  @override
  void initState() {
    super.initState();
    CautariRecenteService.instance.incarca();
    widget.cereriCautare?.addListener(_cauta);
  }

  @override
  void dispose() {
    widget.cereriCautare?.removeListener(_cauta);
    _numarController.dispose();
    _obiectController.dispose();
    _parteController.dispose();
    super.dispose();
  }

  void _cauta() {
    FocusScope.of(context).unfocus();
    final criterii = CautareRecenta(
      numar: _numarController.text.trim(),
      obiect: _obiectController.text.trim(),
      parte: _parteController.text.trim(),
      institutie: _institutii.join(','),
      dataStart: _interval?.start,
      dataStop: _interval?.end,
    );
    if (!criterii.areCriteriuPrincipal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Introdu numărul dosarului, obiectul sau numele unei părți.',
          ),
        ),
      );
      return;
    }
    CautariRecenteService.instance.adauga(criterii);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RezultateScreen(criterii: criterii)),
    );
  }

  void _reia(CautareRecenta c) {
    _numarController.text = c.numar;
    _obiectController.text = c.obiect;
    _parteController.text = c.parte;
    setState(() {
      _institutii = c.institutii;
      _interval = c.dataStart != null && c.dataStop != null
          ? DateTimeRange(start: c.dataStart!, end: c.dataStop!)
          : null;
      _maiMulte = _maiMulte || c.institutie.isNotEmpty || _interval != null;
    });
    _cauta();
  }

  Future<void> _alegeInstanta() async {
    final alese = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _FoaieInstante(alese: _institutii),
    );
    if (alese != null) setState(() => _institutii = alese);
  }

  Future<void> _alegeInterval() async {
    final acum = DateTime.now();
    final ales = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: DateTime(acum.year, acum.month, acum.day),
      initialDateRange: _interval,
      helpText: 'Data înregistrării dosarului',
      saveText: 'Gata',
    );
    if (ales != null) setState(() => _interval = ales);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // Bara de stare are fundal propriu: la derulare, formularul nu mai
        // trece pe sub ceas și iconițe.
        body: Column(
          children: [
            Container(
              color: AppColors.primary,
              height: MediaQuery.paddingOf(context).top,
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _antet(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_recente(), _termene()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _antet() {
    const alb = AppColors.onPrimary;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.hero),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 24),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PORTAL DOSARE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: AppColors.accentContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Caută un dosar',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: alb,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Date preluate direct de pe portal.just.ro',
                    style: TextStyle(
                      fontSize: 14,
                      color: alb.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E0D1433),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _camp(
                      eticheta: 'Număr dosar',
                      hint: 'ex. 14993/299/2026',
                      icon: Icons.folder,
                      controller: _numarController,
                    ),
                    const SizedBox(height: 14),
                    _camp(
                      eticheta: 'Obiectul dosarului',
                      hint: 'ex. uzucapiune, pretenții',
                      icon: Icons.search,
                      controller: _obiectController,
                    ),
                    const SizedBox(height: 14),
                    _camp(
                      eticheta: 'Nume parte',
                      hint: 'ex. Popescu Ion, Exemplu SRL',
                      icon: Icons.person,
                      controller: _parteController,
                    ),
                    _criteriiSuplimentare(),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _cauta,
                      icon: const Icon(Icons.search, size: 20),
                      label: const Text('Caută dosar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _criteriiSuplimentare() {
    final instanta = _institutii.isEmpty
        ? 'Toate instanțele'
        : descrieInstante(_institutii);
    final interval = _interval == null
        ? 'Oricând'
        : '${formateazaData(_interval!.start)} – ${formateazaData(_interval!.end)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _maiMulte = !_maiMulte),
            icon: Icon(
              _maiMulte ? Icons.expand_less : Icons.expand_more,
              size: 20,
            ),
            label: const Text('Mai multe criterii'),
          ),
        ),
        if (_maiMulte) ...[
          _selector(
            eticheta: _institutii.length > 1 ? 'Instanțele' : 'Instanța',
            valoare: instanta,
            icon: Icons.account_balance,
            onTap: _alegeInstanta,
            onSterge: _institutii.isEmpty
                ? null
                : () => setState(() => _institutii = []),
          ),
          const SizedBox(height: 14),
          _selector(
            eticheta: 'Înregistrat între',
            valoare: interval,
            icon: Icons.date_range,
            onTap: _alegeInterval,
            onSterge: _interval == null
                ? null
                : () => setState(() => _interval = null),
          ),
        ],
      ],
    );
  }

  /// Câmp de ales (instanța, intervalul), în același stil cu câmpurile de
  /// text: eticheta deasupra, nu în chenar.
  Widget _selector({
    required String eticheta,
    required String valoare,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onSterge,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eticheta(eticheta),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 20),
              suffixIcon: onSterge == null
                  ? const Icon(Icons.expand_more)
                  : IconButton(
                      tooltip: 'Șterge',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: onSterge,
                    ),
            ),
            child: Text(
              valoare,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _eticheta(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceVariant,
    ),
  );

  Widget _camp({
    required String eticheta,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eticheta(eticheta),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _cauta(),
          decoration: InputDecoration(
            hintText: hint,
            hintMaxLines: 1,
            hintStyle: const TextStyle(overflow: TextOverflow.ellipsis),
            prefixIcon: Icon(icon, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _recente() {
    return ListenableBuilder(
      listenable: CautariRecenteService.instance,
      builder: (context, _) {
        final recente = CautariRecenteService.instance.lista;
        if (recente.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AntetSectiune(
                'Căutări recente',
                actiune: 'Șterge',
                onActiune: CautariRecenteService.instance.sterge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in recente)
                    Pastila(
                      c.eticheta,
                      icon: Icons.history,
                      onTap: () => _reia(c),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _termene() {
    return ListenableBuilder(
      listenable: BibliotecaService.instance,
      builder: (context, _) {
        final cuTermen = <(DosarSalvat, Sedinta)>[
          for (final s in BibliotecaService.instance.dosare)
            if (urmatorulTermen(s.dosar) case final t?) (s, t),
        ]..sort((a, b) => a.$2.data!.compareTo(b.$2.data!));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AntetSectiune(
              'Termene apropiate',
              actiune: cuTermen.isEmpty ? null : 'Vezi toate',
              onActiune: widget.onVeziMonitorizate,
            ),
            const SizedBox(height: 8),
            if (cuTermen.isEmpty)
              const Text(
                'Monitorizează un dosar ca să vezi aici următoarele termene.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                ),
              )
            else
              for (final (s, _) in cuTermen.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DosarCardWidget(
                    key: ValueKey(s.dosar.cheie),
                    dosar: s.dosar,
                    salvat: s,
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// Lista instanțelor, cu căutare după nume sau județ. Întoarce codul SOAP.
/// Alegerea instanțelor: oricâte, bifate pe rând sau tot județul deodată
/// (ex. „prahova” → „Bifează toate”).
class _FoaieInstante extends StatefulWidget {
  final List<String> alese;
  const _FoaieInstante({required this.alese});

  @override
  State<_FoaieInstante> createState() => _FoaieInstanteState();
}

class _FoaieInstanteState extends State<_FoaieInstante> {
  String _text = '';
  late final List<String> _alese = [...widget.alese];

  static String _simplu(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ăâ]'), 'a')
      .replaceAll('î', 'i')
      .replaceAll(RegExp('[șş]'), 's')
      .replaceAll(RegExp('[țţ]'), 't');

  void _comuta(String cod) => setState(() {
    if (!_alese.remove(cod)) _alese.add(cod);
  });

  @override
  Widget build(BuildContext context) {
    final cautat = _simplu(_text.trim());
    final instante = [
      for (final i in toateInstantele)
        if (cautat.isEmpty || _simplu('${i.nume} ${i.judet}').contains(cautat))
          i,
    ]..sort((a, b) => a.nume.compareTo(b.nume));
    // Cele bifate stau sus, ca să se vadă ce ai ales.
    instante.sort((a, b) {
      final x = _alese.contains(a.cod) ? 0 : 1,
          y = _alese.contains(b.cod) ? 0 : 1;
      return x - y;
    });
    final toateBifate =
        instante.isNotEmpty && instante.every((i) => _alese.contains(i.cod));

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (t) => setState(() => _text = t),
              decoration: const InputDecoration(
                hintText: 'Caută instanța sau județul',
                hintMaxLines: 1,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          if (cautat.isNotEmpty && instante.length > 1 && instante.length <= 30)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    for (final i in instante) {
                      if (toateBifate) {
                        _alese.remove(i.cod);
                      } else if (!_alese.contains(i.cod)) {
                        _alese.add(i.cod);
                      }
                    }
                  }),
                  icon: Icon(
                    toateBifate ? Icons.remove_done : Icons.done_all,
                    size: 20,
                  ),
                  label: Text(
                    toateBifate
                        ? 'Debifează cele ${instante.length}'
                        : 'Bifează toate cele ${instante.length}',
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: instante.length,
              itemBuilder: (context, i) {
                final inst = instante[i];
                return CheckboxListTile(
                  value: _alese.contains(inst.cod),
                  onChanged: (_) => _comuta(inst.cod),
                  title: Text(inst.nume),
                  subtitle: Text(inst.judet),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _alese.isEmpty
                        ? null
                        : () => setState(_alese.clear),
                    child: const Text('Toate instanțele'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_alese),
                    child: Text(
                      _alese.isEmpty ? 'Gata' : 'Gata (${_alese.length})',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
