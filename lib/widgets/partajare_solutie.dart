import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/dosar_model.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../utils/instante.dart';

/// Textul unei soluții, gata de trimis (WhatsApp, SMS, email etc.): numărul
/// dosarului, instanța, data pronunțării, soluția și documentul.
String textSolutie(Sedinta s, {Dosar? dosar}) {
  final pronuntata = s.dataPronuntare ?? s.data;
  final sedinta = [
    if (s.data != null) formateazaData(s.data),
    if (s.ora.isNotEmpty) 'ora ${s.ora}',
  ].join(', ');
  final document = [
    numeDocument(s.document),
    if (s.numarDocument.isNotEmpty) 'nr. ${s.numarDocument}',
    if (s.dataDocument != null) 'din ${formateazaData(s.dataDocument)}',
  ].where((e) => e.isNotEmpty).join(' ');
  final sumar = s.solutieSumar.trim();

  return [
    if (dosar != null) ...[
      'Dosar nr. ${dosar.numar}',
      dosar.instanta,
      if (dosar.stadiuProcesual.isNotEmpty) 'Stadiu: ${dosar.stadiuProcesual}',
      '',
    ],
    'Soluție: ${s.solutie.isNotEmpty ? s.solutie : 'Pronunțat'}',
    if (sumar.isNotEmpty && sumar != s.solutie) sumar,
    '',
    if (pronuntata != null) 'Data pronunțării: ${formateazaData(pronuntata)}',
    if (sedinta.isNotEmpty && formateazaData(pronuntata) != formateazaData(s.data))
      'Ședința: $sedinta'
    else if (s.ora.isNotEmpty)
      'Ora ședinței: ${s.ora}',
    if (s.complet.isNotEmpty) 'Complet: ${s.complet}',
    if (document.isNotEmpty) 'Document: $document',
    '',
    'Sursa: portal.just.ro',
  ].join('\n');
}

/// Apăsare lungă pe o soluție: previzualizare, Distribuie și Copiază.
Future<void> optiuniSolutie(BuildContext context, Sedinta s, {Dosar? dosar}) {
  final text = textSolutie(s, dosar: dosar);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Soluția', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.45),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: text));
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(const SnackBar(content: Text('Soluția a fost copiată.')));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiază'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final box = ctx.findRenderObject() as RenderBox?;
                      Navigator.pop(ctx);
                      await SharePlus.instance.share(ShareParams(
                        text: text,
                        subject: dosar == null ? 'Soluție' : 'Soluție dosar ${dosar.numar}',
                        sharePositionOrigin:
                            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                      ));
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Distribuie'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
