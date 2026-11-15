import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/dosar_model.dart';
import '../utils/formatare.dart';
import 'biblioteca_service.dart';
import 'iccj_service.dart';
import 'parti_urmarite_service.dart';
import 'pro_service.dart';
import 'rezumat_service.dart';
import 'setari_notificari_service.dart';
import 'soap_service.dart';
import 'termene_procedurale_service.dart';
import 'widget_service.dart';

const _numeTask = 'verificare_dosare';
const _canalId = 'modificari_dosare';
const _canalPartiId = 'dosare_noi_parti';
const _canalLinisteId = 'ore_de_liniste';
const _canalRezumatId = 'rezumat_zilnic';
const payloadRezumat = 'rezumat';

/// Cât de des verifică telefonul portalul, în fundal. Android nu permite mai
/// des de 15 minute și poate întârzia rulările când economisește bateria.
const frecventaVerificare = Duration(hours: 1);

/// Peste atâtea dosare urmărite verificăm de două ori mai rar: fiecare dosar
/// înseamnă o cerere la portal, iar portalul ne limitează (HTTP 429).
const plafonDosare = 200;

/// Cât trece între două verificări automate complete. Instanțele lucrează în
/// zilele lucrătoare, ziua: atunci verificăm din oră în oră. Noaptea
/// (21:00–7:00) și în weekend grefele publică rar, așa că verificăm la 4 ore,
/// nu deloc. Peste [plafonDosare] intervalele se dublează.
Duration intervalVerificare(DateTime acum, {int dosare = 0}) {
  final liber =
      acum.weekday >= DateTime.saturday || acum.hour < 7 || acum.hour >= 21;
  final baza = Duration(hours: liber ? 4 : 1);
  return dosare > plafonDosare ? baza * 2 : baza;
}

/// Programul de verificare, în cuvinte, pentru ecranul Monitorizate.
String descriereProgramVerificare(int dosare) => dosare > plafonDosare
    ? 'Verificare automată la 2 ore în zilele lucrătoare, la 8 ore noaptea și în weekend '
          '(peste $plafonDosare de dosare)'
    : 'Verificare automată din oră în oră în zilele lucrătoare, la 4 ore noaptea și în weekend';

/// Punctul de intrare al verificării din fundal. Rulează într-un isolate
/// separat, pornit de Android chiar dacă aplicația este închisă.
@pragma('vm:entry-point')
void verificareInFundal() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await MonitorizareService.instance.verificaToate(programata: true);
      return true;
    } catch (e) {
      debugPrint('Verificarea din fundal a eșuat: $e');
      // false = Android reîncearcă mai târziu.
      return false;
    }
  });
}

/// Verifică dosarele din bibliotecă pe portal și anunță schimbările prin
/// notificări pe telefon.
class MonitorizareService {
  MonitorizareService._();
  static final MonitorizareService instance = MonitorizareService._();

  final _notificari = FlutterLocalNotificationsPlugin();
  bool _notificariPornite = false;

  /// Devine true când aplicația a fost deschisă dintr-o notificare, ca
  /// interfața să sară direct la bibliotecă.
  final ValueNotifier<bool> deschideBiblioteca = ValueNotifier(false);

  /// Devine true când aplicația a fost deschisă din rezumatul zilnic.
  final ValueNotifier<bool> deschideRezumat = ValueNotifier(false);

  void _dinNotificare(String? payload) {
    if (payload == payloadRezumat) {
      deschideRezumat.value = true;
    } else {
      deschideBiblioteca.value = true;
    }
  }

  /// Notificările și rularea în fundal sunt configurate doar pentru Android.
  bool get _suportat => !kIsWeb && Platform.isAndroid;

  /// De apelat la pornirea aplicației.
  Future<void> porneste() async {
    if (!_suportat) return;
    await _pornesteNotificari();

    final lansare = await _notificari.getNotificationAppLaunchDetails();
    if (lansare?.didNotificationLaunchApp ?? false) {
      _dinNotificare(lansare?.notificationResponse?.payload);
    }

    await Workmanager().initialize(verificareInFundal);
    await Workmanager().registerPeriodicTask(
      _numeTask,
      _numeTask,
      frequency: frecventaVerificare,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  Future<void> _pornesteNotificari() async {
    if (_notificariPornite) return;
    await _notificari.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_dosar'),
      ),
      onDidReceiveNotificationResponse: (r) => _dinNotificare(r.payload),
    );
    _notificariPornite = true;
  }

