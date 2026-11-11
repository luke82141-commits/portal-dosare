import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dosar_model.dart';
import '../services/biblioteca_service.dart';
import '../services/cautari_recente_service.dart';
import '../theme/app_theme.dart';
import '../utils/termene.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';
import 'rezultate_screen.dart';

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

  @override
  void initState() {
    super.initState();
    CautariRecenteService.instance.incarca();
  }

  @override
  void dispose() {
    _numarController.dispose();
    _obiectController.dispose();
    super.dispose();
  }

  void _cauta() {
    final numar = _numarController.text.trim();
    final obiect = _obiectController.text.trim();
    if (numar.isEmpty && obiect.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introdu numărul dosarului sau obiectul.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    CautariRecenteService.instance.adauga(CautareRecenta(numar: numar, obiect: obiect));
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RezultateScreen(numar: numar, obiect: obiect)),
    );
  }

  void _reia(CautareRecenta c) {
    _numarController.text = c.numar;
    _obiectController.text = c.obiect;
    _cauta();
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
