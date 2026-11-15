/// Actele căutate cel mai des de avocați, cu numele sub care le știe lumea
/// („Codul civil”, „NCPC”, „Legea insolvenței”). Așa „codul civ” găsește
/// direct Legea 287/2009, nu sute de acte care pomenesc codul civil.
class ActCunoscut {
  final String nume;
  final String tip;
  final String numar;
  final int an;

  /// Alte nume și abrevieri, fără diacritice, cu litere mici.
  final List<String> alias;

  /// Anul intrării în vigoare, când e altul decât anul actului (serviciul
  /// filtrează după el: Codul civil, Legea 287/2009, are 2011).
  int? get anVigoare => _anVigoare['$numar/$an'];

  const ActCunoscut(
    this.nume,
    this.tip,
    this.numar,
    this.an, [
    this.alias = const [],
  ]);

  String get trimitere {
    final t = switch (tip) {
      'ORDONANTA DE URGENTA' => 'OUG',
      'ORDONANTA' => 'OG',
      'HOTARARE' => 'HG',
      'CONSTITUTIE' => 'Constituția',
      _ => 'Legea',
    };
    return tip == 'CONSTITUTIE' ? 'Constituția României' : '$t nr. $numar/$an';
  }
}

const _anVigoare = {
  '287/2009': 2011,
  '134/2010': 2013,
  '286/2009': 2014,
  '135/2010': 2014,
  '227/2015': 2016,
  '207/2015': 2016,
  '76/2012': 2013,
  '187/2012': 2014,
  '255/2013': 2014,
};

