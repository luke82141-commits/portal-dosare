// Proxy-ul LexSnap AI, pentru serverul OVH.
//
// Aplicația trimite documentul (fără date de identificare) și articolele
// găsite; proxy-ul construiește promptul (același cod ca în aplicație) și
// întreabă modelul gratuit (Groq sau Gemini). Cheia API stă DOAR aici, în
// variabilele de mediu ale serviciului, niciodată în aplicație.
//
// Nu e un releu general: primește doar {document, surse}, cu limite de
// mărime și de număr de cereri. Nu salvează și nu scrie în jurnal textul
// documentelor.
//
// Pornire: vezi README.md din acest dosar.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:legal_management_app/lexsnap/prompt_aparare.dart';

/// Întreabă modelul; întoarce textul răspunsului (JSON-ul cu sugestii).
typedef Model = Future<String> Function(String sistem, String prompt);

class Configurare {
  final String furnizor;
  final String cheie;
  final String model;
  final String token;
  final String adresa;
  final int port;
  final int maxPeMinutPeIp;
  final int maxPeZi;

  const Configurare({
    this.furnizor = 'groq',
    this.cheie = '',
    this.model = '',
    this.token = 'lexsnap-app-v1',
    this.adresa = '127.0.0.1',
    this.port = 8787,
    this.maxPeMinutPeIp = 6,
    this.maxPeZi = 500,
  });

  factory Configurare.dinMediu(Map<String, String> env) {
    final furnizor = (env['LEXSNAP_FURNIZOR'] ?? 'groq').toLowerCase();
    return Configurare(
      furnizor: furnizor,
      cheie: furnizor == 'gemini'
          ? env['GEMINI_API_KEY'] ?? ''
          : env['GROQ_API_KEY'] ?? '',
      model: env['LEXSNAP_MODEL'] ?? '',
      token: env['LEXSNAP_TOKEN'] ?? 'lexsnap-app-v1',
      adresa: env['LEXSNAP_ADRESA'] ?? '127.0.0.1',
      port: int.tryParse(env['LEXSNAP_PORT'] ?? '') ?? 8787,
      maxPeMinutPeIp: int.tryParse(env['LEXSNAP_MAX_MINUT'] ?? '') ?? 6,
      maxPeZi: int.tryParse(env['LEXSNAP_MAX_ZI'] ?? '') ?? 500,
    );
  }
}

// ---------------------------------------------------------------------------
// Modelele

Future<Map<String, dynamic>> _postJson(
  HttpClient client,
  Uri url,
  Map<String, String> antete,
  Object corp,
) async {
  final req = await client.postUrl(url).timeout(const Duration(seconds: 20));
  antete.forEach(req.headers.set);
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode(corp)));
  final r = await req.close().timeout(const Duration(seconds: 80));
  final text = await r.transform(utf8.decoder).join();
  if (r.statusCode != 200) {
    // Doar codul: corpul răspunsului poate repeta fragmente din document.
    throw HttpException('Modelul a răspuns ${r.statusCode}.');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

/// Groq (API compatibil OpenAI). Nu folosește cererile pentru antrenare.
Model modelGroq(String cheie, {String model = '', HttpClient? client}) {
  final c = client ?? HttpClient();
  return (sistem, prompt) async {
    final j = await _postJson(
      c,
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      {'Authorization': 'Bearer $cheie'},
      {
        'model': model.isEmpty ? 'llama-3.3-70b-versatile' : model,
        'temperature': 0.1,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': sistem},
          {'role': 'user', 'content': prompt},
        ],
      },
    );
    return '${j['choices'][0]['message']['content']}';
  };
}

/// Google Gemini (planul gratuit poate folosi datele pentru îmbunătățirea
/// produselor Google: de preferat Groq pentru documente reale).
Model modelGemini(String cheie, {String model = '', HttpClient? client}) {
  final c = client ?? HttpClient();
  final m = model.isEmpty ? 'gemini-2.5-flash' : model;
  return (sistem, prompt) async {
    final j = await _postJson(
      c,
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent',
      ),
      {'x-goog-api-key': cheie},
      {
        'systemInstruction': {
          'parts': [
            {'text': sistem},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,
          'responseMimeType': 'application/json',
        },
      },
    );
    final parti = j['candidates'][0]['content']['parts'] as List;
    return parti.map((p) => '${p['text'] ?? ''}').join();
  };
}

// ---------------------------------------------------------------------------
// Limite

class LimitaCereri {
  final int peMinutPeIp;
  final int peZi;
  final DateTime Function() acum;
  final _ip = <String, List<DateTime>>{};
  var _zi = '';
  var _azi = 0;

  LimitaCereri(this.peMinutPeIp, this.peZi, {DateTime Function()? acum})
    : acum = acum ?? DateTime.now;

  /// True dacă cererea poate trece (și o numără).
  bool permite(String ip) {
    final t = acum();
    final zi = t.toIso8601String().substring(0, 10);
    if (zi != _zi) {
      _zi = zi;
      _azi = 0;
      _ip.clear();
    }
    if (_azi >= peZi) return false;
    final lista = _ip.putIfAbsent(ip, () => [])
      ..removeWhere((x) => t.difference(x) > const Duration(minutes: 1));
    if (lista.length >= peMinutPeIp) return false;
    lista.add(t);
    _azi++;
    return true;
  }
}

