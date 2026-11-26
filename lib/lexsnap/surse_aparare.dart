import '../services/act_export.dart' show structureazaInFundal;
import '../services/act_structura.dart';
import '../services/forma_consolidata.dart';
import '../services/legislatie_service.dart';
import 'analiza_document.dart' show MotivPrevedere;
import 'lexsnap_service.dart';
import 'prompt_aparare.dart';

/// Textul articolelor găsite la pasul 2, ca surse numerotate (S1, S2...)
/// pentru model.
///
/// - Textul e cel la zi (forma consolidată de pe legislatie.just.ro), când se
///   poate citi; altfel cel din serviciu (forma de bază).
/// - La coduri (Codul civil, Codul de procedură civilă) legea care le aprobă
///   are doar câteva rânduri: căutăm codul anexat și luăm articolul din el.
class PregatireSurse {
  final LegislatieService service;
  final FormaConsolidataService forme;

  PregatireSurse({LegislatieService? service, FormaConsolidataService? forme})
    : service = service ?? LegislatieService.instance,
      forme = forme ?? FormaConsolidataService.instance;

  /// Sursele și actul fiecăreia (după id), ca citările să poată fi
  /// deschise în aplicație.
  Future<({List<ArticolSursa> surse, Map<String, ActNormativ> acte})>
  pregateste(List<PrevedereGasita> prevederi) async {
    final surse = <ArticolSursa>[];
    final acte = <String, ActNormativ>{};
    for (final p in prevederi) {
      if (p.cautare.articole.isEmpty) continue;
      for (final gasit in p.acte) {
        final act = await _actCuText(gasit);
        final blocuri = await _blocuri(act);
        if (blocuri.isEmpty) continue;
        for (final a in p.cautare.articole) {
          if (surse.length >= maxSurse) break;
          if (surse.any(
            (s) => s.cheieAct == act.cheie && s.articol == a.articol,
          )) {
            continue;
          }
          final i = indiceArticol(blocuri, a.articol);
          if (i == null) continue;
          final linii = [
            for (final x in blocuriArticol(blocuri, i).skip(1))
              if (x.tip != TipBloc.nota)
                [x.eticheta, x.text].where((s) => s.isNotEmpty).join(' '),
          ];
          final text = linii.join('\n').trim();
          if (text.isEmpty) continue;
          final id = 'S${surse.length + 1}';
          surse.add(
            ArticolSursa(
              id: id,
              act: p.cautare.motiv == MotivPrevedere.termenCheie
                  ? act.denumireScurta
                  : p.cautare.eticheta,
              cheieAct: act.cheie,
              articol: a.articol,
              text: text,
            ),
          );
          acte[id] = act;
        }
      }
    }
    return (surse: surse, acte: acte);
  }

  /// Codul anexat în locul legii care doar îl aprobă.
  Future<ActNormativ> _actCuText(ActNormativ act) async {
    final nume = numeCodAnexat(act);
    if (nume == null || act.text.length >= 3000) return act;
    for (final c in [
      CerereLegislatie(titlu: nume),
      if (act.numar.isNotEmpty && act.an != null)
        CerereLegislatie(titlu: 'Legea nr. ${act.numar}/${act.an}'),
    ]) {
      try {
        final p = await service.cauta(c, simplu: true);
        final cod = alegeCodAnexat(p.acte, act, nume);
        if (cod != null) return cod;
      } catch (_) {}
    }
    return act;
  }

  Future<List<BlocAct>> _blocuri(ActNormativ act) async {
    final id = idDinLink(act.linkHtml);
    if (id != null) {
      try {
        final f = await forme.forma(id);
        if (f != null && f.blocuri.isNotEmpty) return f.blocuri;
      } catch (_) {}
    }
    if (act.text.isEmpty) return const [];
    return structureazaInFundal(act.text);
  }
}
