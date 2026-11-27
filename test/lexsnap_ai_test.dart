import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_management_app/lexsnap/ai_proxy.dart';
import 'package:legal_management_app/lexsnap/sugestii_aparare.dart';

import '../tool/lexsnap_proxy/server.dart' as proxy;

const _sursa = ArticolSursa(
  id: 'S1',
  act: 'OG nr. 2/2001',
  cheieAct: 'og2',
  articol: '31',
  text: '(1) Împotriva procesului-verbal se poate face plângere în termen de 15 zile.',
);

void main() {
  group('datele personale nu pleacă', () {
    test('CNP, IBAN, email, telefon, buletin, număr auto', () {
      final t = anonimizeaza(
        'Popescu Ion, CNP 1850101123456, CI seria RX nr. 123456, '
        'tel. 0722 123 456, ion@mail.ro, cont RO49 AAAA 1B31 0075 9384 0000, '
        'autoturismul B 123 ABC, conform HG 391 DIN 2006 și Legii nr. 85/2014.',
      );
      expect(t, contains('[CNP]'));
      expect(t, contains('seria [ACT IDENTITATE]'));
      expect(t, contains('[TELEFON]'));
      expect(t, contains('[EMAIL]'));
      expect(t, contains('[IBAN]'));
      expect(t, contains('[NR. AUTO]'));
      // Trimiterile la lege rămân.
      expect(t, contains('HG 391 DIN 2006'));
      expect(t, contains('Legii nr. 85/2014'));
    });

    test('nume după formule și adrese', () {
      final t = anonimizeaza(
        'Contravenientul POPESCU ION, domiciliat în București, str. Florilor '
        'nr. 12, bl. A3, sc. 2, ap. 4, sector 3. Agent constatator: Ionescu '
        'Vasile-Mihai. Numele și prenumele: Marin Gheorghe. Subsemnatul '
        'Dumitru Ana, fiul lui Ion. Domnul Avram. Conform art. 31 din OG nr. '
        '2/2001, Codul de procedură civilă și Legea 85/2014. Poliția Locală '
        'Ploiești, Calea Victoriei nr. 5.',
      );
      for (final nume in [
        'POPESCU',
        'Ionescu',
        'Vasile-Mihai',
        'Marin',
        'Dumitru',
        'Avram',
        'Florilor',
        'Victoriei',
        'A3',
      ]) {
        expect(t, isNot(contains(nume)), reason: nume);
      }
      expect(t, contains('Contravenientul [NUME]'));
      expect(t, contains('Agent constatator: [NUME]'));
      expect(t, contains('fiul lui [NUME]'));
      expect(t, contains('[ADRESĂ]'));
      // Rămân: localitatea, instituția și trimiterile la lege.
      expect(t, contains('București'));
      expect(t, contains('Poliția Locală Ploiești'));
      expect(t, contains('art. 31 din OG nr. 2/2001'));
      expect(t, contains('Codul de procedură civilă'));
      expect(t, contains('Legea 85/2014'));
    });
  });

  group('aplicația → proxy', () {
    test('trimite tokenul, documentul anonimizat și sursele', () async {
      late http.Request trimis;
      final f = FurnizorProxy(
        Uri.parse('https://exemplu.ro/lexsnap'),
        client: MockClient((r) async {
          trimis = r;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'raspuns':
                    '{"sugestii":[{"text":"Plângere în 15 zile",'
                    '"citari":[{"sursa":"S1","articol":"31","citat":"se poate face plângere"}]}]}',
              }),
            ),
            200,
          );
        }),
      );
      final s = await f.sugereaza('CNP 1850101123456', [_sursa]);
      expect(trimis.url.toString(), 'https://exemplu.ro/lexsnap/sugestii');
      expect(trimis.headers['X-LexSnap-Token'], tokenProxyAi);
      final corp = jsonDecode(trimis.body) as Map<String, dynamic>;
      expect(corp['document'], 'CNP [CNP]');
      expect((corp['surse'] as List).single['id'], 'S1');
      expect(s.single.citari.single.sursa, 'S1');
    });

    test('429 → mesaj clar', () async {
      final f = FurnizorProxy(
        Uri.parse('https://exemplu.ro/lexsnap'),
        client: MockClient((_) async => http.Response('', 429)),
      );
      expect(
        () => f.sugereaza('x', [_sursa]),
        throwsA(
          isA<EroareSugestii>().having(
            (e) => e.mesaj,
            'mesaj',
            contains('Prea multe'),
          ),
        ),
      );
    });

    test('fără adresă configurată: nedisponibil', () {
      expect(furnizorImplicit().disponibil, urlProxyAi.isNotEmpty);
    });
  });

  group('proxy-ul de pe server', () {
    late HttpServer server;
    late HttpClient client;
    var prompturi = <String>[];

    setUp(() async {
      prompturi = [];
      server = await proxy.porneste(
        const proxy.Configurare(port: 0, token: 'tk', maxPeMinutPeIp: 2),
        model: (sistem, prompt) async {
          prompturi.add(prompt);
          return '{"sugestii":[]}';
        },
      );
      client = HttpClient();
    });
    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    Future<(int, String)> post(Object corp, {String token = 'tk'}) async {
      final req = await client.post(
        '127.0.0.1',
        server.port,
        '/lexsnap/sugestii',
      );
      req.headers.set('x-lexsnap-token', token);
      req.add(utf8.encode(jsonEncode(corp)));
      final r = await req.close();
      return (r.statusCode, await r.transform(utf8.decoder).join());
    }

    final bun = {
      'document': 'PROCES-VERBAL ...',
      'surse': [_sursa.toJson()],
    };

    test('construiește promptul și întoarce răspunsul modelului', () async {
      final (cod, corp) = await post(bun);
      expect(cod, 200);
      expect(jsonDecode(corp)['raspuns'], '{"sugestii":[]}');
      expect(prompturi.single, contains('[S1] OG nr. 2/2001, art. 31'));
      expect(prompturi.single, contains('PROCES-VERBAL'));
    });

    test('fără token, cereri invalide, prea multe cereri', () async {
      expect((await post(bun, token: 'gresit')).$1, 401);
      expect((await post({'document': 'x', 'surse': []})).$1, 400);
      expect((await post({'prompt': 'scrie-mi o poezie'})).$1, 400);
      expect(
        (await post({
          'document': 'x',
          'surse': [
            {'id': 'altceva', 'act': 'a', 'articol': '1', 'text': 't'},
          ],
        })).$1,
        400,
      );
      expect((await post(bun)).$1, 200);
      expect((await post(bun)).$1, 200);
      expect((await post(bun)).$1, 429);
      expect(prompturi.length, 2);
    });
  });

  test('limita pe zi', () {
    var t = DateTime(2026, 11, 26, 10);
    final l = proxy.LimitaCereri(100, 2, acum: () => t);
    expect(l.permite('a'), isTrue);
    expect(l.permite('b'), isTrue);
    expect(l.permite('c'), isFalse);
    t = DateTime(2026, 11, 27, 0, 1);
    expect(l.permite('c'), isTrue);
  });
}
