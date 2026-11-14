import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/biblioteca_service.dart';
import '../services/pro_service.dart';
import '../services/raport_export.dart';
import '../services/raport_service.dart';
import '../theme/app_theme.dart';

/// „Rapoarte” (Pro): alegi perioada, vezi sinteza și descarci raportul în
/// PDF sau Word.
class RapoarteScreen extends StatefulWidget {
  const RapoarteScreen({super.key});

  @override
  State<RapoarteScreen> createState() => _RapoarteScreenState();
}

class _RapoarteScreenState extends State<RapoarteScreen> {
  static const _cheieBeneficiar = 'raport_beneficiar';

  var _interval = IntervalRaport.pentru(PerioadaRaport.lunar, DateTime.now());
  final _beneficiar = TextEditingController();
  bool _lucreaza = false;

  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
    SharedPreferences.getInstance().then((p) {
      if (mounted) _beneficiar.text = p.getString(_cheieBeneficiar) ?? '';
    });
  }

  @override
  void dispose() {
    _beneficiar.dispose();
    super.dispose();
  }

  Raport get _raport => construiesteRaport(
    BibliotecaService.instance.dosare,
    _interval,
    beneficiar: _beneficiar.text,
  );

  Future<void> _exporta(String extensie) async {
    setState(() => _lucreaza = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      (await SharedPreferences.getInstance()).setString(_cheieBeneficiar, _beneficiar.text.trim());
      final raport = _raport;
      final Uint8List date;
      final String tip;
      if (extensie == 'pdf') {
        Future<pw.Font> font(String nume) async =>
            pw.Font.ttf(await rootBundle.load('assets/fonts/LiberationSerif-$nume.ttf'));
        date = await raportPdf(
          raport,
          FonturiRaport(await font('Regular'), await font('Bold'), await font('Italic')),
        );
        tip = 'application/pdf';
      } else {
        date = raportDocx(raport);
        tip = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      }
      final nume = numeFisierRaport(raport, extensie);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(date, mimeType: tip, name: nume)],
          fileNameOverrides: [nume],
          subject: nume,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Raportul nu a putut fi creat: $e')));
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rapoarte')),
      body: ListenableBuilder(
        listenable: Listenable.merge([ProService.instance, BibliotecaService.instance]),
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          final raport = _raport;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SegmentedButton<PerioadaRaport>(
                segments: const [
                  ButtonSegment(value: PerioadaRaport.saptamanal, label: Text('Săptămânal')),
                  ButtonSegment(value: PerioadaRaport.lunar, label: Text('Lunar')),
                  ButtonSegment(value: PerioadaRaport.anual, label: Text('Anual')),
                ],
                selected: {_interval.perioada},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    setState(() => _interval = IntervalRaport.pentru(s.first, _interval.inceput)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Perioada anterioară',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _interval = _interval.precedent),
                  ),
                  Expanded(
                    child: Text(
                      _interval.eticheta,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Perioada următoare',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _interval = _interval.urmator),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (final (eticheta, valoare, sub) in raport.indicatori)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.only(left: sub ? 32 : 16, right: 16),
                          title: Text(
                            eticheta,
                            style: sub ? const TextStyle(color: AppColors.onSurfaceVariant) : null,
                          ),
                          trailing: Text(
                            valoare,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _beneficiar,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Beneficiar (opțional)',
                  hintText: 'ex. Cabinet de avocat …',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lucreaza ? null : () => _exporta('pdf'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _lucreaza ? null : () => _exporta('docx'),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Word'),
                    ),
                  ),
                ],
              ),
              if (_lucreaza)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 16),
              const Text(
                'Raportul se întocmește din dosarele urmărite, cu datele publicate pe portal la '
                'ultima verificare.',
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
              ),
            ],
          );
        },
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
            const Icon(Icons.workspace_premium_outlined, size: 48, color: AppColors.accent),
            const SizedBox(height: 12),
            const Text(
              'Disponibil în Portal Dosare Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Rapoarte săptămânale, lunare și anuale, în PDF și Word.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => ProService.instance.seteaza(true),
              child: const Text('Activează Pro (test)'),
            ),
          ],
        ),
      ),
    );
  }
}
