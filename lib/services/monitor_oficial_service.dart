import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legislatie_service.dart' show etichetaTip, fataDiacritice;

/// Un act publicat în Monitorul Oficial, Partea I, așa cum îl dă sursa
/// (e-Monitor sau Portalul Legislativ). Ținem doar antetul, nu textul.
class ActPublicat {
  /// „LEGE”, „ORDONANTA DE URGENTA”, „HOTARARE”, „ORDIN”, „DECIZIE”...
  /// (majuscule, fără diacritice, ca în [tipuriActe]).
  final String tip;
  final String numar;

  /// Titlul fără antet: „privind modificarea Legii nr. 227/2015...”.
  final String titlu;
  final String emitent;

  /// Numărul Monitorului Oficial („1050”, „1050 bis”).
  final String monitor;

  /// Ziua în care a apărut Monitorul Oficial.
  final DateTime dataPublicarii;

  /// Unde se deschide actul (pagina oficială), dacă sursa îl dă.
  final String link;

  const ActPublicat({
    required this.tip,
    required this.numar,
    required this.titlu,
    required this.emitent,
    required this.monitor,
    required this.dataPublicarii,
    this.link = '',
  });

  /// Cheie stabilă, pentru dubluri și pentru „deja anunțat”.
  String get cheie => link.isNotEmpty
      ? link
      : '$tip|$numar|$monitor|${_ziIso(dataPublicarii)}|${titlu.hashCode}';

  /// „Lege nr. 312”, „Ordin nr. 1.540”, „Decizie nr. 87”.
  String get denumire {
    final t = tip.isEmpty ? 'Act' : etichetaTip(tip);
    final n = numar.trim();
    return n.isEmpty || n == '0' ? t : '$t nr. $n';
  }

  Map<String, dynamic> toJson() => {
    'tip': tip,
    'numar': numar,
    'titlu': titlu,
    'emitent': emitent,
    'monitor': monitor,
    'data': _ziIso(dataPublicarii),
    'link': link,
  };

  factory ActPublicat.fromJson(Map<String, dynamic> j) => ActPublicat(
    tip: (j['tip'] as String?) ?? '',
    numar: (j['numar'] as String?) ?? '',
    titlu: (j['titlu'] as String?) ?? '',
    emitent: (j['emitent'] as String?) ?? '',
    monitor: (j['monitor'] as String?) ?? '',
    dataPublicarii: DateTime.parse(j['data'] as String),
    link: (j['link'] as String?) ?? '',
  );
}

String _ziIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _zi(DateTime d) => DateTime(d.year, d.month, d.day);

// ---------------------------------------------------------------------------
// Domenii de interes

/// Cum se combină cuvintele cheie cu emitenții, când are și unele, și altele.
enum Combinare {
  /// Ajunge una: un cuvânt din titlu SAU un emitent (domeniile predefinite).
  oricare,

  /// Trebuie amândouă: un cuvânt din titlu ȘI un emitent din listă.
  toate,
}

/// O „linie de interes”: ce acte vrea utilizatorul să afle că au apărut.
///
/// Un act se potrivește dacă:
/// - are în titlu unul dintre [cuvinte] (început de cuvânt: „impozit” prinde
///   „impozitul”, „impozitelor”; diacriticele și majusculele nu contează)
///   și/sau e dat de unul dintre [emitenti], după [combinare];
/// - e de unul dintre [tipuri] (dacă lista nu e goală);
/// - nu are în titlu niciunul dintre [excluse].
class DomeniuInteres {
  final String id;
  final String nume;
  final List<String> cuvinte;
  final List<String> emitenti;

  /// Tipuri din [tipuriActe] („LEGE”, „ORDIN”...). Gol = orice tip.
  final Set<String> tipuri;
  final List<String> excluse;
  final Combinare combinare;

  /// Vine din lista aplicației (nu se editează, doar se bifează).
  final bool predefinit;

  const DomeniuInteres({
    required this.id,
    required this.nume,
    this.cuvinte = const [],
    this.emitenti = const [],
    this.tipuri = const {},
    this.excluse = const [],
    this.combinare = Combinare.toate,
    this.predefinit = false,
  });

