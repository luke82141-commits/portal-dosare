import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dosar_model.dart';
import '../utils/calendar.dart' show zileleSaptamanii;
import 'termene_procedurale_service.dart';

/// Un termen de judecată dintr-o zi, cu dosarul lui.
typedef TermenZi = ({Dosar dosar, Sedinta sedinta});

/// O actualizare apărută de la rezumatul trecut.
typedef ActualizareRezumat = ({Dosar dosar, Modificare modificare});

/// Ce intră în rezumatul unei zile.
class Rezumat {
  final DateTime zi;
  final List<TermenZi> azi;

  /// Următoarea zi lucrătoare (vinerea: lunea).
  final DateTime ziUrmatoare;
  final List<TermenZi> urmatoare;
  final List<ActualizareRezumat> actualizari;

  /// Termenele procedurale salvate care expiră în următoarele 3 zile.
  final List<TermenSalvat> procedurale;

  const Rezumat({
    required this.zi,
    required this.azi,
    required this.ziUrmatoare,
    required this.urmatoare,
    required this.actualizari,
    required this.procedurale,
  });

  bool get gol => azi.isEmpty && urmatoare.isEmpty && actualizari.isEmpty && procedurale.isEmpty;
}

DateTime _zi(DateTime d) => DateTime(d.year, d.month, d.day);

/// Prima zi lucrătoare după [zi].
DateTime urmatoareaZiLucratoare(DateTime zi) {
  var z = DateTime(zi.year, zi.month, zi.day + 1);
  while (motivZiNelucratoare(z) != null) {
    z = DateTime(z.year, z.month, z.day + 1);
  }
  return z;
}

int _minute(String ora) {
  final p = ora.split(':');
  return (int.tryParse(p.first) ?? 99) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

List<TermenZi> termeneInZiua(List<DosarSalvat> salvate, DateTime zi) {
  final z = _zi(zi);
  final l = [
    for (final s in salvate)
      for (final t in s.dosar.sedinte)
        if (t.data != null && _zi(t.data!) == z) (dosar: s.dosar, sedinta: t),
  ];
  l.sort((a, b) => _minute(a.sedinta.ora).compareTo(_minute(b.sedinta.ora)));
  return l;
}

/// Alcătuiește rezumatul pentru ziua lui [acum]. Actualizările sunt cele
/// apărute după [dela] (implicit cu 24 de ore în urmă).
Rezumat construiesteRezumat(
  List<DosarSalvat> salvate,
  List<TermenSalvat> procedurale, {
  required DateTime acum,
  DateTime? dela,
}) {
  final azi = _zi(acum);
  final urm = urmatoareaZiLucratoare(azi);
  final deLa = dela ?? acum.subtract(const Duration(hours: 24));
  final actualizari = [
    for (final s in salvate)
      for (final m in s.modificari)
        if (m.detectataLa.isAfter(deLa)) (dosar: s.dosar, modificare: m),
  ]..sort((a, b) => b.modificare.detectataLa.compareTo(a.modificare.detectataLa));
  return Rezumat(
    zi: azi,
    azi: termeneInZiua(salvate, azi),
    ziUrmatoare: urm,
    urmatoare: termeneInZiua(salvate, urm),
    actualizari: actualizari,
    procedurale: [
      for (final t in procedurale)
        if (!t.ultimaZi.isBefore(azi) && t.ultimaZi.difference(azi).inDays <= 3) t,
    ],
  );
}

/// Setările rezumatului zilnic (Pro): pornit sau nu și ora la care vine.
class RezumatService extends ChangeNotifier {
  RezumatService._();
  static final RezumatService instance = RezumatService._();

  static const _cheie = 'rezumat_zilnic_v1';

  bool activ = true;
  int ora = 7;
  int minut = 30;

  /// Ziua ultimului rezumat trimis (sau sărit, când nu era nimic de spus).
  DateTime? ultimaZi;

  /// Momentul ultimului rezumat, de la care se numără actualizările noi.
  DateTime? ultimulMoment;

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final s = prefs.getString(_cheie);
    if (s == null) return;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      activ = (j['activ'] as bool?) ?? true;
      ora = (j['ora'] as int?) ?? 7;
      minut = (j['minut'] as int?) ?? 30;
      ultimulMoment = DateTime.tryParse((j['ultimul'] as String?) ?? '');
      ultimaZi = ultimulMoment == null ? null : _zi(ultimulMoment!);
    } catch (e) {
      debugPrint('Setările rezumatului nu au putut fi citite: $e');
    }
    notifyListeners();
  }

  Future<void> salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cheie,
      jsonEncode({
        'activ': activ,
        'ora': ora,
        'minut': minut,
        'ultimul': ultimulMoment?.toIso8601String(),
      }),
    );
    notifyListeners();
  }

  /// E momentul pentru rezumatul de azi? Doar în zilele lucrătoare, după ora
  /// aleasă și până la 14:00 (mai târziu nu mai e „de dimineață”), o dată.
  bool eTimpul(DateTime acum) {
    if (!activ || motivZiNelucratoare(acum) != null) return false;
    final deLa = DateTime(acum.year, acum.month, acum.day, ora, minut);
    if (acum.isBefore(deLa) || acum.hour >= 14) return false;
    return ultimaZi != _zi(acum);
  }

  Future<void> marcheazaTrimis(DateTime acum) async {
    ultimulMoment = acum;
    ultimaZi = _zi(acum);
    await salveaza();
  }

  /// De la ce moment se numără actualizările: ultimul rezumat, dar nu mai
  /// mult de 4 zile în urmă (după un weekend lung sau o vacanță).
  DateTime actualizariDeLa(DateTime acum) {
    final limita = acum.subtract(const Duration(days: 4));
    final u = ultimulMoment;
    if (u == null) return acum.subtract(const Duration(hours: 24));
    return u.isBefore(limita) ? limita : u;
  }
}

