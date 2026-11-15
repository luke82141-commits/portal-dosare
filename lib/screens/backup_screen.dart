import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../theme/app_theme.dart';

/// Salvarea datelor într-un fișier și restaurarea lor, de pildă pe un telefon
/// nou.
class BackupScreen extends StatefulWidget {
  /// Se pot înlocui în teste.
  final Future<String?> Function()? alegeFisier;
  final Future<void> Function(String json, String nume)? trimiteFisier;

  const BackupScreen({super.key, this.alegeFisier, this.trimiteFisier});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _lucreaza = false;

  Future<void> _trimite(String json, String nume) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(Uint8List.fromList(utf8.encode(json)), mimeType: 'application/json'),
        ],
        fileNameOverrides: [nume],
        subject: 'Backup Portal Dosare',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<String?> _alege() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Alege backup-ul');
    return f == null ? null : await f.xFile.readAsString();
  }

  Future<void> _salveaza() async {
    setState(() => _lucreaza = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await BackupService.exporta();
      await (widget.trimiteFisier ?? _trimite)(json, BackupService.numeFisier(DateTime.now()));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup-ul nu a putut fi creat: $e')));
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  Future<void> _restaureaza() async {
    final messenger = ScaffoldMessenger.of(context);
    final String? text;
    try {
      text = await (widget.alegeFisier ?? _alege)();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fișierul nu a putut fi citit: $e')));
      return;
    }
    if (text == null || !mounted) return;

    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurezi backup-ul?'),
        content: const Text(
          'Dosarele, părțile urmărite și setările de acum vor fi înlocuite cu cele din fișier.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurează'),
          ),
        ],
      ),
    );
    if (da != true) return;

    setState(() => _lucreaza = true);
    try {
      final r = await BackupService.restaureaza(text);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Am restaurat ${r.dosare == 1 ? 'un dosar' : '${r.dosare} dosare'}'
            '${r.parti == 0 ? '' : ' și ${r.parti == 1 ? 'o parte urmărită' : '${r.parti} părți urmărite'}'}.',
          ),
        ),
      );
    } on BackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.mesaj)));
    } finally {
      if (mounted) setState(() => _lucreaza = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Datele aplicației stau doar pe acest telefon. Fă un backup înainte să schimbi '
            'telefonul sau să reinstalezi aplicația și păstrează fișierul în Drive sau pe email.',
            style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cuprinde dosarele monitorizate cu istoricul modificărilor, culorile, părțile '
            'urmărite, căutările recente și orele de liniște. Sincronizarea cu calendarul '
            'se alege din nou pe telefonul nou.',
            style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _lucreaza ? null : _salveaza,
            icon: const Icon(Icons.upload_file),
            label: const Text('Salvează backup'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _lucreaza ? null : _restaureaza,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurează din fișier'),
          ),
          if (_lucreaza) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