  /// Un domeniu fără niciun criteriu ar prinde tot Monitorul.
  bool get gol => cuvinte.isEmpty && emitenti.isEmpty && tipuri.isEmpty;

  /// Ce a prins actul („cuvântul «impozit»”, „emitentul ANAF”), sau null
  /// dacă actul nu se potrivește.
  String? motivPotrivire(ActPublicat act) {
    if (gol) return null;
    if (tipuri.isNotEmpty && !tipuri.contains(fataDiacritice(act.tip).toUpperCase())) {
      return null;
    }
    final titlu = _pregatit(act.titlu);
    if (excluse.any((e) => _contine(titlu, e))) return null;
    final cuvant = cuvinte.where((c) => _contine(titlu, c)).firstOrNull;
    final emitent = emitenti.where((e) => _contine(_pregatit(act.emitent), e)).firstOrNull;

    final bunCuvinte = cuvinte.isEmpty || cuvant != null;
    final bunEmitent = emitenti.isEmpty || emitent != null;
    final potrivit = cuvinte.isNotEmpty && emitenti.isNotEmpty && combinare == Combinare.oricare
        ? cuvant != null || emitent != null
        : bunCuvinte && bunEmitent;
    if (!potrivit) return null;
    if (cuvant != null) return '„${cuvant.trim()}”';
    if (emitent != null) return act.emitent.trim();
    return etichetaTip(act.tip);
  }

  bool potriveste(ActPublicat act) => motivPotrivire(act) != null;

  DomeniuInteres copyWith({
    String? nume,
    List<String>? cuvinte,
    List<String>? emitenti,
    Set<String>? tipuri,
    List<String>? excluse,
    Combinare? combinare,
  }) => DomeniuInteres(
    id: id,
    nume: nume ?? this.nume,
    cuvinte: cuvinte ?? this.cuvinte,
    emitenti: emitenti ?? this.emitenti,
    tipuri: tipuri ?? this.tipuri,
    excluse: excluse ?? this.excluse,
    combinare: combinare ?? this.combinare,
    predefinit: predefinit,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nume': nume,
    'cuvinte': cuvinte,
    'emitenti': emitenti,
    'tipuri': tipuri.toList(),
    'excluse': excluse,
    'combinare': combinare.name,
  };

  factory DomeniuInteres.fromJson(Map<String, dynamic> j) => DomeniuInteres(
    id: j['id'] as String,
    nume: (j['nume'] as String?) ?? '',
    cuvinte: [for (final c in (j['cuvinte'] as List?) ?? const []) c as String],
    emitenti: [for (final c in (j['emitenti'] as List?) ?? const []) c as String],
    tipuri: {for (final c in (j['tipuri'] as List?) ?? const []) c as String},
    excluse: [for (final c in (j['excluse'] as List?) ?? const []) c as String],
    combinare: Combinare.values.firstWhere(
      (c) => c.name == j['combinare'],
      orElse: () => Combinare.toate,
    ),
  );
}

/// Litere mici, fără diacritice, orice altceva devine spațiu; cu spațiu la
/// început, ca „ impozit” să însemne „cuvânt care începe cu impozit”.
String _pregatit(String s) =>
    ' ${fataDiacritice(s).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';

/// [text] e deja [_pregatit]. Fiecare cuvânt din [cheie] prinde și formele
/// lungi („executare silită” prinde „executarea silită”, „poprir” prinde
/// „popririle”); un singur cuvânt scurt (până la 3 litere: „TVA”, „CCR”)
/// trebuie să fie întreg.
bool _contine(String text, String cheie) {
  final c = _pregatit(cheie).trim();
  if (c.isEmpty) return false;
  final cuvinte = c.split(' ');
  if (cuvinte.length == 1) return c.length <= 3 ? text.contains(' $c ') : text.contains(' $c');
  final re = _expresii.putIfAbsent(
    c,
    () => RegExp(' ${cuvinte.map(RegExp.escape).join('[a-z0-9]* ')}'),
  );
  return re.hasMatch(text);
}

final _expresii = <String, RegExp>{};