const acteCunoscute = <ActCunoscut>[
  ActCunoscut('Constituția României', 'CONSTITUTIE', '', 1991, ['constitutia']),
  ActCunoscut('Codul civil', 'LEGE', '287', 2009, [
    'cod civil',
    'ncc',
    'c.civ',
    'c. civ',
  ]),
  ActCunoscut('Codul de procedură civilă', 'LEGE', '134', 2010, [
    'cod procedura civila',
    'ncpc',
    'cpc',
    'c.proc.civ',
    'c. proc. civ',
  ]),
  ActCunoscut('Codul penal', 'LEGE', '286', 2009, [
    'cod penal',
    'ncp',
    'c.pen',
    'c. pen',
  ]),
  ActCunoscut('Codul de procedură penală', 'LEGE', '135', 2010, [
    'cod procedura penala',
    'ncpp',
    'cpp',
    'c.proc.pen',
    'c. proc. pen',
  ]),
  ActCunoscut('Codul muncii', 'LEGE', '53', 2003, ['cod muncii', 'c.muncii']),
  ActCunoscut('Codul fiscal', 'LEGE', '227', 2015, ['cod fiscal', 'c.fisc']),
  ActCunoscut('Codul de procedură fiscală', 'LEGE', '207', 2015, [
    'cod procedura fiscala',
  ]),
  ActCunoscut('Codul administrativ', 'ORDONANTA DE URGENTA', '57', 2019, [
    'cod administrativ',
    'functionari publici',
  ]),
  ActCunoscut(
    'Codul amenajării teritoriului, urbanismului și construcțiilor',
    'LEGE',
    '169',
    2026,
    [
      'codul urbanismului',
      'cod urbanism',
      'codul constructiilor',
      'cod constructii',
      'codul amenajarii teritoriului',
    ],
  ),
  ActCunoscut('Codul rutier', 'ORDONANTA DE URGENTA', '195', 2002, [
    'cod rutier',
    'circulatia pe drumurile publice',
  ]),
  ActCunoscut('Punerea în aplicare a Codului civil', 'LEGE', '71', 2011, [
    'aplicare cod civil',
  ]),
  ActCunoscut(
    'Punerea în aplicare a Codului de procedură civilă',
    'LEGE',
    '76',
    2012,
    ['aplicare cod procedura civila'],
  ),
  ActCunoscut('Punerea în aplicare a Codului penal', 'LEGE', '187', 2012, [
    'aplicare cod penal',
  ]),
  ActCunoscut(
    'Punerea în aplicare a Codului de procedură penală',
    'LEGE',
    '255',
    2013,
    ['aplicare cod procedura penala'],
  ),
  ActCunoscut('Legea insolvenței', 'LEGE', '85', 2014, [
    'insolventa',
    'insolventei',
  ]),
  ActCunoscut('Legea societăților', 'LEGE', '31', 1990, [
    'societatilor',
    'societati comerciale',
  ]),
  ActCunoscut('Legea contenciosului administrativ', 'LEGE', '554', 2004, [
    'contencios',
  ]),
  ActCunoscut('Regimul contravențiilor', 'ORDONANTA', '2', 2001, [
    'contraventii',
    'og 2/2001',
  ]),
  ActCunoscut('Legea fondului funciar', 'LEGE', '18', 1991, ['fond funciar']),
  ActCunoscut('Imobilele preluate abuziv', 'LEGE', '10', 2001, [
    'retrocedare',
    'preluate abuziv',
  ]),
  ActCunoscut('Legea cadastrului', 'LEGE', '7', 1996, [
    'cadastru',
    'carte funciara',
  ]),
  ActCunoscut('Legea construcțiilor', 'LEGE', '50', 1991, [
    'autorizare constructii',
  ]),
  ActCunoscut('Legea medierii', 'LEGE', '192', 2006, ['mediere', 'mediator']),
  ActCunoscut('Profesia de avocat', 'LEGE', '51', 1995, [
    'avocat',
    'avocatura',
  ]),
  ActCunoscut('Organizarea judiciară', 'LEGE', '304', 2022, [
    'organizare judiciara',
  ]),
  ActCunoscut('Statutul judecătorilor și procurorilor', 'LEGE', '303', 2022, [
    'statut magistrati',
  ]),
  ActCunoscut('Protecția drepturilor copilului', 'LEGE', '272', 2004, [
    'drepturile copilului',
  ]),
  ActCunoscut('Violența domestică', 'LEGE', '217', 2003, [
    'violenta in familie',
    'ordin de protectie',
  ]),
  ActCunoscut('Achizițiile publice', 'LEGE', '98', 2016, ['achizitii publice']),
  ActCunoscut('Remedii în achiziții publice', 'LEGE', '101', 2016, [
    'contestatii achizitii',
  ]),
  ActCunoscut(
    'Protecția consumatorilor în contracte de credit',
    'ORDONANTA DE URGENTA',
    '50',
    2010,
    ['credit consumatori'],
  ),
  ActCunoscut('Clauzele abuzive', 'LEGE', '193', 2000, ['clauze abuzive']),
  ActCunoscut('Combaterea corupției', 'LEGE', '78', 2000, ['coruptie']),
  ActCunoscut('Combaterea evaziunii fiscale', 'LEGE', '241', 2005, [
    'evaziune',
  ]),
  ActCunoscut('Traficul de droguri', 'LEGE', '143', 2000, ['droguri']),
  ActCunoscut('Executarea pedepselor', 'LEGE', '254', 2013, [
    'executarea pedepselor',
  ]),
  ActCunoscut('Proprietatea publică', 'LEGE', '213', 1998, [
    'proprietate publica',
  ]),
  ActCunoscut('Legea locuinței', 'LEGE', '114', 1996, ['locuinta']),
  ActCunoscut('Asociațiile de proprietari', 'LEGE', '196', 2018, [
    'asociatii de proprietari',
  ]),
  ActCunoscut('Sistemul public de pensii', 'LEGE', '360', 2023, ['pensii']),
  ActCunoscut('Dialogul social', 'LEGE', '367', 2022, [
    'dialog social',
    'sindicate',
  ]),
  ActCunoscut(
    'Taxele judiciare de timbru',
    'ORDONANTA DE URGENTA',
    '80',
    2013,
    ['taxa de timbru', 'taxe judiciare'],
  ),
  ActCunoscut('Ajutorul public judiciar', 'ORDONANTA DE URGENTA', '51', 2008, [
    'ajutor public judiciar',
  ]),
  ActCunoscut('Executorii judecătorești', 'LEGE', '188', 2000, [
    'executor judecatoresc',
  ]),
  ActCunoscut('Notarii publici', 'LEGE', '36', 1995, ['notar']),
  ActCunoscut('Protecția datelor (aplicarea GDPR)', 'LEGE', '190', 2018, [
    'gdpr',
    'date personale',
  ]),
];
