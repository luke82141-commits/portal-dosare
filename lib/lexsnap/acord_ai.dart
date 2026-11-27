import 'package:shared_preferences/shared_preferences.dart';

/// Acordul utilizatorului pentru trimiterea documentelor (anonimizate) la
/// serviciul AI. Se cere o dată, explicit, și se poate retrage oricând.
abstract class AcordAi {
  Future<bool> acordat();
  Future<void> seteaza(bool acord);
}

class AcordAiPreferinte implements AcordAi {
  /// Versiunea textului de acord: dacă textul se schimbă, se cere din nou.
  static const cheie = 'lexsnap_acord_ai_v1';

  const AcordAiPreferinte();

  @override
  Future<bool> acordat() async =>
      (await SharedPreferences.getInstance()).getBool(cheie) ?? false;

  @override
  Future<void> seteaza(bool acord) async {
    final p = await SharedPreferences.getInstance();
    if (acord) {
      await p.setBool(cheie, true);
    } else {
      await p.remove(cheie);
    }
  }
}

/// Avertismentul afișat deasupra rezultatelor AI.
const avertismentRezultatAi = 'Rezultat orientativ, verificați textul oficial.';

/// Textul acordului, afișat înainte de prima trimitere.
const textAcordAi = [
  'Ce se trimite: textul documentului și articolele de lege găsite, prin '
      'serverul nostru (Londra, Regatul Unit), către Groq Inc. (SUA), care rulează '
      'modelul AI.',
  'Ce ascundem înainte să plece de pe telefon: CNP, IBAN, telefon, email, '
      'seria buletinului, numărul de înmatriculare, adresa (strada, numărul, '
      'blocul) și numele scrise după formule ca „contravenientul”, „domnul”, '
      '„subsemnatul”. Alte nume pot rămâne: verifică textul înainte.',
  'Serverul nostru nu salvează documentul și nici răspunsul. Groq nu '
      'folosește datele trimise prin API pentru antrenarea modelelor.',
  'Rezultatul e orientativ și nu înlocuiește verificarea textului oficial.',
];

const textConfirmareAcordAi =
    'Am înțeles și confirm că am dreptul să trimit acest document (de '
    'exemplu, cu acordul clientului) și că nu trimit date sensibile (sănătate, '
    'minori, fapte penale) fără temei legal.';
