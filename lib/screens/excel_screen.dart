import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/biblioteca_service.dart';
import '../services/client_service.dart';
import '../services/excel_service.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';

/// „Situația în Excel” (Pro): un fișier .xlsx cu două foi, „Situația
/// dosarelor” și „Situația termenelor”.
class ExcelScreen extends StatefulWidget {
  const ExcelScreen({super.key});

  @override
  State<ExcelScreen> createState() => _ExcelScreenState();
}

class _ExcelScreenState extends State<ExcelScreen> {
  /// null = toate termenele.
  int? _an = DateTime.now().year;
  bool _lucreaza = false;

  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
    ClientService.instance.incarca();
  }

  Future<void> _exporta() async {
    setState(() => _lucreaza = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dosare = BibliotecaService.instance.dosare;
      final date = xlsx([
        situatiaDosarelor(dosare, ClientService.instance),
        situatiaTermenelor(dosare, an: _an),
      ]);
      final azi = DateTime.now();
      String d(int n) => n.toString().padLeft(2, '0');
      final nume =
          'Situatia dosarelor ${azi.year}-${d(azi.month)}-${d(azi.day)}.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              date,
              name: nume,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          fileNameOverrides: [nume],
          subject: nume,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fișierul nu a putut fi creat: $e')),
      );
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Situația în Excel')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          ProService.instance,
          BibliotecaService.instance,
          ClientService.instance,
        ]),
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          final dosare = BibliotecaService.instance.dosare;
          final numere = {for (final s in dosare) s.dosar.numar};
          final cuClient = numere
              .where((n) => ClientService.instance.client(n) != null)
              .length;
          final aniTermene = {
            for (final s in dosare)
              for (final t in s.dosar.sedinte)
                if (t.data != null) t.data!.year,
          }.toList()..sort((a, b) => b - a);
          final ani = {DateTime.now().year, ...aniTermene}.toList()
            ..sort((a, b) => b - a);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const _Foaie(
                icon: Icons.table_view_outlined,
                titlu: 'Situația dosarelor',
                text:
                    'Un rând pe dosar: instanța, secția, materia, obiectul, stadiul, părțile, '
                    'clientul, soluțiile pe fond, în apel și în recurs, rezultatul pentru client '
                    'și următorul termen.',
              ),
              const _Foaie(
                icon: Icons.event_note_outlined,
                titlu: 'Situația termenelor',
                text:
                    'Un rând pe termen: data, ora, dosarul, instanța, părțile, completul, '
                    'soluția și termenul următor, dacă s-a amânat.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Termenele incluse',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in ani)
                    ChoiceChip(
                      label: Text('$a'),
                      selected: _an == a,
                      onSelected: (_) => setState(() => _an = a),
                    ),
                  ChoiceChip(
                    label: const Text('Toate'),
                    selected: _an == null,
                    onSelected: (_) => setState(() => _an = null),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                color: AppColors.accentContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.star, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Clientul este marcat la $cuClient din ${numere.length} dosare. '
                          'Ca rezultatul (favorabil, nefavorabil, parțial) să fie completat, '
                          'deschide dosarul, apoi Părți, și atinge steaua de lângă client.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _lucreaza || dosare.isEmpty ? null : _exporta,
                icon: const Icon(Icons.download),
                label: const Text('Descarcă Excel'),
              ),
              if (dosare.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Urmărește întâi cel puțin un dosar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              if (_lucreaza)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Foaie extends StatelessWidget {
  final IconData icon;
  final String titlu;
  final String text;
  const _Foaie({required this.icon, required this.titlu, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(titlu),
      subtitle: Text(text),
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
              'Situația dosarelor și a termenelor, într-un fișier Excel.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
