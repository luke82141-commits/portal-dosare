import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/calendar.dart';
import 'dosar_detaliu_screen.dart';

enum VedereCalendar { zi, saptamana, luna, an }

const _initialeZile = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];

/// Termenele dosarelor monitorizate într-un calendar cu vederi pe zi,
/// săptămână, lună și an, după modelul Google Calendar.
class CalendarScreen extends StatefulWidget {
  /// Se poate fixa în teste.
  final DateTime? azi;

  const CalendarScreen({super.key, this.azi});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  VedereCalendar _vedere = VedereCalendar.luna;
  late DateTime _focus = _azi;

  DateTime get _azi => DateUtils.dateOnly(widget.azi ?? DateTime.now());

  void _muta(int pas) => setState(() {
        final f = _focus;
        _focus = switch (_vedere) {
          VedereCalendar.zi => DateTime(f.year, f.month, f.day + pas),
          VedereCalendar.saptamana => DateTime(f.year, f.month, f.day + 7 * pas),
          VedereCalendar.luna => DateTime(f.year, f.month + pas),
          VedereCalendar.an => DateTime(f.year + pas, f.month),
        };
      });

  void _deschide(VedereCalendar vedere, DateTime zi) => setState(() {
        _vedere = vedere;
        _focus = zi;
      });

  String get _titlu {
    final f = _focus;
    switch (_vedere) {
      case VedereCalendar.zi:
        final an = f.year == _azi.year ? '' : ' ${f.year}';
        return '${zileleSaptamanii[f.weekday - 1]}, ${f.day} ${lunileAnului[f.month - 1].toLowerCase()}$an';
      case VedereCalendar.saptamana:
        final s = inceputSaptamana(f);
        final d = DateTime(s.year, s.month, s.day + 6);
        if (s.month == d.month) return '${s.day} – ${d.day} ${_scurt(s.month)} ${d.year}';
        return '${s.day} ${_scurt(s.month)} – ${d.day} ${_scurt(d.month)} ${d.year}';
      case VedereCalendar.luna:
        return '${lunileAnului[f.month - 1]} ${f.year}';
      case VedereCalendar.an:
        return '${f.year}';
    }
  }

  static String _scurt(int luna) => '${lunileAnului[luna - 1].substring(0, 3).toLowerCase()}.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final termene = termenePeZile([
            for (final s in BibliotecaService.instance.dosare) s.dosar,
          ]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(bottom: false, child: _antet()),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -250) _muta(1);
                    if (v > 250) _muta(-1);
                  },
                  child: switch (_vedere) {
                    VedereCalendar.zi => _GrilaOre(
                        key: ValueKey('zi$_focus'),
                        zile: [_focus],
                        termene: termene,
                        azi: _azi,
                        detaliat: true,
                      ),
                    VedereCalendar.saptamana => _GrilaOre(
                        key: ValueKey('sapt${inceputSaptamana(_focus)}'),
                        zile: [
                          for (var i = 0; i < 7; i++)
                            DateTime(_focus.year, _focus.month, _focus.day - (_focus.weekday - 1) + i),
                        ],
                        termene: termene,
                        azi: _azi,
                        onZi: (z) => _deschide(VedereCalendar.zi, z),
                      ),
                    VedereCalendar.luna => _Luna(
                        luna: _focus,
                        termene: termene,
                        azi: _azi,
                        onZi: (z) => _deschide(VedereCalendar.zi, z),
                      ),
                    VedereCalendar.an => _An(
                        an: _focus.year,
                        termene: termene,
                        azi: _azi,
                        onLuna: (l) => _deschide(VedereCalendar.luna, l),
                      ),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _antet() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titlu,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Înapoi',
                onPressed: () => _muta(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Înainte',
                onPressed: () => _muta(1),
                icon: const Icon(Icons.chevron_right),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => setState(() => _focus = _azi),
                child: const Text('Azi'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<VedereCalendar>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              selectedBackgroundColor: AppColors.primaryContainer,
              selectedForegroundColor: AppColors.onPrimaryContainer,
            ),
            segments: const [
              ButtonSegment(value: VedereCalendar.zi, label: Text('Zi')),
              ButtonSegment(value: VedereCalendar.saptamana, label: Text('Săpt.')),
              ButtonSegment(value: VedereCalendar.luna, label: Text('Lună')),
              ButtonSegment(value: VedereCalendar.an, label: Text('An')),
            ],
            selected: {_vedere},
            onSelectionChanged: (s) => setState(() => _vedere = s.first),
          ),
        ],
      ),
    );
  }
}

void _deschideDosar(BuildContext context, Termen t) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: t.dosar)),
    );

/// Numărul zilei, încercuit dacă e azi.
class _NumarZi extends StatelessWidget {
  final DateTime zi;
  final bool azi;
  final bool estompat;
  final double marime;

