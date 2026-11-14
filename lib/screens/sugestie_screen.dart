import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/elemente.dart';

/// Adresa la care ajung sugestiile.
const adresaSugestii = 'contact@typewriter.ro';

/// Versiunea din pubspec.yaml; de actualizat odată cu ea.
const versiuneAplicatie = '1.0.0+1';

enum TipSugestie {
  idee('Idee nouă', Icons.lightbulb_outline),
  problema('Ceva nu merge', Icons.bug_report_outlined),
  altceva('Altceva', Icons.chat_bubble_outline);

  final String eticheta;
  final IconData icon;
  const TipSugestie(this.eticheta, this.icon);
}

String get _platforma {
  if (kIsWeb) return 'web';
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    return 'necunoscută';
  }
}

/// Textul complet al emailului, cu versiunea aplicației și telefonul la final,
/// ca problemele să poată fi reproduse.
String corpSugestie(TipSugestie tip, String text, {String? platforma}) => [
  text.trim(),
  '',
  '—',
  'Tip: ${tip.eticheta}',
  'Versiunea aplicației: $versiuneAplicatie',
  'Sistem: ${platforma ?? _platforma}',
].join('\n');

Uri emailSugestie(TipSugestie tip, String text, {String? platforma}) => Uri(
  scheme: 'mailto',
  path: adresaSugestii,
  // Uri(queryParameters:) codifică spațiile cu „+”, pe care unele aplicații
  // de email le lasă așa; %20 merge peste tot.
  query:
      'subject=${Uri.encodeComponent('Portal Dosare · ${tip.eticheta}')}'
      '&body=${Uri.encodeComponent(corpSugestie(tip, text, platforma: platforma))}',
);

/// „Trimite o sugestie”: utilizatorii spun ce le lipsește sau ce nu merge.
/// Deocamdată prin email; votul pe idei va cere server.
class SugestieScreen extends StatefulWidget {
  const SugestieScreen({super.key});

  @override
  State<SugestieScreen> createState() => _SugestieScreenState();
}

class _SugestieScreenState extends State<SugestieScreen> {
  final _text = TextEditingController();
  var _tip = TipSugestie.idee;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _trimite() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_text.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Scrie mai întâi sugestia.')));
      return;
    }
    var reusit = false;
    try {
      reusit = await launchUrl(emailSugestie(_tip, _text.text));
    } catch (_) {}
    if (reusit) return;

    // Fără aplicație de email: textul ajunge în clipboard, cu adresa.
    await Clipboard.setData(ClipboardData(text: corpSugestie(_tip, _text.text)));
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'Nu am găsit o aplicație de email. Am copiat textul: trimite-l la $adresaSugestii.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trimite o sugestie')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Ce ți-ar fi de folos în aplicație? Citim fiecare mesaj, iar ideile cerute '
            'de mai mulți utilizatori intră primele în lucru.',
            style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in TipSugestie.values)
                Pastila(t.eticheta, activ: _tip == t, onTap: () => setState(() => _tip = t)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _tip == TipSugestie.problema
                  ? 'Ce ai făcut, ce te așteptai să se întâmple și ce s-a întâmplat'
                  : 'Scrie sugestia ta',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Se deschide aplicația de email cu mesajul gata scris. Adăugăm versiunea '
            'aplicației și a telefonului, ca să putem reproduce problemele.',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _trimite,
            icon: const Icon(Icons.send),
            label: const Text('Trimite pe email'),
          ),
        ],
      ),
    );
  }
}
