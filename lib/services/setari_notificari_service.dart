import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Orele de liniște și dosarele care sună oricând. Notificările din orele de
/// liniște nu se pierd: ajung pe telefon fără sunet și fără vibrație.
class SetariNotificariService extends ChangeNotifier {
  SetariNotificariService._();
  static final SetariNotificariService instance = SetariNotificariService._();

  static const _cheieActiv = 'liniste_activa_v1';
  static const _cheieStart = 'liniste_start_v1';
  static const _cheieStop = 'liniste_stop_v1';
  static const _cheieImportante = 'dosare_importante_v1';

  bool _activ = false;
  TimeOfDay _start = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _stop = const TimeOfDay(hour: 7, minute: 0);
  Set<String> _importante = {};

  bool get linisteActiva => _activ;
  TimeOfDay get start => _start;
  TimeOfDay get stop => _stop;

  /// Dosarele care anunță cu sunet și în orele de liniște.
  bool important(String cheie) => _importante.contains(cheie);

  static int _minute(TimeOfDay t) => t.hour * 60 + t.minute;
  static TimeOfDay _dinMinute(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);

  /// Dacă [moment] cade în orele de liniște. Intervalul poate trece peste
  /// miezul nopții (22:00–07:00); începutul e inclus, sfârșitul nu.
  bool esteLiniste(DateTime moment) {
    if (!_activ) return false;
    final m = moment.hour * 60 + moment.minute;
    final a = _minute(_start), b = _minute(_stop);
    if (a == b) return false;
    return a < b ? m >= a && m < b : m >= a || m < b;
  }

  /// Notificarea pentru dosarul [cheie] (null = fără dosar anume, de pildă
  /// o parte urmărită) trebuie să fie silențioasă acum?
  bool silentioasa(DateTime moment, {String? cheie}) =>
      esteLiniste(moment) && !(cheie != null && important(cheie));

  /// Recitește discul: verificarea din fundal rulează în alt isolate.
  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _activ = prefs.getBool(_cheieActiv) ?? false;
    _start = _dinMinute(prefs.getInt(_cheieStart) ?? 22 * 60);
    _stop = _dinMinute(prefs.getInt(_cheieStop) ?? 7 * 60);
    _importante = (prefs.getStringList(_cheieImportante) ?? const []).toSet();
    notifyListeners();
  }

  Future<void> seteazaLiniste({bool? activ, TimeOfDay? start, TimeOfDay? stop}) async {
    _activ = activ ?? _activ;
    _start = start ?? _start;
    _stop = stop ?? _stop;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cheieActiv, _activ);
    await prefs.setInt(_cheieStart, _minute(_start));
    await prefs.setInt(_cheieStop, _minute(_stop));
  }

  Future<void> seteazaImportant(String cheie, bool da) async {
    da ? _importante.add(cheie) : _importante.remove(cheie);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cheieImportante, _importante.toList());
  }
}
