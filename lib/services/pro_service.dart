import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Funcțiile Pro (widgeturi, rapoarte, statistici). Până există abonamentul,
/// Pro se pornește dintr-un comutator de test din „Widgeturi pe ecran”.
class ProService extends ChangeNotifier {
  ProService._();
  static final ProService instance = ProService._();

  static const _cheie = 'pro_activ';
  bool _activ = false;
  bool get activ => _activ;

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final v = prefs.getBool(_cheie) ?? false;
    if (v != _activ) {
      _activ = v;
      notifyListeners();
    }
  }

  Future<void> seteaza(bool activ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cheie, activ);
    _activ = activ;
    notifyListeners();
  }
}
