import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/soap_service.dart';

// Structura unui răspuns real al operației CautareDosare, cu date fictive.
const _raspuns = '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<soap:Body><CautareDosareResponse xmlns="portalquery.just.ro"><CautareDosareResult>
<Dosar>
<parti><DosarParte><nume>POPESCU ION</nume><calitateParte>Reclamant</calitateParte></DosarParte></parti>
<sedinte>
<DosarSedinta><complet>C3 Civil</complet><data>2026-11-17T00:00:00</data><ora>09:00</ora><solutie /><solutieSumar /><dataPronuntare xsi:nil="true" /><documentSedinta xsi:nil="true" /><numarDocument /><dataDocument xsi:nil="true" /></DosarSedinta>
<DosarSedinta><complet>C3 Civil</complet><data>2026-09-15T00:00:00</data><ora>09:00</ora><solutie>Amână cauza</solutie><solutieSumar>probe</solutieSumar><dataPronuntare>2026-09-15T00:00:00</dataPronuntare><documentSedinta>incheieredesedinta</documentSedinta><numarDocument /><dataDocument>2026-09-15T00:00:00</dataDocument></DosarSedinta>
</sedinte>
<caiAtac><DosarCaleAtac><dataDeclarare>2026-10-01T00:00:00</dataDeclarare><parteDeclaratoare>POPESCU ION</parteDeclaratoare><tipCaleAtac>Apel</tipCaleAtac></DosarCaleAtac></caiAtac>
<numar>468/310/2026</numar><numarVechi /><data>2026-03-03T14:21:00</data><institutie>JudecatoriaSINAIA</institutie><departament>Sectia Civila</departament><categorieCaz>Civil</categorieCaz><stadiuProcesual>Fond</stadiuProcesual><obiect>uzucapiune</obiect><dataModificare>2026-05-14T08:33:52.94</dataModificare><categorieCazNume>Civil</categorieCazNume><stadiuProcesualNume>Fond</stadiuProcesualNume>
</Dosar>
</CautareDosareResult></CautareDosareResponse></soap:Body></soap:Envelope>''';

void main() {
  test('parsează dosarul cu ședințe, părți și căi de atac', () {
    final d = parseazaRaspunsDosare(_raspuns).single;
    expect(d.numar, '468/310/2026');
    expect(d.instanta, 'Judecătoria Sinaia');
    expect(d.cheie, '468/310/2026|JudecatoriaSINAIA');
    expect(d.data, DateTime(2026, 3, 3, 14, 21));
    expect(d.parti.single.calitate, 'Reclamant');
    expect(d.caiAtac.single.tip, 'Apel');

    expect(d.sedinte, hasLength(2));
    final viitoare = d.sedinteSortate.first;
    expect(viitoare.data, DateTime(2026, 11, 17));
    expect(viitoare.arePronuntare, isFalse);
    expect(viitoare.dataPronuntare, isNull);

    final pronuntata = d.sedinteSortate.last;
    expect(pronuntata.arePronuntare, isTrue);
    expect(pronuntata.solutie, 'Amână cauza');
    expect(pronuntata.document, 'incheieredesedinta');
  });

  test('răspunsul gol înseamnă niciun dosar', () {
    const gol = '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
        '<soap:Body><CautareDosareResponse xmlns="portalquery.just.ro" /></soap:Body></soap:Envelope>';
    expect(parseazaRaspunsDosare(gol), isEmpty);
  });

  test('dosarul supraviețuiește salvării ca JSON', () {
    final d = parseazaRaspunsDosare(_raspuns).single;
    expect(Dosar.fromJson(d.toJson()).toJson(), d.toJson());
  });
}