// ---------------------------------------------------------------------------
// Serverul

const _maxCorp = 200 * 1024;

Future<void> _raspunde(HttpRequest req, int cod, Object corp) async {
  req.response
    ..statusCode = cod
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(corp));
  await req.response.close();
}

/// IP-ul clientului: din X-Forwarded-For când cererea vine prin Caddy (local).
String _ipClient(HttpRequest req) {
  final direct = req.connectionInfo?.remoteAddress;
  final fwd = req.headers.value('x-forwarded-for');
  if (direct != null && direct.isLoopback && fwd != null && fwd.isNotEmpty) {
    return fwd.split(',').first.trim();
  }
  return direct?.address ?? '?';
}

/// Validează cererea și întoarce (document, surse), sau null.
(String, List<ArticolSursa>)? cerereValida(Object? j) {
  if (j is! Map<String, dynamic>) return null;
  final doc = j['document'];
  final surse = j['surse'];
  if (doc is! String || doc.trim().isEmpty || surse is! List) return null;
  if (surse.isEmpty || surse.length > maxSurse) return null;
  final lista = <ArticolSursa>[];
  for (final s in surse) {
    if (s is! Map<String, dynamic>) return null;
    final a = ArticolSursa.fromJson(s);
    if (!RegExp(r'^S\d{1,2}$').hasMatch(a.id) ||
        a.text.isEmpty ||
        a.text.length > maxCaractereSursa * 2 ||
        a.act.length > 300 ||
        a.articol.length > 20) {
      return null;
    }
    lista.add(a);
  }
  return (doc, lista);
}

Future<void> trateaza(
  HttpRequest req, {
  required Configurare config,
  required Model model,
  required LimitaCereri limita,
}) async {
  final cale = req.uri.path;
  if (req.method == 'GET' && cale.endsWith('/sanatate')) {
    return _raspunde(req, 200, {'ok': true});
  }
  if (req.method != 'POST' || !cale.endsWith('/sugestii')) {
    return _raspunde(req, 404, {'eroare': 'negasit'});
  }
  if (req.headers.value('x-lexsnap-token') != config.token) {
    return _raspunde(req, 401, {'eroare': 'neautorizat'});
  }
  if ((req.contentLength) > _maxCorp) {
    return _raspunde(req, 413, {'eroare': 'prea mare'});
  }
  final bytes = <int>[];
  await for (final b in req) {
    bytes.addAll(b);
    if (bytes.length > _maxCorp) {
      return _raspunde(req, 413, {'eroare': 'prea mare'});
    }
  }
  Object? j;
  try {
    j = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return _raspunde(req, 400, {'eroare': 'json invalid'});
  }
  final cerere = cerereValida(j);
  if (cerere == null) return _raspunde(req, 400, {'eroare': 'cerere invalida'});
  if (!limita.permite(_ipClient(req))) {
    return _raspunde(req, 429, {'eroare': 'prea multe cereri'});
  }
  final (doc, surse) = cerere;
  final pornit = DateTime.now();
  final String raspuns;
  try {
    raspuns = await model(instructiuniSistem, construiestePrompt(doc, surse));
  } catch (e) {
    // Fără textul documentului în jurnal.
    stderr.writeln('${pornit.toIso8601String()} eroare model: $e');
    return _raspunde(req, 502, {'eroare': 'modelul nu a raspuns'});
  }
  stdout.writeln(
    '${pornit.toIso8601String()} ok surse=${surse.length} '
    'ms=${DateTime.now().difference(pornit).inMilliseconds}',
  );
  return _raspunde(req, 200, {'raspuns': raspuns});
}

Future<HttpServer> porneste(Configurare config, {Model? model}) async {
  final m =
      model ??
      (config.furnizor == 'gemini'
          ? modelGemini(config.cheie, model: config.model)
          : modelGroq(config.cheie, model: config.model));
  final limita = LimitaCereri(config.maxPeMinutPeIp, config.maxPeZi);
  final server = await HttpServer.bind(config.adresa, config.port);
  server.listen((req) async {
    try {
      await trateaza(req, config: config, model: m, limita: limita);
    } catch (e) {
      stderr.writeln('eroare: $e');
      try {
        await _raspunde(req, 500, {'eroare': 'intern'});
      } catch (_) {}
    }
  });
  return server;
}

Future<void> main() async {
  final config = Configurare.dinMediu(Platform.environment);
  if (config.cheie.isEmpty) {
    stderr.writeln(
      'Lipsește cheia: GROQ_API_KEY (sau GEMINI_API_KEY cu LEXSNAP_FURNIZOR=gemini).',
    );
    exit(1);
  }
  final s = await porneste(config);
  stdout.writeln(
    'LexSnap AI pornit pe ${s.address.address}:${s.port} (${config.furnizor})',
  );
}