  const _NumarZi(this.zi, {this.azi = false, this.estompat = false, this.marime = 24});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: marime,
      height: marime,
      alignment: Alignment.center,
      decoration: azi ? const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle) : null,
      child: Text(
        '${zi.day}',
        style: TextStyle(
          fontSize: marime * 0.5,
          fontWeight: azi ? FontWeight.bold : FontWeight.w500,
          color: azi
              ? AppColors.onPrimary
              : estompat
                  ? AppColors.onSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.onSurface,
        ),
      ),
    );
  }
}

/// Un termen ca bandă colorată, în vederea lunii și pe rândul „fără oră”.
class _Banda extends StatelessWidget {
  final Termen t;
  final VoidCallback? onTap;

  /// În grila lunii celula e îngustă: doar numărul, fără anul curent.
  final bool scurt;

  const _Banda(this.t, {this.onTap, this.scurt = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: t.trecut ? t.culoare.withValues(alpha: 0.45) : t.culoare,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap ?? () => _deschideDosar(context, t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              scurt
                  ? t.dosar.numar.replaceFirst(RegExp('/${t.zi.year}\$'), '')
                  : [if (t.ora.isNotEmpty) t.ora, t.dosar.numar].join(' '),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: const TextStyle(fontSize: 10, height: 1.3, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Lună ─────────────────────────────────────────────────────────────────

class _Luna extends StatelessWidget {
  final DateTime luna;
  final Map<DateTime, List<Termen>> termene;
  final DateTime azi;
  final ValueChanged<DateTime> onZi;

  const _Luna({required this.luna, required this.termene, required this.azi, required this.onZi});

  @override
  Widget build(BuildContext context) {
    final zile = zileGrilaLuna(luna);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (final z in _initialeZile)
                Expanded(
                  child: Text(
                    z,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var r = 0; r < 6; r++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < 7; c++) Expanded(child: _celula(context, zile[r * 7 + c])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _celula(BuildContext context, DateTime zi) {
    final ale = termene[zi] ?? const <Termen>[];
    return InkWell(
      onTap: () => onZi(zi),
      child: Container(
        decoration: BoxDecoration(
          color: zi.weekday >= 6 ? AppColors.surfaceVariant.withValues(alpha: 0.5) : null,
          border: const Border(
            top: BorderSide(color: AppColors.outline, width: 0.5),
            left: BorderSide(color: AppColors.outline, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 2),
        child: LayoutBuilder(
          builder: (context, c) {
            // Câte benzi încap sub număr (24 px), fiecare de ~17 px.
            final loc = ((c.maxHeight - 26) / 17).floor().clamp(0, 99);
            final vizibile = ale.length <= loc ? ale.length : (loc - 1).clamp(0, ale.length);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _NumarZi(
                    zi,
                    azi: DateUtils.isSameDay(zi, azi),
                    estompat: zi.month != luna.month,
                  ),
                ),
                const SizedBox(height: 2),
                for (final t in ale.take(vizibile)) _Banda(t, scurt: true, onTap: () => onZi(zi)),
                if (ale.length > vizibile)
                  Text(
                    '+${ale.length - vizibile}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Zi și săptămână ──────────────────────────────────────────────────────

class _GrilaOre extends StatefulWidget {
  final List<DateTime> zile;
  final Map<DateTime, List<Termen>> termene;
  final DateTime azi;

  /// Vederea pe o zi: blocuri late, cu instanța și obiectul.
  final bool detaliat;
  final ValueChanged<DateTime>? onZi;

  const _GrilaOre({
    super.key,
    required this.zile,
    required this.termene,
    required this.azi,
    this.detaliat = false,
    this.onZi,
  });

  @override
  State<_GrilaOre> createState() => _GrilaOreState();
}

class _GrilaOreState extends State<_GrilaOre> {
  static const _latimeOre = 48.0;
  late final double _ora = widget.detaliat ? 72 : 56;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Pornește de la primul termen din interval sau, dacă nu e niciunul, de la 08:00.
    final minute = [
      for (final z in widget.zile)
        for (final t in widget.termene[z] ?? const <Termen>[])
          if (t.minut != null) t.minut!,
    ];
    final start = minute.isEmpty ? 8 * 60 : (minute.reduce((a, b) => a < b ? a : b) - 30);
    _scroll = ScrollController(initialScrollOffset: (start.clamp(0, 24 * 60) / 60) * _ora);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faraOra = [
      for (final z in widget.zile)
        [for (final t in widget.termene[z] ?? const <Termen>[]) if (t.minut == null) t],
    ];
    final areFaraOra = faraOra.any((l) => l.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.detaliat)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const SizedBox(width: _latimeOre),
                for (final z in widget.zile)
                  Expanded(
                    child: InkWell(
                      onTap: widget.onZi == null ? null : () => widget.onZi!(z),
                      child: Column(
                        children: [
                          Text(
                            _initialeZile[z.weekday - 1],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DateUtils.isSameDay(z, widget.azi)
                                  ? AppColors.primary
                                  : AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _NumarZi(z, azi: DateUtils.isSameDay(z, widget.azi), marime: 28),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (areFaraOra)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: _latimeOre,
                  child: Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'fără\noră',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, height: 1.1, color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
                for (final l in faraOra)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final t in l) _Banda(t)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * _ora,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _latimeOre, child: _eticheteOre()),
                  for (final z in widget.zile) Expanded(child: _coloana(z)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _eticheteOre() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var h = 1; h < 24; h++)
          Positioned(
            top: h * _ora - 7,
            right: 8,
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _coloana(DateTime zi) {
    final cuOra = [for (final t in widget.termene[zi] ?? const <Termen>[]) if (t.minut != null) t];
    final coloane = coloaneSuprapuse(cuOra);
    final acum = DateTime.now();
    final eAzi = DateUtils.isSameDay(zi, acum);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.outline, width: 0.5)),
          ),
          child: Stack(
            children: [
              for (var h = 1; h < 24; h++)
                Positioned(
                  top: h * _ora,
                  left: 0,
                  right: 0,
                  child: const Divider(height: 0.5, thickness: 0.5),
                ),
              for (final (i, t) in cuOra.indexed)
                Positioned(
                  top: t.minut! / 60 * _ora + 1,
                  height: _ora - 2,
                  left: coloane[i].$1 * w / coloane[i].$2 + 1,
                  width: w / coloane[i].$2 - 3,
                  child: _Bloc(t, detaliat: widget.detaliat),
                ),
              if (eAzi)
                Positioned(
                  top: (acum.hour * 60 + acum.minute) / 60 * _ora - 1,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                      ),
                      Expanded(child: Container(height: 2, color: AppColors.error)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Termenul ca bloc în grila de ore.
class _Bloc extends StatelessWidget {
  final Termen t;
  final bool detaliat;

  const _Bloc(this.t, {this.detaliat = false});

  @override
  Widget build(BuildContext context) {
    const alb = TextStyle(color: Colors.white, fontSize: 11, height: 1.25);
    return Material(
      color: t.trecut ? t.culoare.withValues(alpha: 0.5) : t.culoare,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _deschideDosar(context, t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 3, 4, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.dosar.numar,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: alb.copyWith(fontWeight: FontWeight.w600, fontSize: detaliat ? 13 : 11),
              ),
              Text(
                detaliat
                    ? [t.ora, t.dosar.instanta, if (t.sedinta.complet.isNotEmpty) 'Complet ${t.sedinta.complet}']
                        .join(' · ')
                    : t.ora,
                maxLines: detaliat ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: alb,
              ),
              if (detaliat && t.dosar.obiect.isNotEmpty)
                Text(
                  t.dosar.obiect,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: alb.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── An ───────────────────────────────────────────────────────────────────

class _An extends StatelessWidget {
  final int an;
  final Map<DateTime, List<Termen>> termene;
  final DateTime azi;
  final ValueChanged<DateTime> onLuna;

  const _An({required this.an, required this.termene, required this.azi, required this.onLuna});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.78,
      children: [for (var l = 1; l <= 12; l++) _lunaMica(DateTime(an, l))],
    );
  }

  Widget _lunaMica(DateTime luna) {
    final zile = zileGrilaLuna(luna);
    final lunaCurenta = luna.year == azi.year && luna.month == azi.month;
    final numar = [
      for (final z in zile)
        if (z.month == luna.month) ...termene[z] ?? const <Termen>[],
    ].length;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onLuna(luna),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: lunaCurenta ? AppColors.primary : AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lunileAnului[luna.month - 1],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: lunaCurenta ? AppColors.primary : AppColors.onSurface,
                      ),
                    ),
                  ),
                  if (numar > 0)
                    Text(
                      '$numar',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final z in _initialeZile)
                    Expanded(
                      child: Text(
                        z[0],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 8, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Column(
                  children: [
                    for (var r = 0; r < 6; r++)
                      Expanded(
                        child: Row(
                          children: [
                            for (var c = 0; c < 7; c++) Expanded(child: _ziMica(zile[r * 7 + c], luna)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ziMica(DateTime zi, DateTime luna) {
    if (zi.month != luna.month) return const SizedBox();
    final ale = termene[zi];
    final eAzi = DateUtils.isSameDay(zi, azi);
    final areTermene = ale != null && ale.isNotEmpty;
    return Center(
      child: Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: areTermene ? ale.first.culoare : null,
          border: eAzi ? Border.all(color: AppColors.primary, width: 1.5) : null,
        ),
        child: Text(
          '${zi.day}',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: areTermene || eAzi ? FontWeight.bold : FontWeight.w400,
            color: areTermene ? Colors.white : AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}
