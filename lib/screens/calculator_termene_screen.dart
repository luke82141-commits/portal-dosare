import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/pro_service.dart';
import '../services/termene_procedurale_service.dart';
import '../theme/app_theme.dart';
import '../utils/calendar.dart' show zileleSaptamanii;
import '../utils/formatare.dart';
import 'sincronizare_calendar_screen.dart';

/// „luni, 16.11.2026”.
String dataCuZi(DateTime d) =>
    '${zileleSaptamanii[d.weekday - 1].toLowerCase()}, '
    '${formateazaData(d)}';

String _durataText(int n, UnitateTermen u) => switch (u) {
  UnitateTermen.zile => n == 1 ? '1 zi' : _cuDe(n, 'zile'),
  UnitateTermen.luni => n == 1 ? '1 lună' : _cuDe(n, 'luni'),
  UnitateTermen.ani => n == 1 ? '1 an' : _cuDe(n, 'ani'),
};

String _cuDe(int n, String plural) {
  final rest = n % 100;
  return '$n ${n >= 20 && (rest == 0 || rest >= 20) ? 'de ' : ''}$plural';
}

/// Explicația calculului, pas cu pas, sub rezultat.
List<String> explicatieCalcul(
  DateTime start,
  int durata,
  UnitateTermen unitate,
  CalculTermen c,
) {
  return [
    if (unitate == UnitateTermen.zile)
      'Termenul de ${_durataText(durata, unitate)} se calculează pe zile libere: nu se '
          'socotesc ziua de la care curge (${formateazaData(start)}) și ziua în care se '
          'împlinește. Actul se poate face până pe ${dataCuZi(c.implinire)} inclusiv.'
    else
      'Termenul de ${_durataText(durata, unitate)} se împlinește în ziua corespunzătoare '
          '(${dataCuZi(c.implinire)}); dacă luna nu are o asemenea zi, în ultima zi a lunii.',
    for (final (zi, motiv) in c.prelungiri)
      '${formateazaData(zi)} nu e zi lucrătoare ($motiv), așa că termenul se prelungește.',
    'Actul trimis prin poștă sau curier ori depus electronic până la ora 24 a ultimei zile '
        'se consideră făcut în termen (art. 182–183 CPC).',
  ];
}

/// Calculatorul de termene procedurale (Pro).
class CalculatorTermeneScreen extends StatefulWidget {
  const CalculatorTermeneScreen({super.key});

  @override
  State<CalculatorTermeneScreen> createState() =>
      _CalculatorTermeneScreenState();
}

