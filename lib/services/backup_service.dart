import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'biblioteca_service.dart';
import 'cautari_recente_service.dart';
import 'culori_service.dart';
import 'parti_urmarite_service.dart';
import 'setari_notificari_service.dart';

class BackupException implements Exception {
  final String mesaj;
  const BackupException(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Ce s-a restaurat dintr-un backup.
class RezultatRestaurare {
  final int dosare;
  final int parti;
  const RezultatRestaurare(this.dosare, this.parti);
}

/// Copia de siguranță într-un fișier: dosarele din bibliotecă cu istoricul
/// modificărilor, culorile, părțile urmărite, căutările recente și setările de
/// notificare. Se mută cu ea datele pe alt telefon.
///
/// Sincronizarea cu calendarul nu intră: calendarele au alte id-uri pe alt
/// telefon și se aleg din nou.
class BackupService {
  BackupService._();

  static const _format = 'portal-dosare-backup';
  static const versiune = 1;

  static const chei = [
    'biblioteca_dosare_v1',
    'biblioteca_ignorate_v1',
    'culori_dosare_v1',
    'parti_urmarite_v1',
    'cautari_recente_v1',
    'liniste_activa_v1',
    'liniste_start_v1',
    'liniste_stop_v1',
    'dosare_importante_v1',
  ];

  static String numeFisier(DateTime d) =>
      'portal-dosare-${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}.json';

  /// Tot ce trebuie salvat, ca text JSON.
  static Future<String> exporta({DateTime? acum}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final date = <String, Object>{
      for (final c in chei)
        if (prefs.get(c) case final v?) c: v is List ? List<String>.from(v) : v,
    };
    return const JsonEncoder.withIndent(' ').convert({
      'format': _format,
      'versiune': versiune,
      'creat': (acum ?? DateTime.now()).toIso8601String(),
      'date': date,
    });
  }

  /// Înlocuiește datele de pe telefon cu cele din backup și reîncarcă ecranele.
  /// Aruncă [BackupException] dacă fișierul nu e un backup al aplicației.
  static Future<RezultatRestaurare> restaureaza(String text) async {
    final Object? brut;
    try {
      brut = jsonDecode(text);
    } catch (_) {
      throw const BackupException('Fișierul nu este un backup Portal Dosare.');
    }
    if (brut is! Map || brut['format'] != _format || brut['date'] is! Map) {
      throw const BackupException('Fișierul nu este un backup Portal Dosare.');
    }
    if ((brut['versiune'] as num? ?? 0) > versiune) {
      throw const BackupException(
        'Backup-ul e făcut cu o versiune mai nouă a aplicației. Actualizeaz-o întâi.',
      );
    }
    final date = brut['date'] as Map;

    final prefs = await SharedPreferences.getInstance();
    for (final c in chei) {
      final v = date[c];
      if (v == null) {
        await prefs.remove(c);
      } else if (v is String) {
        await prefs.setString(c, v);
      } else if (v is bool) {
        await prefs.setBool(c, v);
      } else if (v is int) {
        await prefs.setInt(c, v);
      } else if (v is List) {
        await prefs.setStringList(c, [for (final e in v) '$e']);
      }
    }

    await BibliotecaService.instance.incarca();
    await CuloriDosareService.instance.incarca();
    await PartiUrmariteService.instance.incarca();
    await CautariRecenteService.instance.incarca();
    await SetariNotificariService.instance.incarca();
    return RezultatRestaurare(
      BibliotecaService.instance.dosare.length,
      PartiUrmariteService.instance.parti.length,
    );
  }
}
