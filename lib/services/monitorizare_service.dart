import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../models/dosar_model.dart';
import '../utils/formatare.dart';
import 'biblioteca_service.dart';
import 'soap_service.dart';

const _numeTask = 'verificare_dosare';
const _canalId = 'modificari_dosare';

/// Cât de des verifică telefonul portalul, în fundal. Android nu permite mai
/// des de 15 minute și poate întârzia rulările când economisește bateria.
const frecventaVerificare = Duration(hours: 1);

/// Punctul de intrare al verificării din fundal. Rulează într-un isolate
/// separat, pornit de Android chiar dacă aplicația este închisă.
@pragma('vm:entry-point')
void verificareInFundal() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await MonitorizareService.instance.verificaToate();
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

  /// Notificările și rularea în fundal sunt configurate doar pentru Android.
  bool get _suportat => !kIsWeb && Platform.isAndroid;

  /// De apelat la pornirea aplicației.
  Future<void> porneste() async {
    if (!_suportat) return;
    await _pornesteNotificari();

    final lansare = await _notificari.getNotificationAppLaunchDetails();
    if (lansare?.didNotificationLaunchApp ?? false) {
      deschideBiblioteca.value = true;
    }

    await Workmanager().initialize(verificareInFundal);
    await Workmanager().registerPeriodicTask(
      _numeTask,
      _numeTask,
      frequency: frecventaVerificare,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );  }

  Future<void> _pornesteNotificari() async {
    if (_notificariPornite) return;
    await _notificari.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_dosar'),
      ),
      onDidReceiveNotificationResponse: (_) => deschideBiblioteca.value = true,
    );
    _notificariPornite = true;
  }

  /// Cere permisiunea de notificări (Android 13+). Întoarce false dacă
  /// utilizatorul a refuzat.
  Future<bool> cerePermisiune() async {
    if (!_suportat) return true;
    await _pornesteNotificari();
    final android = _notificari.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Interoghează portalul pentru fiecare număr de dosar din bibliotecă,
  /// actualizează biblioteca și trimite câte o notificare pentru fiecare dosar
  /// modificat. Aruncă [SoapException] doar dacă nicio interogare nu a reușit.
  Future<List<RezultatVerificare>> verificaToate({SoapService? soap}) async {
    final biblioteca = BibliotecaService.instance;
    await biblioteca.incarca();
    final numere = biblioteca.numereUrmarite;
    if (numere.isEmpty) return [];

    final serviciu = soap ?? SoapService();
    final proaspete = <Dosar>[];
    final verificate = <String>{};
    Object? ultimaEroare;

    // Pe rând, ca să nu aglomerăm portalul.
    for (final numar in numere) {
      try {
        final rezultat = await serviciu.cautaDosare(numarDosar: numar);
        proaspete.addAll(rezultat.dosare.where((d) => d.numar == numar));
        verificate.add(numar);
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
        body: linii.length == 1 ? linii.first : '${linii.length} modificări: ${linii.first}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _canalId,
            'Modificări în dosare',
            channelDescription:
                'Anunță schimbările apărute pe portal la dosarele din bibliotecă',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(text),
          ),
        ),
        payload: r.dosar.cheie,
      );
    } catch (e) {
      debugPrint('Notificarea nu a putut fi afișată: $e');
    }
  }
}
