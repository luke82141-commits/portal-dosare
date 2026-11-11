import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/calendar_sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/termene.dart';

/// Sincronizarea termenelor cu Google Calendar / iCloud (calendarele din
/// telefon), în ambele sensuri.
class SincronizareCalendarScreen extends StatefulWidget {
  const SincronizareCalendarScreen({super.key});

  @override
  State<SincronizareCalendarScreen> createState() => _SincronizareCalendarScreenState();
}

class _SincronizareCalendarScreenState extends State<SincronizareCalendarScreen> {
  final _sync = CalendarSyncService.instance;
  List<CalendarTelefon>? _calendare;
  Object? _eroare;
  bool _lucreaza = false;

  late Set<String> _alese;
  List<DosarDinCalendar>? _gasite;
  final Set<String> _deAdaugat = {};

  static const _amintiri = [
    (Duration(minutes: 30), '30 de minute'),
    (Duration(hours: 1), 'o oră'),
    (Duration(hours: 2), '2 ore'),
    (Duration(days: 1), 'o zi'),
  ];

  @override
  void initState() {
    super.initState();
    final toate = {for (final s in BibliotecaService.instance.dosare) s.dosar.cheie};
    _alese = _sync.dosareAlese == null ? toate : toate.intersection(_sync.dosareAlese!);
    _incarcaCalendare();
  }

  Future<void> _incarcaCalendare() async {
    setState(() => _eroare = null);
    try {
      final c = await _sync.calendareTelefon.calendare();
      if (mounted) setState(() => _calendare = c);
    } catch (e) {
      if (mounted) setState(() => _eroare = e);
    }
  }