/// Împarte ce scrie omul („impozit, taxe; TVA”) în cuvinte cheie.
List<String> cuvinteDinText(String s) => [
  for (final p in s.split(RegExp(r'[,;\n]')))
    if (p.trim().isNotEmpty) p.trim(),
];

/// Liniile de interes din care se alege. Cuvintele sunt începuturi de cuvânt,
/// fără diacritice; emitenții, bucăți din numele lor.
const domeniiPredefinite = <DomeniuInteres>[
  DomeniuInteres(
    id: 'fiscal',
    nume: 'Fiscal și contabilitate',
    cuvinte: ['fiscal', 'impozit', 'taxe', 'taxa pe valoarea adaugata', 'TVA', 'accize',
      'contabil', 'contributii sociale', 'facturare', 'e-factura'],
    emitenti: ['Ministerul Finantelor', 'Agentia Nationala de Administrare Fiscala'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'munca',
    nume: 'Muncă și asigurări sociale',
    cuvinte: ['Codul muncii', 'contractul individual de munca', 'salari', 'salarizar',
      'concedi', 'pensii', 'pensia', 'asigurari sociale', 'somaj', 'inspectia muncii',
      'dialogul social', 'timpul de munca'],
    emitenti: ['Ministerul Muncii', 'Casa Nationala de Pensii'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'civil',
    nume: 'Drept civil și procedură civilă',
    cuvinte: ['Codul civil', 'procedura civila', 'executare silita', 'executarea silita',
      'executorilor judecatoresti', 'taxele judiciare de timbru', 'mediere', 'arbitraj',
      'carte funciara', 'cartea funciara'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'penal',
    nume: 'Penal și procedură penală',
    cuvinte: ['Codul penal', 'procedura penala', 'infractiun', 'executarea pedepselor',
      'penitenciar', 'cazier', 'urmarire penala', 'Ministerul Public'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'ccr',
    nume: 'Decizii ale Curții Constituționale',
    emitenti: ['Curtea Constitutionala'],
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'iccj',
    nume: 'Decizii ÎCCJ (RIL, HP)',
    emitenti: ['Inalta Curte de Casatie'],
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'justitie',
    nume: 'Justiție și profesii juridice',
    cuvinte: ['organizarea judiciara', 'magistrat', 'judecator', 'procuror', 'instante',
      'avocat', 'notar', 'executor judecatoresc', 'practician in insolventa',
      'Consiliul Superior al Magistraturii'],
    emitenti: ['Consiliul Superior al Magistraturii', 'Ministerul Justitiei',
      'Uniunea Nationala a Barourilor', 'Uniunea Nationala a Notarilor'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'achizitii',
    nume: 'Achiziții publice',
    cuvinte: ['achizitii publice', 'achizitiile publice', 'achizitiilor publice',
      'achizitii sectoriale', 'concesiuni de lucrari', 'concesiunile de lucrari',
      'remedii si cai de atac'],
    emitenti: ['Agentia Nationala pentru Achizitii Publice',
      'Consiliul National de Solutionare a Contestatiilor'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'gdpr',
    nume: 'Protecția datelor (GDPR)',
    cuvinte: ['date cu caracter personal', 'datelor cu caracter personal',
      'protectia datelor', 'Regulamentul (UE) 2016/679'],
    emitenti: ['Autoritatea Nationala de Supraveghere a Prelucrarii Datelor'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'societati',
    nume: 'Societăți, insolvență, registrul comerțului',
    cuvinte: ['societat', 'insolvent', 'registrul comertului', 'profesionisti',
      'persoanele juridice', 'reorganizare judiciara', 'faliment'],
    emitenti: ['Oficiul National al Registrului Comertului'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'administrativ',
    nume: 'Administrație publică și contencios',
    cuvinte: ['Codul administrativ', 'contencios administrativ', 'administratiei publice',
      'unitatilor administrativ teritoriale', 'functionarilor publici', 'functionarii publici'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'urbanism',
    nume: 'Urbanism, construcții, cadastru',
    cuvinte: ['urbanism', 'amenajarea teritoriului', 'autorizarea executarii lucrarilor',
      'autorizatii de construire', 'constructii', 'cadastru', 'publicitate imobiliara'],
    emitenti: ['Agentia Nationala de Cadastru', 'Ministerul Dezvoltarii'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'consumatori',
    nume: 'Protecția consumatorilor',
    cuvinte: ['consumator', 'clauzele abuzive', 'practicile comerciale'],
    emitenti: ['Autoritatea Nationala pentru Protectia Consumatorilor'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'sanatate',
    nume: 'Sănătate',
    cuvinte: ['sanatat', 'medical', 'medicament', 'spital', 'farmac'],
    emitenti: ['Ministerul Sanatatii', 'Casa Nationala de Asigurari de Sanatate'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'mediu',
    nume: 'Mediu și energie',
    cuvinte: ['protectia mediului', 'deseuri', 'ariilor naturale', 'emisii', 'energie',
      'energiei', 'gaze naturale', 'apelor'],
    emitenti: ['Ministerul Mediului', 'Ministerul Energiei',
      'Autoritatea Nationala de Reglementare in Domeniul Energiei'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'transport',
    nume: 'Transporturi și circulație rutieră',
    cuvinte: ['circulatia pe drumurile publice', 'rutier', 'transport', 'permis de conducere',
      'permisului de conducere', 'vehicul'],
    emitenti: ['Ministerul Transporturilor'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'educatie',
    nume: 'Educație',
    cuvinte: ['invatamant', 'educatie', 'educatiei', 'universit', 'scolar', 'bacalaureat',
      'titularizar', 'definitivar'],
    emitenti: ['Ministerul Educatiei'],
    combinare: Combinare.oricare,
    predefinit: true,
  ),
  DomeniuInteres(
    id: 'legi',
    nume: 'Toate legile și ordonanțele',
    tipuri: {'LEGE', 'ORDONANTA DE URGENTA', 'ORDONANTA'},
    predefinit: true,
  ),
];

// ---------------------------------------------------------------------------
// Raport

/// Un act potrivit cu domeniile utilizatorului.
typedef ActGasit = ({ActPublicat act, List<String> domenii, String motiv});

/// Actele din [acte] care se potrivesc cu [domenii], fiecare o dată, cu
/// numele tuturor domeniilor care l-au prins. Ordinea: după ziua apariției,
/// apoi legile și ordonanțele înaintea celorlalte, apoi după Monitor.
List<ActGasit> potriveste(List<ActPublicat> acte, List<DomeniuInteres> domenii) {
  final vazute = <String>{};
  final rezultat = <ActGasit>[];
  for (final a in acte) {
    if (!vazute.add(a.cheie)) continue;
    String? motiv;
    final nume = <String>[];
    for (final d in domenii) {
      final m = d.motivPotrivire(a);
      if (m == null) continue;
      motiv ??= m;
      nume.add(d.nume);
    }
    if (motiv != null) rezultat.add((act: a, domenii: nume, motiv: motiv));
  }
  int rang(String tip) => switch (tip) {
    'LEGE' => 0,
    'ORDONANTA DE URGENTA' => 1,
    'ORDONANTA' => 2,
    'HOTARARE' => 3,
    'DECIZIE' => 4,
    _ => 5,
  };
  rezultat.sort((x, y) {
    final z = x.act.dataPublicarii.compareTo(y.act.dataPublicarii);
    if (z != 0) return z;
    final r = rang(x.act.tip).compareTo(rang(y.act.tip));
    if (r != 0) return r;
    return (int.tryParse(x.act.monitor.split(' ').first) ?? 0)
        .compareTo(int.tryParse(y.act.monitor.split(' ').first) ?? 0);
  });
  return rezultat;
}

/// Zilele pe care le acoperă raportul de dimineață din [azi]: ieri și, după
/// un weekend sau o pauză, toate zilele de la ultimul raport (cel mult 4).
List<DateTime> zileRaport(DateTime azi, {DateTime? ultimulRaport}) {
  final a = _zi(azi);
  var dela = DateTime(a.year, a.month, a.day - 1);
  final u = ultimulRaport == null ? null : _zi(ultimulRaport);
  // Ultimul raport a acoperit zilele dinaintea lui; continuăm din ziua lui.
  if (u != null && u.isBefore(dela)) dela = u;
  final limita = DateTime(a.year, a.month, a.day - 4);
  if (dela.isBefore(limita)) dela = limita;
  return [
    for (var z = dela; z.isBefore(a); z = DateTime(z.year, z.month, z.day + 1)) z,
  ];
}

const _luni = [
  'ianuarie', 'februarie', 'martie', 'aprilie', 'mai', 'iunie', 'iulie', 'august',
  'septembrie', 'octombrie', 'noiembrie', 'decembrie',
];

String dataLunga(DateTime d) => '${d.day} ${_luni[d.month - 1]} ${d.year}';

String _nr(int n, String unu, String multe) => n == 1 ? '1 $unu' : '$n $multe';

/// Titlul, rândul scurt și rândurile notificării de dimineață.
({String titlu, String sumar, List<String> linii}) textRaportMO(
  List<ActGasit> gasite,
  List<DateTime> zile,
) {
  final perioada = zile.length <= 1
      ? (zile.isEmpty ? '' : dataLunga(zile.first))
      : '${dataLunga(zile.first)} – ${dataLunga(zile.last)}';
  if (gasite.isEmpty) {
    return (
      titlu: 'Monitorul Oficial',
      sumar: 'Nimic nou pe domeniile tale ($perioada)',
      linii: const [],
    );
  }
  return (
    titlu: 'Monitorul Oficial · ${_nr(gasite.length, 'act', 'acte')}',
    sumar: 'Pe domeniile tale, $perioada',
    linii: [
      for (final g in gasite.take(8)) '• ${g.act.denumire} ${_scurt(g.act.titlu)}',
      if (gasite.length > 8) '… și încă ${gasite.length - 8}',
    ],
  );
}

String _scurt(String titlu) {
  final t = titlu.trim();
  return t.length <= 90 ? t : '${t.substring(0, 87).trimRight()}…';
}

/// Textul notificării pentru acte noi apărute în cursul zilei.
({String titlu, String sumar, List<String> linii}) textActeNoi(List<ActGasit> noi) => (
  titlu: noi.length == 1
      ? 'Monitorul Oficial: ${noi.first.act.denumire}'
      : 'Monitorul Oficial: ${_nr(noi.length, 'act nou', 'acte noi')}',
  sumar: noi.length == 1 ? _scurt(noi.first.act.titlu) : noi.first.domenii.first,
  linii: [for (final g in noi.take(8)) '• ${g.act.denumire} ${_scurt(g.act.titlu)}'],
);

// ---------------------------------------------------------------------------
// Sursa

/// De unde aflăm ce a apărut într-o zi în Monitorul Oficial, Partea I.
abstract class SursaMonitorOficial {
  String get nume;

  /// Actele din toate Monitoarele (inclusiv „bis”) apărute în [zi].
  Future<List<ActPublicat>> actePublicate(DateTime zi);
}

class MonitorOficialException implements Exception {
  final String mesaj;
  MonitorOficialException(this.mesaj);

  @override
  String toString() => mesaj;
}

// ---------------------------------------------------------------------------
// Setări și stare

/// Alertele pentru Monitorul Oficial (Pro): domeniile alese, raportul de
/// dimineață și actele aflate pe zile (ultimele 14 zile, fără text).
class MonitorOficialService extends ChangeNotifier {
  MonitorOficialService._();
  static final MonitorOficialService instance = MonitorOficialService._();

  static const _cheie = 'monitor_oficial_v1';
  // v2: în v1 zilele erau salvate goale (numărul Monitorului nu era citit
  // din antet), iar zilele trecute nu se mai cer din nou.
  static const _cheieActe = 'monitor_oficial_acte_v2';

  /// Sursa folosită; se setează la pornire (și în teste).
  SursaMonitorOficial? sursa;

  /// Id-urile domeniilor predefinite bifate.
  Set<String> predefiniteAlese = {};

  /// Domeniile definite de utilizator.
  List<DomeniuInteres> proprii = [];

  /// Notificare imediat ce apare un act pe domeniile alese.
  bool alerteImediate = true;

  /// Raportul de dimineață.
  bool raportActiv = true;
  int ora = 8;
  int minut = 0;

  /// Raportul vine și când nu s-a publicat nimic pe domeniile alese.
  bool raportSiCandEGol = true;

  /// Ziua ultimului raport trimis.
  DateTime? ultimulRaport;

  /// Actele deja anunțate (cheile lor), ca să nu le anunțăm de două ori.
  Set<String> anuntate = {};

  /// Actele aflate, pe zile („2026-11-24” → acte), și când a fost întrebată
  /// sursa ultima dată pentru fiecare zi.
  final Map<String, List<ActPublicat>> _acte = {};
  final Map<String, DateTime> _verificatLa = {};

  List<DomeniuInteres> get domeniiActive => [
    for (final d in domeniiPredefinite)
      if (predefiniteAlese.contains(d.id)) d,
    ...proprii.where((d) => !d.gol),
  ];

  bool get areDomenii => domeniiActive.isNotEmpty;

  List<ActPublicat>? acteDin(DateTime zi) => _acte[_ziIso(zi)];
  DateTime? verificatLa(DateTime zi) => _verificatLa[_ziIso(zi)];

  Future<void> incarca() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final s = prefs.getString(_cheie);
    if (s != null) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        predefiniteAlese = {for (final x in (j['alese'] as List?) ?? const []) x as String};
        proprii = [
          for (final x in (j['proprii'] as List?) ?? const [])
            DomeniuInteres.fromJson(x as Map<String, dynamic>),
        ];
        alerteImediate = (j['imediate'] as bool?) ?? true;
        raportActiv = (j['raport'] as bool?) ?? true;
        ora = (j['ora'] as int?) ?? 8;
        minut = (j['minut'] as int?) ?? 0;
        raportSiCandEGol = (j['siGol'] as bool?) ?? true;
        ultimulRaport = DateTime.tryParse((j['ultimul'] as String?) ?? '');
        anuntate = {for (final x in (j['anuntate'] as List?) ?? const []) x as String};
      } catch (e) {
        debugPrint('Setările pentru Monitorul Oficial nu au putut fi citite: $e');
      }
    }
    final a = prefs.getString(_cheieActe);
    if (a != null) {
      try {
        final j = jsonDecode(a) as Map<String, dynamic>;
        _acte.clear();
        _verificatLa.clear();
        for (final e in j.entries) {
          final v = e.value as Map<String, dynamic>;
          _acte[e.key] = [
            for (final x in (v['acte'] as List?) ?? const [])
              ActPublicat.fromJson(x as Map<String, dynamic>),
          ];
          final la = DateTime.tryParse((v['la'] as String?) ?? '');
          if (la != null) _verificatLa[e.key] = la;
        }
      } catch (e) {
        debugPrint('Actele din Monitorul Oficial nu au putut fi citite: $e');
      }
    }
    notifyListeners();
  }

  Future<void> salveaza() async {
    final prefs = await SharedPreferences.getInstance();
    // Ținem minte doar cheile anunțate recent (actele vechi nu mai revin).
    if (anuntate.length > 2000) {
      anuntate = anuntate.skip(anuntate.length - 2000).toSet();
    }
    await prefs.setString(
      _cheie,
      jsonEncode({
        'alese': predefiniteAlese.toList(),
        'proprii': [for (final d in proprii) d.toJson()],
        'imediate': alerteImediate,
        'raport': raportActiv,
        'ora': ora,
        'minut': minut,
        'siGol': raportSiCandEGol,
        'ultimul': ultimulRaport?.toIso8601String(),
        'anuntate': anuntate.toList(),
      }),
    );
    notifyListeners();
  }

  Future<void> _salveazaActe() async {
    final prefs = await SharedPreferences.getInstance();
    final chei = _acte.keys.toList()..sort();
    for (final k in chei.take(chei.length > 14 ? chei.length - 14 : 0)) {
      _acte.remove(k);
      _verificatLa.remove(k);
    }
    await prefs.setString(
      _cheieActe,
      jsonEncode({
        for (final e in _acte.entries)
          e.key: {
            'acte': [for (final a in e.value) a.toJson()],
            'la': _verificatLa[e.key]?.toIso8601String(),
          },
      }),
    );
  }

  void comutaPredefinit(String id, bool ales) {
    ales ? predefiniteAlese.add(id) : predefiniteAlese.remove(id);
    salveaza();
  }

  Future<void> salveazaPropriu(DomeniuInteres d) async {
    final i = proprii.indexWhere((x) => x.id == d.id);
    if (i < 0) {
      proprii.add(d);
    } else {
      proprii[i] = d;
    }
    await salveaza();
  }

  Future<void> stergePropriu(String id) async {
    proprii.removeWhere((d) => d.id == id);
    await salveaza();
  }

  /// Cât de des întrebăm sursa pentru ziua de azi: Monitorul apare de-a
  /// lungul zilei, dar nu are rost să-l citim la fiecare rulare orară.
  static const intervalAzi = Duration(hours: 3);

  /// Aduce actele din [zi] de la sursă (dacă nu le avem deja proaspete) și le
  /// ține minte. Ziua de ieri se mai cere o dată dimineața, pentru Monitoarele
  /// apărute seara târziu. Întoarce null dacă nu e nicio sursă.
  Future<List<ActPublicat>?> aduce(DateTime zi, {required DateTime acum, bool fortat = false}) async {
    final s = sursa;
    if (s == null) return acteDin(zi);
    final k = _ziIso(zi);
    final la = _verificatLa[k];
    final ziua = _zi(zi);
    final azi = _zi(acum);
    final proaspat = la != null &&
        (ziua.isBefore(azi)
            // Zi trecută: ajunge o citire făcută după ce s-a terminat ziua.
            ? !la.isBefore(DateTime(ziua.year, ziua.month, ziua.day + 1, 6))
            : acum.difference(la) < intervalAzi);
    if (proaspat && !fortat) return _acte[k];
    final acte = await s.actePublicate(ziua);
    _acte[k] = acte;
    _verificatLa[k] = acum;
    await _salveazaActe();
    notifyListeners();
    return acte;
  }

  /// E momentul raportului de dimineață? O dată pe zi, după ora aleasă și
  /// până la 14:00. Monitorul apare și sâmbăta, uneori: raportul vine în
  /// fiecare zi în care e ceva de spus; luni acoperă și weekendul.
  bool eTimpulRaportului(DateTime acum) {
    if (!raportActiv || !areDomenii) return false;
    final deLa = DateTime(acum.year, acum.month, acum.day, ora, minut);
    if (acum.isBefore(deLa) || acum.hour >= 14) return false;
    final u = ultimulRaport;
    return u == null || _zi(u) != _zi(acum);
  }

  /// Raportul pentru zilele dinaintea lui [acum]. Întoarce null dacă vreo zi
  /// nu a putut fi citită de la sursă.
  Future<({List<ActGasit> gasite, List<DateTime> zile})?> raport(DateTime acum) async {
    final zile = zileRaport(acum, ultimulRaport: ultimulRaport);
    final acte = <ActPublicat>[];
    for (final z in zile) {
      final a = await aduce(z, acum: acum);
      if (a == null) return null;
      acte.addAll(a);
    }
    return (gasite: potriveste(acte, domeniiActive), zile: zile);
  }

  Future<void> marcheazaRaport(DateTime acum, Iterable<ActGasit> gasite) async {
    ultimulRaport = acum;
    anuntate.addAll(gasite.map((g) => g.act.cheie));
    await salveaza();
  }

  /// Actele de azi potrivite cu domeniile și încă neanunțate; le marchează
  /// anunțate.
  Future<List<ActGasit>> noiAzi(DateTime acum) async {
    final acte = await aduce(acum, acum: acum);
    if (acte == null) return const [];
    final noi = potriveste(acte, domeniiActive)
        .where((g) => !anuntate.contains(g.act.cheie))
        .toList();
    if (noi.isNotEmpty) {
      anuntate.addAll(noi.map((g) => g.act.cheie));
      await salveaza();
    }
    return noi;
  }
}
