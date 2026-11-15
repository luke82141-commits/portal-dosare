import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Funcțiile Pro (rezumat zilnic, calculator termene, widgeturi, rapoarte,
/// statistici, Excel).
///
/// În perioada de lansare Pro e gratuit pentru toți: [perioadaLansare] e
/// `true`, deci [activ] e mereu `true` și ecranele Pro nu se blochează. Nu
/// există niciun comutator prin care utilizatorul să pornească Pro singur.
///
/// Când vine abonamentul (Google Play Billing / App Store), [perioadaLansare]
/// devine `false`, iar [activ] depinde doar de abonamentul confirmat de
/// magazin, salvat aici prin [salveazaAbonament].
class ProService extends ChangeNotifier {
  ProService._();
  static final ProService instance = ProService._();

  /// Pro e deblocat pentru toți cât durează lansarea.
  static const bool perioadaLansare = true;

  /// Textul care spune utilizatorului de la început că Pro va fi plătit.
  static const String etichetaLansare = 'Pro, gratuit în perioada de lansare';

  static const _cheie = 'pro_abonament';
  bool _abonament = false;

  bool get activ => perioadaLansare || _abonament;

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final v = prefs.getBool(_cheie) ?? false;
    if (v != _abonament) {
      _abonament = v;
      notifyListeners();
    }
  }

  /// De apelat doar din fluxul de plată, după ce magazinul confirmă
  /// abonamentul (sau expirarea lui). Nu se leagă de niciun buton.
  Future<void> salveazaAbonament(bool activ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cheie, activ);
    _abonament = activ;
    notifyListeners();
  }
}