  /// Cere permisiunea de notificări (Android 13+). Întoarce false dacă
  /// utilizatorul a refuzat.
  Future<bool> cerePermisiune() async {
    if (!_suportat) return true;
    await _pornesteNotificari();
    final android = _notificari
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Interoghează portalul pentru fiecare număr de dosar din bibliotecă,
  /// actualizează biblioteca și trimite câte o notificare pentru fiecare dosar
  /// modificat. Aruncă [SoapException] doar dacă nicio interogare nu a reușit.
  ///
  /// După dosare verifică și părțile urmărite; o eroare acolo nu strică
  /// verificarea dosarelor. Ce s-a găsit pentru părți rămâne în
  /// [dosareNoiParti].
  ///
  /// [programata] = rularea orară din fundal: portalul e întrebat doar dacă
  /// a trecut [intervalVerificare] de la ultima verificare completă. Dosarele
  /// ÎCCJ se verifică oricum în fereastra lor de noapte.
  Future<List<RezultatVerificare>> verificaToate({
    SoapService? soap,
    IccjService? iccj,
    DateTime? acum,
    bool programata = false,
  }) async {
    final serviciu = soap ?? SoapService();
    final moment = acum ?? DateTime.now();
    await SetariNotificariService.instance.incarca();
    if (programata && !await _eDatorata(moment)) {
      final rezultate = await _verificaDosare(
        serviciu,
        iccj,
        moment,
        doarIccj: true,
      );
      await actualizeazaWidgeturi(acum: acum);
      if (programata) await trimiteRezumatulDacaEOra(moment);
      return rezultate;
    }
    final rezultate = await _verificaDosare(serviciu, iccj, moment);

    try {
      dosareNoiParti = await PartiUrmariteService.instance.verificaToate(
        soap: serviciu,
      );
      for (final r in dosareNoiParti) {
        await _notificaParte(r);
      }
    } catch (e) {
      dosareNoiParti = [];
      debugPrint('Verificarea părților urmărite a eșuat: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cheieUltimaVerificare,
      (acum ?? DateTime.now()).toIso8601String(),
    );
    // Widgeturile de pe ecran se reîmprospătează odată cu verificarea orară.
    await actualizeazaWidgeturi(acum: acum);
    if (programata) await trimiteRezumatulDacaEOra(moment);
    return rezultate;
  }

  /// Rezumatul zilnic (Pro) vine cu prima verificare din fundal de după ora
  /// aleasă, în zilele lucrătoare. Când nu e nimic de spus, nu trimitem nimic.
  Future<void> trimiteRezumatulDacaEOra(DateTime acum) async {
    try {
      await ProService.instance.incarca();
      final setari = RezumatService.instance;
      await setari.incarca();
      if (!ProService.instance.activ || !setari.eTimpul(acum)) return;
      await TermeneProceduraleService.instance.incarca();
      final r = construiesteRezumat(
        BibliotecaService.instance.dosare,
        TermeneProceduraleService.instance.termene,
        acum: acum,
        dela: setari.actualizariDeLa(acum),
      );
      if (!r.gol) await _notificaRezumat(r);
      await setari.marcheazaTrimis(acum);
    } catch (e) {
      debugPrint('Rezumatul zilnic nu a putut fi trimis: $e');
    }
  }

  Future<void> _notificaRezumat(Rezumat r) async {
    if (!_suportat) return;
    await _pornesteNotificari();
    final t = textRezumat(r, ziUrm: numeZiUrmatoare(r));
    await _notificari.show(
      id: 'rezumat'.hashCode & 0x7fffffff,
      title: t.titlu,
      body: t.sumar,
      notificationDetails: NotificationDetails(
        android: _detaliiAndroid(
          _canalRezumatId,
          'Rezumatul zilnic',
          'Termenele zilei și actualizările, dimineața',
          t.linii.join('\n'),
        ),
      ),
      payload: payloadRezumat,
    );
  }

  static const _cheieUltimaVerificare = 'ultima_verificare_completa';

  /// Rulările din fundal nu cad fix la oră: lăsăm 10 minute de toleranță, ca
  /// o rulare venită la 59 de minute să nu fie sărită.
  Future<bool> _eDatorata(DateTime acum) async {
    final biblioteca = BibliotecaService.instance;
    await biblioteca.incarca();
    final interval = intervalVerificare(acum, dosare: biblioteca.dosare.length);
    return eTimpulPentruVerificare(
      interval: interval - const Duration(minutes: 10),
      acum: acum,
    );
  }

  /// La deschiderea aplicației verificăm doar dacă ultima verificare
  /// completă (de aici sau din fundal) e mai veche de [interval]: cu zeci de
  /// dosare, fiecare deschidere ar trimite zeci de cereri și portalul ne
  /// limitează (HTTP 429).
  Future<bool> eTimpulPentruVerificare({
    Duration interval = const Duration(minutes: 15),
    DateTime? acum,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ultima = DateTime.tryParse(
      prefs.getString(_cheieUltimaVerificare) ?? '',
    );
    return ultima == null ||
        (acum ?? DateTime.now()).difference(ultima) >= interval;
  }

  /// Dosarele noi găsite pe numele părților urmărite la ultima verificare.
  List<RezultatParte> dosareNoiParti = [];

  Future<List<RezultatVerificare>> _verificaDosare(
    SoapService serviciu,
    IccjService? iccj,
    DateTime acum, {
    bool doarIccj = false,
  }) async {
    final biblioteca = BibliotecaService.instance;
    await biblioteca.incarca();
    // Dosarele Înaltei Curți nu sunt pe portal.just.ro: le întreabă serviciul
    // ÎCCJ, și doar în fereastra lui de noapte.
    final numereIccj = {
      for (final d in biblioteca.dosare)
        if (d.dosar.institutie == codIccj) d.dosar.numar,
    };
    final numere = doarIccj
        ? <String>{}
        : biblioteca.numereUrmarite.difference(numereIccj);
    if (numere.isEmpty && numereIccj.isEmpty) return [];

    final proaspete = <Dosar>[];
    final verificate = <String>{};
    Object? ultimaEroare;

    if (numereIccj.isNotEmpty && IccjService.inFereastra(acum)) {
      final scj = iccj ?? IccjService();
      for (final numar in numereIccj) {
        try {
          final gasite = await scj.cautaDosar(numar);
          proaspete.addAll(gasite.where((d) => d.numar == numar));
          verificate.add(numar);
        } catch (e) {
          debugPrint('Verificarea ÎCCJ a eșuat pentru $numar: $e');
        }
      }
    }

    // Pe rând, ca să nu aglomerăm portalul.
    for (final numar in numere) {
      try {
        final rezultat = await serviciu.cautaDosare(numarDosar: numar);
        proaspete.addAll(rezultat.dosare.where((d) => d.numar == numar));
        verificate.add(numar);
      } on PortalOcupatException catch (e) {
        // Portalul ne-a cerut pauză: restul dosarelor la verificarea următoare.
        ultimaEroare = e;
        break;
      } catch (e) {
        ultimaEroare = e;
      }
    }

    if (verificate.isEmpty && ultimaEroare != null) {
      throw ultimaEroare;
    }

    final rezultate = await biblioteca.aplicaActualizari(
      proaspete,
      numereVerificate: verificate,
    );
    for (final r in rezultate) {
      await _notifica(r);
    }
    return rezultate;
  }

  Future<void> _notifica(RezultatVerificare r) async {
    if (!_suportat) return;
    try {
      await _pornesteNotificari();
      final linii = [for (final s in r.schimbari) scurteaza(s, 300)];
      final text = linii.join('\n');
      await _notificari.show(
        // Un id per dosar: o schimbare nouă înlocuiește notificarea veche a
        // aceluiași dosar, fără să le atingă pe ale celorlalte.
        id: r.dosar.cheie.hashCode & 0x7fffffff,
        title: 'Dosar ${r.dosar.numar} · ${r.dosar.instanta}',
        body: linii.length == 1
            ? linii.first
            : '${linii.length} modificări: ${linii.first}',
        notificationDetails: NotificationDetails(
          android: _detaliiAndroid(
            _canalId,
            'Modificări în dosare',
            'Anunță schimbările apărute pe portal la dosarele din bibliotecă',
            text,
            cheie: r.dosar.cheie,
          ),
        ),
        payload: r.dosar.cheie,
      );
    } catch (e) {
      debugPrint('Notificarea nu a putut fi afișată: $e');
    }
  }

  Future<void> _notificaParte(RezultatParte r) async {
    if (!_suportat) return;
    try {
      await _pornesteNotificari();
      final linii = [
        for (final d in r.dosareNoi)
          [
            d.numar,
            d.instanta,
            d.obiect,
          ].where((e) => e.isNotEmpty).join(' · '),
      ];
      await _notificari.show(
        // Un id per parte urmărită, separat de cele ale dosarelor.
        id: ('parte|${r.parte.cheie}').hashCode & 0x7fffffff,
        title: linii.length == 1
            ? 'Dosar nou pe numele ${r.parte.nume}'
            : '${linii.length} dosare noi pe numele ${r.parte.nume}',
        body: scurteaza(linii.first, 300),
        notificationDetails: NotificationDetails(
          android: _detaliiAndroid(
            _canalPartiId,
            'Dosare noi pe numele părților',
            'Anunță dosarele noi apărute pe portal pe numele părților urmărite',
            linii.join('\n'),
          ),
        ),
        payload: 'parte|${r.parte.cheie}',
      );
    } catch (e) {
      debugPrint('Notificarea nu a putut fi afișată: $e');
    }
  }

  /// În orele de liniște notificarea merge pe un canal fără sunet și fără
  /// vibrație (pe Android, sunetul ține de canal), afară de dosarele
  /// marcate „sună oricând”.
  AndroidNotificationDetails _detaliiAndroid(
    String canal,
    String nume,
    String descriere,
    String text, {
    String? cheie,
  }) {
    final stil = BigTextStyleInformation(text);
    if (SetariNotificariService.instance.silentioasa(
      DateTime.now(),
      cheie: cheie,
    )) {
      return AndroidNotificationDetails(
        _canalLinisteId,
        'Ore de liniște',
        channelDescription:
            'Modificările apărute noaptea, fără sunet și fără vibrație',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        silent: true,
        styleInformation: stil,
      );
    }
    return AndroidNotificationDetails(
      canal,
      nume,
      channelDescription: descriere,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: stil,
    );
  }
}
