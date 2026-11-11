import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../widgets/elemente.dart';
import 'dosar_detaliu_screen.dart';

/// Modificările detectate la dosarele monitorizate, cele mai noi primele
/// (Figma: „05 · Notificări”).
class NotificariScreen extends StatelessWidget {
  const NotificariScreen({super.key});

  Future<void> _marcheazaToate() async {
    final b = BibliotecaService.instance;
    for (final d in b.dosare.where((d) => d.necitite > 0).toList()) {
      await b.marcheazaCitit(d.dosar.cheie);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final biblioteca = BibliotecaService.instance;
          final elemente = <_Element>[
            for (final s in biblioteca.dosare)
              for (var i = 0; i < s.modificari.length; i++)
                _Element(s.dosar, s.modificari[i], necitit: i < s.necitite),
          ]..sort((a, b) => b.modificare.detectataLa.compareTo(a.modificare.detectataLa));

          final azi = DateUtils.dateOnly(DateTime.now());
          final deAzi = elemente.where((e) => !e.modificare.detectataLa.isBefore(azi)).toList();
          final vechi = elemente.where((e) => e.modificare.detectataLa.isBefore(azi)).toList();

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificări',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Alerte despre dosarele pe care le monitorizezi',
                              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (biblioteca.totalNecitite > 0)
                        TextButton(
                          onPressed: _marcheazaToate,
                          child: const Text('Marchează citite'),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: elemente.isEmpty
                    ? const StareMesaj(
                        icon: Icons.notifications_none,
                        titlu: 'Nicio notificare',
                        text: 'Când apare un termen nou sau o soluție la un dosar '
                            'monitorizat, o vei vedea aici.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (deAzi.isNotEmpty) ...[
                            const _Grup('AZI'),
                            for (final e in deAzi) _NotificareRand(e),
                          ],
                          if (vechi.isNotEmpty) ...[
                            const _Grup('ÎNAINTE'),
                            for (final e in vechi) _NotificareRand(e),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Element {
  final Dosar dosar;
  final Modificare modificare;
  final bool necitit;

  const _Element(this.dosar, this.modificare, {required this.necitit});
}

class _Grup extends StatelessWidget {
  final String text;

  const _Grup(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NotificareRand extends StatelessWidget {
  final _Element e;

  const _NotificareRand(this.e);

  /// Pictograma și culorile după tipul schimbării.
  (IconData, Color, Color) get _stil {
    final t = e.modificare.text.toLowerCase();
    if (t.contains('termen') || t.contains('ședinț')) {
      return (Icons.event, AppColors.successContainer, AppColors.success);
    }
    if (t.contains('soluți') || t.contains('pronunț')) {
      return (Icons.gavel, AppColors.primaryContainer, AppColors.onPrimaryContainer);
    }
    if (t.contains('instanț')) {
      return (Icons.account_balance, AppColors.accentContainer, AppColors.accent);
    }
    return (Icons.notifications, AppColors.surfaceVariant, AppColors.onSurfaceVariant);
  }

  String get _ora {
    final d = e.modificare.detectataLa;
    final azi = DateUtils.dateOnly(DateTime.now());
    if (!d.isBefore(azi)) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (!d.isBefore(azi.subtract(const Duration(days: 1)))) return 'Ieri';
    return formateazaData(d);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, fundal, culoare) = _stil;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: e.necitit ? AppColors.card : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: e.necitit ? const BorderSide(color: AppColors.outline) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: e.dosar)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: fundal, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 20, color: culoare),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.dosar.numar,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _ora,
                            style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${e.dosar.instanta} — ${e.modificare.text}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.38,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (e.necitit) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
