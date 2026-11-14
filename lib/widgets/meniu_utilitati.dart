import 'package:flutter/material.dart';

import '../screens/backup_screen.dart';
import '../screens/parti_urmarite_screen.dart';
import '../screens/setari_notificari_screen.dart';
import '../screens/sugestie_screen.dart';
import '../theme/app_theme.dart';

/// Foaia „Utilități” din bara de jos: unelte folosite mai rar, ținute în afara
/// ecranelor principale. Cele marcate Pro vin cu abonamentul.
Future<void> deschideUtilitati(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _MeniuUtilitati(),
);

class _MeniuUtilitati extends StatelessWidget {
  const _MeniuUtilitati();

  void _deschide(BuildContext context, Widget ecran) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => ecran));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Utilități', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            _Unealta(
              icon: Icons.person_search,
              titlu: 'Părți urmărite',
              text: 'Alertă când apare un dosar nou pe numele unei părți',
              onTap: () => _deschide(context, const PartiUrmariteScreen()),
            ),
            _Unealta(
              icon: Icons.bedtime_outlined,
              titlu: 'Ore de liniște',
              text: 'Fără sunet noaptea; dosarele importante sună oricând',
              onTap: () => _deschide(context, const SetariNotificariScreen()),
            ),
            _Unealta(
              icon: Icons.save_alt,
              titlu: 'Backup',
              text: 'Salvează datele într-un fișier și mută-le pe alt telefon',
              onTap: () => _deschide(context, const BackupScreen()),
            ),
            _Unealta(
              icon: Icons.lightbulb_outline,
              titlu: 'Trimite o sugestie',
              text: 'Spune-ne ce îți lipsește sau ce nu merge',
              onTap: () => _deschide(context, const SugestieScreen()),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'PRO · ÎN CURÂND',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.accent,
                ),
              ),
            ),
            const _Unealta(
              icon: Icons.summarize_outlined,
              titlu: 'Rapoarte',
              text: 'Termenele pe zi, săptămână, lună și an, cu obiectul dosarelor',
              pro: true,
            ),
            const _Unealta(
              icon: Icons.bar_chart,
              titlu: 'Statistici',
              text: 'Termene și dosare pe an, soluții: admite, respinge, admite în parte',
              pro: true,
            ),
            const _Unealta(
              icon: Icons.table_view_outlined,
              titlu: 'Situația dosarelor în Excel',
              text: 'Instanță, materie, stadiu, părți, soluții pe fond, apel, recurs',
              pro: true,
            ),
            const _Unealta(
              icon: Icons.event_note_outlined,
              titlu: 'Situația termenelor în Excel',
              text: 'Data, dosarul, părțile, ora, completul, soluția și termenul următor',
              pro: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Unealta extends StatelessWidget {
  final IconData icon;
  final String titlu;
  final String text;
  final VoidCallback? onTap;
  final bool pro;

  const _Unealta({
    required this.icon,
    required this.titlu,
    required this.text,
    this.onTap,
    this.pro = false,
  });

  @override
  Widget build(BuildContext context) {
    final culoare = pro ? AppColors.onSurfaceVariant : AppColors.primary;
    return ListTile(
      enabled: !pro,
      leading: Icon(icon, color: culoare),
      title: Text(titlu),
      subtitle: Text(text),
      trailing: pro ? const Icon(Icons.lock_outline, size: 18) : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
