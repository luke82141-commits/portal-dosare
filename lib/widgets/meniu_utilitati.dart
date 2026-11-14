import 'package:flutter/material.dart';

import '../screens/backup_screen.dart';
import '../screens/calculator_termene_screen.dart';
import '../screens/excel_screen.dart';
import '../screens/parti_urmarite_screen.dart';
import '../screens/rapoarte_screen.dart';
import '../screens/rezumat_zilnic_screen.dart';
import '../screens/setari_notificari_screen.dart';
import '../screens/statistici_screen.dart';
import '../screens/sugestie_screen.dart';
import '../screens/widgeturi_screen.dart';
import '../theme/app_theme.dart';
import 'dosar_iccj.dart';

/// Foaia „Utilități” din bara de jos: unelte folosite mai rar, ținute în afara
/// ecranelor principale. Cele de sub „PRO” vin cu abonamentul.
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
              icon: Icons.account_balance,
              titlu: 'Dosar la Înalta Curte',
              text: 'Urmărește un dosar ÎCCJ după număr (actualizat noaptea)',
              onTap: () {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                navigator.pop();
                adaugaDosarIccj(navigator.context).then((m) {
                  if (m == null) return;
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(content: Text(m)));
                });
              },
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
                'PRO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.accent,
                ),
              ),
            ),
            _Unealta(
              icon: Icons.wb_sunny_outlined,
              titlu: 'Rezumatul zilnic',
              text: 'Dimineața: termenele zilei, ce s-a schimbat și ce expiră',
              onTap: () => _deschide(context, const RezumatZilnicScreen()),
            ),
            _Unealta(
              icon: Icons.calculate_outlined,
              titlu: 'Calculator termene',
              text: 'Ultima zi pentru apel, recurs, întâmpinare și alte acte',
              onTap: () => _deschide(context, const CalculatorTermeneScreen()),
            ),
            _Unealta(
              icon: Icons.widgets_outlined,
              titlu: 'Widgeturi pe ecran',
              text: 'Termenele și actualizările direct pe ecranul telefonului',
              onTap: () => _deschide(context, const WidgeturiScreen()),
            ),
            _Unealta(
              icon: Icons.summarize_outlined,
              titlu: 'Rapoarte',
              text: 'Săptămânal, lunar și anual, în PDF și Word',
              onTap: () => _deschide(context, const RapoarteScreen()),
            ),
            _Unealta(
              icon: Icons.bar_chart,
              titlu: 'Statistici',
              text: 'Termene, dosare și soluții pe ani, comparate cu anul trecut',
              onTap: () => _deschide(context, const StatisticiScreen()),
            ),
            _Unealta(
              icon: Icons.table_view_outlined,
              titlu: 'Situația în Excel',
              text: 'Dosarele și termenele, cu soluțiile pe faze și rezultatul pentru client',
              onTap: () => _deschide(context, const ExcelScreen()),
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

  const _Unealta({required this.icon, required this.titlu, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(titlu),
      subtitle: Text(text),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