String _scurt(String instanta) => instanta
    .replaceFirst('Tribunalul ', 'Trib. ')
    .replaceFirst('Judecătoria ', 'Jud. ')
    .replaceFirst('Curtea de Apel ', 'C.A. ');

String _termen(TermenZi t) => [
  if (t.sedinta.ora.isNotEmpty) t.sedinta.ora,
  t.dosar.numar,
  _scurt(t.dosar.instanta),
  if (t.sedinta.complet.isNotEmpty) 'complet ${t.sedinta.complet}',
].join(' · ');

/// „Mâine”, sau numele zilei când următoarea zi lucrătoare nu e mâine.
String numeZiUrmatoare(Rezumat r) => r.ziUrmatoare.difference(r.zi).inDays == 1
    ? 'Mâine'
    : zileleSaptamanii[r.ziUrmatoare.weekday - 1];

String _nr(int n, String unu, String multe) => n == 1 ? '1 $unu' : '$n $multe';

/// Titlul și rândurile notificării de dimineață.
({String titlu, String sumar, List<String> linii}) textRezumat(Rezumat r, {required String ziUrm}) {
  final sumar = [
    if (r.azi.isNotEmpty) 'Azi ${_nr(r.azi.length, 'termen', 'termene')}',
    if (r.urmatoare.isNotEmpty) '$ziUrm ${_nr(r.urmatoare.length, 'termen', 'termene')}',
    if (r.actualizari.isNotEmpty) _nr(r.actualizari.length, 'actualizare', 'actualizări'),
    if (r.procedurale.isNotEmpty)
      _nr(r.procedurale.length, 'termen care expiră', 'termene care expiră'),
  ].join(' · ');
  return (
    titlu: 'Rezumatul zilei',
    sumar: sumar,
    linii: [
      if (r.azi.isNotEmpty) ...['Azi:', for (final t in r.azi) '• ${_termen(t)}'],
      if (r.urmatoare.isNotEmpty) ...['$ziUrm:', for (final t in r.urmatoare) '• ${_termen(t)}'],
      if (r.procedurale.isNotEmpty) ...[
        'Expiră:',
        for (final t in r.procedurale)
          '• ${t.act}${t.numarDosar.isEmpty ? '' : ' · ${t.numarDosar}'}',
      ],
      if (r.actualizari.isNotEmpty) 'Actualizări: ${r.actualizari.length}',
    ],
  );
}
