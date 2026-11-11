import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/termene.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';
import 'dosare_filtrate_screen.dart';

/// Dosarele monitorizate (Figma: „04 · Dosare monitorizate”).
class MonitorizateScreen extends StatefulWidget {
  const MonitorizateScreen({super.key});

  @override
  State<MonitorizateScreen> createState() => _MonitorizateScreenState();
}

class _MonitorizateScreenState extends State<MonitorizateScreen> {
  bool _verifica = false;

  Future<void> _verificaAcum() async {
    if (_verifica) return;
    setState(() => _verifica = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rezultate = await MonitorizareService.instance.verificaToate();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            rezultate.isEmpty
                ? 'Nicio modificare pe portal.'
                : rezultate.length == 1
                    ? 'Un dosar are modificări.'
                    : '${rezultate.length} dosare au modificări.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Verificarea a eșuat: $e')));
    } finally {
      if (mounted) setState(() => _verifica = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final biblioteca = BibliotecaService.instance;
          final dosare = biblioteca.dosare;
          final verificari = [
            for (final d in dosare)
              if (d.ultimaVerificare != null) d.ultimaVerificare!,
          ]..sort();
          final azi = DateTime.now();
          final peSaptamana = dosare.where((d) {
            final t = urmatorulTermen(d.dosar);
            return t != null && t.data!.difference(DateUtils.dateOnly(azi)).inDays < 7;
          }).length;

          return RefreshIndicator(
            onRefresh: _verificaAcum,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Monitorizate',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (dosare.isNotEmpty) ...[
                              _butonRotund(
                                tooltip: 'Filtrează dosarele',
                                icon: Icons.tune,
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const DosareFiltrateScreen()),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _butonVerificare(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Verificare automată o dată pe oră'
                          '${verificari.isEmpty ? '' : ' · ultima: ${formateazaDataOra(verificari.last)}'}',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.38,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: dosare.isEmpty
                      ? const StareMesaj(
                          icon: Icons.bookmark_border,
                          titlu: 'Niciun dosar monitorizat',
                          text: 'Deschide un dosar și pornește „Monitorizează dosarul”. '
                              'Vei primi o notificare la fiecare schimbare apărută pe portal.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Sumar(
                                    '${dosare.length}',
                                    dosare.length == 1 ? 'dosar urmărit' : 'dosare urmărite',
                                  ),
                                  const SizedBox(width: 10),
                                  _Sumar(
                                    '${biblioteca.totalNecitite}',
                                    biblioteca.totalNecitite == 1
                                        ? 'actualizare nouă'
                                        : 'actualizări noi',
                                    fundal: AppColors.successContainer,
                                    culoare: AppColors.success,
                                  ),
                                  const SizedBox(width: 10),
                                  _Sumar(
                                    '$peSaptamana',
                                    'termene în 7 zile',
                                    fundal: AppColors.accentContainer,
                                    culoare: AppColors.accent,
                                  ),
                                ],
                              ),
                            ),
                            for (final s in dosare) ...[
                              const SizedBox(height: 12),
                              DosarCardWidget(
                                key: ValueKey(s.dosar.cheie),
                                dosar: s.dosar,
                                salvat: s,
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _butonRotund({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 20,
          color: AppColors.primary,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }

  Widget _butonVerificare() {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: SizedBox(
        width: 40,
        height: 40,
        child: _verifica
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Verifică acum pe portal',
                padding: EdgeInsets.zero,
                iconSize: 20,
                color: AppColors.primary,
                onPressed: _verificaAcum,
                icon: const Icon(Icons.refresh),
              ),
      ),
    );
  }
}

class _Sumar extends StatelessWidget {
  final String valoare;
  final String eticheta;
  final Color? fundal;
  final Color culoare;

  const _Sumar(
    this.valoare,
    this.eticheta, {
    this.fundal,
    this.culoare = AppColors.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fundal ?? AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: fundal == null ? Border.all(color: AppColors.outline) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              valoare,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: culoare),
            ),
            const SizedBox(height: 2),
            Text(
              eticheta,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                color: fundal == null ? AppColors.onSurfaceVariant : culoare,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