  void _mesaj(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _trimite() async {
    final toate = {for (final s in BibliotecaService.instance.dosare) s.dosar.cheie};
    _sync.dosareAlese = _alese.length == toate.length ? null : {..._alese};
    setState(() => _lucreaza = true);
    try {
      final r = await _sync.trimite([for (final s in BibliotecaService.instance.dosare) s.dosar]);
      final n = _alese.length;
      _mesaj(r.adaugate == 0
          ? 'Calendarul era deja la zi.'
          : '${n == 1 ? 'Un dosar sincronizat' : '$n dosare sincronizate'} în calendar.');
    } catch (e) {
      _mesaj('Sincronizarea a eșuat: $e');
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  Future<void> _cauta() async {
    final ids = [for (final c in _calendare ?? const <CalendarTelefon>[]) c.id];
    setState(() => _lucreaza = true);
    try {
      final g = await _sync.cautaInCalendare(ids);
      setState(() {
        _gasite = g;
        _deAdaugat
          ..clear()
          ..addAll(g.map((e) => e.numar));
      });
    } catch (e) {
      _mesaj('Nu am putut citi calendarele: $e');
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  Future<void> _adauga() async {
    final alese = [for (final g in _gasite!) if (_deAdaugat.contains(g.numar)) g];
    setState(() => _lucreaza = true);
    try {
      final (n, negasite) = await _sync.adaugaInBiblioteca(alese);
      _mesaj([
        n == 1 ? 'Un dosar adăugat în bibliotecă.' : '$n dosare adăugate în bibliotecă.',
        if (negasite.isNotEmpty) 'Negăsite pe portal: ${negasite.join(', ')}.',
      ].join(' '));
      setState(() => _gasite = null);
    } catch (e) {
      _mesaj('Adăugarea a eșuat: $e');
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizare calendar'),
        bottom: _lucreaza
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([BibliotecaService.instance, _sync]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Dosarele apar în calendarul ales (Google, iCloud sau altul configurat în telefon), '
              'la data și ora fiecărei ședințe, cu instanța ca locație. Așa, Google Calendar și Maps '
              'îți pot spune când să pleci ca să ajungi la timp. Nimic nu se șterge și nimic nu se dublează.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _cardCalendar(),
            const SizedBox(height: 16),
            _cardDosare(),
            const SizedBox(height: 16),
            _cardImport(),
          ],
        ),
      ),
    );
  }

  Widget _titlu(String t, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _cardCalendar() {
    Widget continut;
    if (_eroare != null) {
      continut = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nu am acces la calendare. Permite accesul la calendar pentru aplicație.\n\n$_eroare',
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _incarcaCalendare, child: const Text('Încearcă din nou')),
        ],
      );
    } else if (_calendare == null) {
      continut = const Text('Caut calendarele din telefon…', style: TextStyle(color: AppColors.onSurfaceVariant));
    } else if (_calendare!.isEmpty) {
      continut = const Text(
        'Nu am găsit niciun calendar. Adaugă contul Google sau iCloud în setările telefonului.',
        style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
      );
    } else {
      continut = RadioGroup<String>(
        groupValue: _sync.calendarId,
        onChanged: (id) {
          final c = _calendare!.firstWhere((c) => c.id == id);
          _sync
            ..calendarId = c.id
            ..numeCalendar = '${c.nume} (${c.cont})';
          _sync.salveaza();
        },
        child: Column(
          children: [
            for (final c in _calendare!)
              RadioListTile<String>(
                value: c.id,
                contentPadding: EdgeInsets.zero,
                dense: true,
                secondary: CircleAvatar(radius: 7, backgroundColor: c.culoare),
                title: Text(c.nume, style: const TextStyle(fontSize: 15)),
                subtitle: Text(c.cont, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titlu('Calendarul sincronizat', Icons.event_available),
            continut,
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Amintire înainte de termen', style: TextStyle(fontSize: 14))),
                DropdownButton<Duration>(
                  value: _sync.amintire,
                  underline: const SizedBox(),
                  items: [
                    for (final (d, t) in _amintiri) DropdownMenuItem(value: d, child: Text(t)),
                  ],
                  onChanged: (d) {
                    _sync.amintire = d!;
                    _sync.salveaza();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardDosare() {
    final dosare = BibliotecaService.instance.dosare;
    final toate = dosare.isNotEmpty && _alese.length == dosare.length;
    final alese = dosare.where((s) => _alese.contains(s.dosar.cheie)).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titlu('Dosarele sincronizate', Icons.checklist),
            if (dosare.isEmpty)
              const Text('Biblioteca e goală.', style: TextStyle(color: AppColors.onSurfaceVariant))
            else ...[
              CheckboxListTile(
                value: toate,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Toate dosarele', style: TextStyle(fontWeight: FontWeight.w600)),
                onChanged: (v) => setState(() {
                  _alese = v == true ? {for (final s in dosare) s.dosar.cheie} : {};
                }),
              ),
              const Divider(),
              for (final s in dosare)
                CheckboxListTile(
                  value: _alese.contains(s.dosar.cheie),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(s.dosar.numar, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${s.dosar.instanta} · ${rezumatTermen(s.dosar)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (v) => setState(() {
                    v == true ? _alese.add(s.dosar.cheie) : _alese.remove(s.dosar.cheie);
                  }),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _lucreaza || !_sync.configurat || alese == 0 ? null : _trimite,
                icon: const Icon(Icons.sync),
                label: Text(alese == 0
                    ? 'Bifează dosarele de sincronizat'
                    : 'Sincronizează ${alese == 1 ? 'un dosar' : '$alese dosare'} în calendar'),
              ),
              if (!_sync.configurat)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Alege întâi un calendar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ),
              if (_sync.ultimaSincronizare != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Ultima sincronizare: ${formateazaDataOra(_sync.ultimaSincronizare)}'
                    '${_sync.numeCalendar == null ? '' : ' · ${_sync.numeCalendar}'}. '
                    'Dosarele se sincronizează automat când deschizi aplicația.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardImport() {
    final g = _gasite;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titlu('Adaugă din calendar', Icons.download),
            const Text(
              'Caut numere de dosar în evenimentele din calendarele tale și le adaug în bibliotecă. '
              'Dosarele pe care le ai deja nu se dublează.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (g == null)
              OutlinedButton.icon(
                onPressed: _lucreaza || (_calendare?.isEmpty ?? true) ? null : _cauta,
                icon: const Icon(Icons.search),
                label: const Text('Caută dosare în calendare'),
              )
            else if (g.isEmpty)
              const Text(
                'Nu am găsit dosare noi în calendare.',
                style: TextStyle(fontWeight: FontWeight.w500),
              )
            else ...[
              for (final d in g)
                CheckboxListTile(
                  value: _deAdaugat.contains(d.numar),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(d.numar, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${formateazaData(d.eveniment.start)} · ${d.eveniment.titlu}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (v) => setState(() {
                    v == true ? _deAdaugat.add(d.numar) : _deAdaugat.remove(d.numar);
                  }),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _lucreaza || _deAdaugat.isEmpty ? null : _adauga,
                icon: const Icon(Icons.library_add),
                label: Text('Adaugă ${_deAdaugat.length == 1 ? 'un dosar' : '${_deAdaugat.length} dosare'}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
