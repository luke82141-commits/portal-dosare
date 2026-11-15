import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/pro_service.dart';
import '../services/raport_service.dart' show TipSolutie, lunileAnului;
import '../services/statistici_service.dart';
import '../theme/app_theme.dart';

/// Culorile seriilor (ordine fixă, validată pentru daltonism): admite,
/// admite în parte, respinge, alte soluții.
const _culoriSolutii = {
  TipSolutie.admite: Color(0xFF2A78D6),
  TipSolutie.admiteInParte: Color(0xFFEB6834),
  TipSolutie.respinge: Color(0xFF1BAF7A),
  TipSolutie.alta: Color(0xFFEDA100),
};
const _anCurent = Color(0xFF2A78D6);
const _anTrecut = Color(0xFFC9CDD6);

const _luniScurte = ['I', 'F', 'M', 'A', 'M', 'I', 'I', 'A', 'S', 'O', 'N', 'D'];

/// „Statistici” (Pro): dosarele urmărite pe un an, comparate cu anul trecut.
class StatisticiScreen extends StatefulWidget {
  const StatisticiScreen({super.key});

  @override
  State<StatisticiScreen> createState() => _StatisticiScreenState();
}

enum _Masura { termene, dosare }

class _StatisticiScreenState extends State<StatisticiScreen> {
  int _an = DateTime.now().year;
  _Masura _masura = _Masura.termene;

  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistici')),
      body: ListenableBuilder(
        listenable: Listenable.merge([ProService.instance, BibliotecaService.instance]),
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          final s = calculeazaStatistici(BibliotecaService.instance.dosare, _an);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Anul anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _an--),
                  ),
                  Expanded(
                    child: Text(
                      'Anul $_an',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Anul următor',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _an >= DateTime.now().year + 1 ? null : () => setState(() => _an++),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: [
                  _Cifra(
                    eticheta: 'Termene de judecată',
                    valoare: s.totalTermene,
                    detaliu: variatie(s.totalTermene, s.totalTermeneAnTrecut, _an - 1),
                  ),
                  _Cifra(
                    eticheta: 'Dosare înregistrate',
                    valoare: s.totalDosare,
                    detaliu: variatie(s.totalDosare, s.totalDosareAnTrecut, _an - 1),
                  ),
                  _Cifra(eticheta: 'Hotărâri pronunțate', valoare: s.totalHotarari),
                  _Cifra(
                    eticheta: 'Termene amânate',
                    valoare: s.amanari,
                    detaliu: s.totalTermene == 0
                        ? ''
                        : '${(s.amanari * 100 / s.totalTermene).round()}% din termene',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Sectiune(
                titlu: 'Pe luni',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<_Masura>(
                      segments: const [
                        ButtonSegment(value: _Masura.termene, label: Text('Termene')),
                        ButtonSegment(value: _Masura.dosare, label: Text('Dosare noi')),
                      ],
                      selected: {_masura},
                      showSelectedIcon: false,
                      onSelectionChanged: (m) => setState(() => _masura = m.first),
                    ),
                    const SizedBox(height: 16),
                    _GraficLuni(
                      an: _an,
                      curent: _masura == _Masura.termene ? s.termene : s.dosareInregistrate,
                      trecut: _masura == _Masura.termene
                          ? s.termeneAnTrecut
                          : s.dosareInregistrateAnTrecut,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      children: [
                        _Legenda(culoare: _anCurent, text: '$_an'),
                        _Legenda(culoare: _anTrecut, text: '${_an - 1}'),
                      ],
                    ),
                  ],
                ),
              ),
              _Sectiune(
                titlu: 'Soluții',
                child: s.totalHotarari == 0
                    ? const _Gol('Nicio hotărâre pronunțată în acest an.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _BaraSolutii(s.solutii),
                          const SizedBox(height: 12),
                          for (final t in ordineSolutii)
                            if (t != TipSolutie.alta || (s.solutii[t] ?? 0) > 0)
                              _RandSolutie(
                                tip: t,
                                numar: s.solutii[t] ?? 0,
                                total: s.totalHotarari,
                              ),
                        ],
                      ),
              ),
              if (s.solutiiPeFaze.length > 1 ||
                  (s.solutiiPeFaze.length == 1 && s.totalHotarari > 0))
                _Sectiune(
                  titlu: 'Soluții pe faze procesuale',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in s.solutiiPeFaze.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    _detaliiFaza(e.value),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              _BaraSolutii(e.value, inaltime: 10),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              _Sectiune(
                titlu: 'Instanțe cu cele mai multe termene',
                child: s.instante.isEmpty
                    ? const _Gol('Niciun termen în acest an.')
                    : Column(
                        children: [
                          for (final (nume, n) in s.instante)
                            _RandInstanta(nume: nume, numar: n, maxim: s.instante.first.$2),
                        ],
                      ),
              ),
              const Text(
                'Cifrele privesc dosarele urmărite în aplicație, cu datele publicate pe '
                'portal la ultima verificare.',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _detaliiFaza(Map<TipSolutie, int> m) {
    final total = m.values.fold(0, (a, b) => a + b);
    return '$total ${total == 1 ? 'hotărâre' : 'hotărâri'}';
  }
}

class _Sectiune extends StatelessWidget {
  final String titlu;
  final Widget child;
  const _Sectiune({required this.titlu, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titlu, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  final String eticheta;
  final int valoare;
  final String detaliu;
  const _Cifra({required this.eticheta, required this.valoare, this.detaliu = ''});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              eticheta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              '$valoare',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            if (detaliu.isNotEmpty)
              Text(
                detaliu,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bare pe luni: anul ales lângă anul trecut. Atingerea unei luni arată
/// valorile.
class _GraficLuni extends StatelessWidget {
  final int an;
  final List<int> curent;
  final List<int> trecut;
  const _GraficLuni({required this.an, required this.curent, required this.trecut});

  @override
  Widget build(BuildContext context) {
    final maxim = math.max(1, [...curent, ...trecut].reduce(math.max));
    const inaltime = 120.0;
    Widget bara(int v, Color c) => Container(
      width: 7,
      height: v == 0 ? 0 : math.max(2, inaltime * v / maxim),
      decoration: BoxDecoration(
        color: c,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    );

    return Column(
      children: [
        SizedBox(
          height: inaltime + 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 12; i++)
                Expanded(
                  child: Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    message:
                        '${lunileAnului[i][0].toUpperCase()}${lunileAnului[i].substring(1)}\n'
                        '$an: ${curent[i]}\n${an - 1}: ${trecut[i]}',
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (curent[i] > 0)
                            Text(
                              '${curent[i]}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              bara(curent[i], _anCurent),
                              const SizedBox(width: 2),
                              bara(trecut[i], _anTrecut),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.outline),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final l in _luniScurte)
              Expanded(
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// O bară împărțită pe felul soluțiilor, cu 2 px între segmente.
class _BaraSolutii extends StatelessWidget {
  final Map<TipSolutie, int> solutii;
  final double inaltime;
  const _BaraSolutii(this.solutii, {this.inaltime = 16});

  @override
  Widget build(BuildContext context) {
    final parti = [
      for (final t in ordineSolutii)
        if ((solutii[t] ?? 0) > 0) (t, solutii[t]!),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: inaltime,
        child: Row(
          children: [
            for (final (i, (t, n)) in parti.indexed)
              Expanded(
                flex: n,
                child: Container(
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                  color: _culoriSolutii[t],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RandSolutie extends StatelessWidget {
  final TipSolutie tip;
  final int numar;
  final int total;
  const _RandSolutie({required this.tip, required this.numar, required this.total});

  @override
  Widget build(BuildContext context) {
    final procent = total == 0 ? 0 : (numar * 100 / total).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _Legenda(culoare: _culoriSolutii[tip]!, text: numeSolutie(tip)),
          const Spacer(),
          Text('$numar', style: const TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(
            width: 48,
            child: Text(
              '$procent%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _RandInstanta extends StatelessWidget {
  final String nume;
  final int numar;
  final int maxim;
  const _RandInstanta({required this.nume, required this.numar, required this.maxim});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(nume, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('$numar', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: maxim == 0 ? 0 : numar / maxim,
              child: Container(
                height: 6,
                decoration: BoxDecoration(color: _anCurent, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  final Color culoare;
  final String text;
  const _Legenda({required this.culoare, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: culoare, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _Gol extends StatelessWidget {
  final String text;
  const _Gol(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AppColors.onSurfaceVariant));
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
            const Icon(Icons.workspace_premium_outlined, size: 48, color: AppColors.accent),
            const SizedBox(height: 12),
            const Text(
              'Disponibil în Portal Dosare Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Termene, dosare și soluții pe ani și luni, comparate cu anul trecut.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