class _CalculatorTermeneScreenState extends State<CalculatorTermeneScreen> {
  ActProcedural? _act = actePrecompletate.first;
  late final _durata = TextEditingController(
    text: '${actePrecompletate.first.durata}',
  );
  UnitateTermen _unitate = actePrecompletate.first.unitate;
  DateTime? _start;
  String _dosar = '';

  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
    TermeneProceduraleService.instance.incarca();
    CalendarSyncService.instance.incarca();
  }

  @override
  void dispose() {
    _durata.dispose();
    super.dispose();
  }

  int? get _n {
    final n = int.tryParse(_durata.text.trim());
    return n == null || n <= 0 || n > 3650 ? null : n;
  }

  String get _numeAct => _act?.nume ?? 'Termen procedural';

  Future<void> _alegeData() async {
    final azi = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start ?? azi,
      firstDate: DateTime(azi.year - 5),
      lastDate: DateTime(azi.year + 2),
      helpText: 'Data de la care curge termenul',
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _salveaza(CalculTermen c) async {
    final messenger = ScaffoldMessenger.of(context);
    await TermeneProceduraleService.instance.adauga(
      TermenSalvat(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        act: _numeAct,
        numarDosar: _dosar,
        start: _start!,
        ultimaZi: c.ultimaZi,
      ),
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Termen salvat. Îl vei vedea și în rezumatul zilnic.'),
      ),
    );
  }

  Future<void> _inCalendar(CalculTermen c) async {
    final messenger = ScaffoldMessenger.of(context);
    final sync = CalendarSyncService.instance;
    if (!sync.configurat) {
      messenger.showSnackBar(
        SnackBar(
          persist: false,
          showCloseIcon: true,
          content: const Text(
            'Alege întâi calendarul în care trimitem termenele.',
          ),
          action: SnackBarAction(
            label: 'Alege',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SincronizareCalendarScreen(),
              ),
            ),
          ),
        ),
      );
      return;
    }
    try {
      final zi = c.ultimaZi;
      await sync.calendareTelefon.creeaza(
        calendarId: sync.calendarId!,
        titlu:
            'Ultima zi: $_numeAct${_dosar.isEmpty ? '' : ' · dosar $_dosar'}',
        start: zi,
        sfarsit: DateTime(zi.year, zi.month, zi.day + 1),
        totaZiua: true,
        descriere: [
          'Termen calculat de la ${formateazaData(_start)}'
              ' (${_durataText(_n!, _unitate)}).',
          if (_act != null) 'Temei: ${_act!.temei}.',
        ].join('\n'),
        locatie: '',
        // Cu o zi înainte, la ora 9.
        amintire: const Duration(hours: 15),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Adăugat în calendarul „${sync.numeCalendar ?? ''}”.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Nu am putut adăuga în calendar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calculator termene')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          ProService.instance,
          TermeneProceduraleService.instance,
        ]),
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          final n = _n;
          final calcul = n == null || _start == null
              ? null
              : calculeazaTermen(_start!, n, _unitate);
          final numere = {
            for (final s in BibliotecaService.instance.dosare) s.dosar.numar,
          }.toList()..sort();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              DropdownButtonFormField<ActProcedural?>(
                initialValue: _act,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Actul'),
                items: [
                  for (final a in actePrecompletate)
                    DropdownMenuItem(value: a, child: Text(a.nume)),
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Alt termen'),
                  ),
                ],
                onChanged: (a) => setState(() {
                  _act = a;
                  if (a != null) {
                    _durata.text = '${a.durata}';
                    _unitate = a.unitate;
                  }
                }),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _durata,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Durata',
                        errorText: _durata.text.isNotEmpty && n == null
                            ? 'Invalid'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<UnitateTermen>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: UnitateTermen.zile,
                          label: Text('zile'),
                        ),
                        ButtonSegment(
                          value: UnitateTermen.luni,
                          label: Text('luni'),
                        ),
                        ButtonSegment(
                          value: UnitateTermen.ani,
                          label: Text('ani'),
                        ),
                      ],
                      selected: {_unitate},
                      onSelectionChanged: (s) =>
                          setState(() => _unitate = s.first),
                    ),
                  ),
                ],
              ),
              if (_act != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Curge de la ${_act!.deLa} · ${_act!.temei}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _alegeData,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de la care curge',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _start == null ? 'Alege data' : dataCuZi(_start!),
                    style: TextStyle(
                      fontSize: 16,
                      color: _start == null ? AppColors.onSurfaceVariant : null,
                    ),
                  ),
                ),
              ),
              if (numere.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _dosar,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Dosarul (opțional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Fără dosar'),
                    ),
                    for (final nr in numere)
                      DropdownMenuItem(value: nr, child: Text(nr)),
                  ],
                  onChanged: (v) => setState(() => _dosar = v ?? ''),
                ),
              ],
              const SizedBox(height: 20),
              if (calcul != null)
                _Rezultat(
                  calcul: calcul,
                  explicatie: explicatieCalcul(_start!, n!, _unitate, calcul),
                  onSalveaza: () => _salveaza(calcul),
                  onCalendar: () => _inCalendar(calcul),
                ),
              _TermeneSalvate(TermeneProceduraleService.instance.termene),
            ],
          );
        },
      ),
    );
  }
}

class _Rezultat extends StatelessWidget {
  final CalculTermen calcul;
  final List<String> explicatie;
  final VoidCallback onSalveaza;
  final VoidCallback onCalendar;

  const _Rezultat({
    required this.calcul,
    required this.explicatie,
    required this.onSalveaza,
    required this.onCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final ramase = calcul.ultimaZi
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ultima zi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dataCuZi(calcul.ultimaZi),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              switch (ramase) {
                < 0 => 'Termenul a expirat.',
                0 => 'Azi e ultima zi.',
                1 => 'Mâine e ultima zi.',
                _ => 'Mai sunt $ramase zile.',
              },
              style: TextStyle(
                fontSize: 13,
                color: ramase <= 1
                    ? AppColors.error
                    : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final e in explicatie)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  e,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onSalveaza,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Salvează'),
                ),
                OutlinedButton.icon(
                  onPressed: onCalendar,
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('Adaugă în calendar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TermeneSalvate extends StatelessWidget {
  final List<TermenSalvat> termene;
  const _TermeneSalvate(this.termene);

  @override
  Widget build(BuildContext context) {
    if (termene.isEmpty) return const SizedBox.shrink();
    final azi = DateUtils.dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Termenele salvate',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          for (final t in termene)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.timer_outlined,
                color: t.ultimaZi.isBefore(azi)
                    ? AppColors.onSurfaceVariant
                    : AppColors.primary,
              ),
              title: Text(t.act),
              subtitle: Text(
                [
                  'Ultima zi: ${dataCuZi(t.ultimaZi)}',
                  if (t.numarDosar.isNotEmpty) 'dosar ${t.numarDosar}',
                ].join(' · '),
              ),
              trailing: IconButton(
                tooltip: 'Șterge',
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    TermeneProceduraleService.instance.sterge(t.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _Blocat extends StatelessWidget {
  const _Blocat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium_outlined,
              size: 48,
              color: AppColors.accent,
            ),
            const SizedBox(height: 12),
            const Text(
              'Disponibil în Portal Dosare Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Calculează ultima zi pentru apel, recurs, întâmpinare și alte acte.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
