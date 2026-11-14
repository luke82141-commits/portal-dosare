import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/instante_portal.dart';
import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/cautari_recente_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/instante.dart';
import '../utils/termene.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';
import 'rezultate_screen.dart';
import 'sugestie_screen.dart';

/// Ecranul principal de căutare (Figma: „01 · Căutare”).
class CautareScreen extends StatefulWidget {
  /// Deschide fila „Monitorizate” (butonul „Vezi toate”).
  final VoidCallback? onVeziMonitorizate;

  const CautareScreen({super.key, this.onVeziMonitorizate});

  @override
  State<CautareScreen> createState() => _CautareScreenState();
}

class _CautareScreenState extends State<CautareScreen> {
  final _numarController = TextEditingController();
  final _obiectController = TextEditingController();
  final _parteController = TextEditingController();

  /// Codul SOAP al instanței alese; gol = toate instanțele.
  String _institutie = '';
  DateTimeRange? _interval;
  bool _maiMulte = false;

  @override
  void initState() {
    super.initState();
    CautariRecenteService.instance.incarca();
  }

  @override
  void dispose() {
    _numarController.dispose();
    _obiectController.dispose();
    _parteController.dispose();
    super.dispose();
  }

  void _cauta() {
    final criterii = CautareRecenta(
      numar: _numarController.text.trim(),
      obiect: _obiectController.text.trim(),
      parte: _parteController.text.trim(),
      institutie: _institutie,
      dataStart: _interval?.start,
      dataStop: _interval?.end,
    );
    if (!criterii.areCriteriuPrincipal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Introdu numărul dosarului, obiectul sau numele unei părți.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
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
      _institutie = c.institutie;
      _interval = c.dataStart != null && c.dataStop != null
          ? DateTimeRange(start: c.dataStart!, end: c.dataStop!)
          : null;
      _maiMulte = _maiMulte || c.institutie.isNotEmpty || _interval != null;
    });
    _cauta();
  }

  Future<void> _alegeInstanta() async {
    final aleasa = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => const _FoaieInstante(),
    );
    if (aleasa != null) setState(() => _institutie = aleasa);
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
        body: ListView(
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
    );
  }

  Widget _antet() {
    const alb = AppColors.onPrimary;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.hero)),
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
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PORTAL DOSARE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: AppColors.accentContainer,
                          ),
                        ),
                      ),
                      // Până la meniul cu „Utilități”, sugestiile se trimit de aici.
                      IconButton(
                        tooltip: 'Trimite o sugestie',
                        visualDensity: VisualDensity.compact,
                        color: alb,
                        icon: const Icon(Icons.lightbulb_outline),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SugestieScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Caută un dosar',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: alb),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Date preluate direct de pe portal.just.ro',
                    style: TextStyle(fontSize: 14, color: alb.withValues(alpha: 0.8)),
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
                    BoxShadow(color: Color(0x2E0D1433), blurRadius: 24, offset: Offset(0, 8)),
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
                      hint: 'ex. uzucapiune, pretenții (opțional)',
                      icon: Icons.search,
                      controller: _obiectController,
                    ),
                    const SizedBox(height: 14),
                    _camp(
                      eticheta: 'Nume parte',
                      hint: 'ex. SC Exemplu SRL, Popescu Ion (opțional)',
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
    final instanta = _institutie.isEmpty ? 'Toate instanțele' : numeInstanta(_institutie);
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
            icon: Icon(_maiMulte ? Icons.expand_less : Icons.expand_more, size: 20),
            label: const Text('Mai multe criterii'),
          ),
        ),
        if (_maiMulte) ...[
          _selector(
            eticheta: 'Instanța',
            valoare: instanta,
            icon: Icons.account_balance,
            onTap: _alegeInstanta,
            onSterge: _institutie.isEmpty ? null : () => setState(() => _institutie = ''),
          ),
          const SizedBox(height: 10),
          _selector(
            eticheta: 'Înregistrat între',
            valoare: interval,
            icon: Icons.date_range,
            onTap: _alegeInterval,
            onSterge: _interval == null ? null : () => setState(() => _interval = null),
          ),
        ],
      ],
    );
  }

  Widget _selector({
    required String eticheta,
    required String valoare,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onSterge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: eticheta,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: onSterge == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  tooltip: 'Șterge',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onSterge,
                ),
        ),
        child: Text(valoare, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _camp({
    required String eticheta,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eticheta,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _cauta(),
          decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20)),
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
                    Pastila(c.eticheta, icon: Icons.history, onTap: () => _reia(c)),
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
                style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant),
              )
            else
              for (final (s, _) in cuTermen.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DosarCardWidget(key: ValueKey(s.dosar.cheie), dosar: s.dosar, salvat: s),
                ),
          ],
        );
      },
    );
  }
}

/// Lista instanțelor, cu căutare după nume sau județ. Întoarce codul SOAP.
class _FoaieInstante extends StatefulWidget {
  const _FoaieInstante();

  @override
  State<_FoaieInstante> createState() => _FoaieInstanteState();
}

class _FoaieInstanteState extends State<_FoaieInstante> {
  String _text = '';

  static String _simplu(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ăâ]'), 'a')
      .replaceAll('î', 'i')
      .replaceAll(RegExp('[șş]'), 's')
      .replaceAll(RegExp('[țţ]'), 't');

  @override
  Widget build(BuildContext context) {
    final cautat = _simplu(_text.trim());
    final instante = [
      for (final i in toateInstantele)
        if (cautat.isEmpty || _simplu('${i.nume} ${i.judet}').contains(cautat)) i,
    ]..sort((a, b) => a.nume.compareTo(b.nume));

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (t) => setState(() => _text = t),
              decoration: const InputDecoration(
                hintText: 'Caută instanța sau județul',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: instante.length,
              itemBuilder: (context, i) {
                final inst = instante[i];
                return ListTile(
                  title: Text(inst.nume),
                  subtitle: Text(inst.judet),
                  onTap: () => Navigator.of(context).pop(inst.cod),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
