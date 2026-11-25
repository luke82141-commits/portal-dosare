import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:home_widget/home_widget.dart';

import '../services/biblioteca_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/client_service.dart';
import '../services/culori_service.dart';
import '../services/monitorizare_service.dart';
import '../services/parti_urmarite_service.dart';
import '../services/pro_service.dart';
import '../services/widget_service.dart';
import 'calendar_screen.dart';
import 'cautare_screen.dart';
import 'dosar_detaliu_screen.dart';
import 'dosare_selectie_screen.dart';
import 'legislatie_screen.dart';
import 'monitor_oficial_screen.dart';
import 'monitorizate_screen.dart';
import 'notificari_screen.dart';
import 'rezumat_zilnic_screen.dart';
import 'widgeturi_screen.dart';
import '../widgets/meniu_utilitati.dart';

/// Cadrul aplicației: Căutare, Monitorizate, Calendar, Instanțe și Notificări, cu bara de
/// navigare jos (Figma: „Bară navigare”). La derularea în jos bara se strânge
/// într-un buton rotund, care o readuce la atingere; la derularea în sus revine
/// singură. Ultima filă a barei deschide „Utilități”.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _filaCautare = 0;
  static const _filaMonitorizate = 1;
  static const _filaNotificari = 4;

  int _tab = 0;
  bool _baraStransa = false;

  void _strangeBara(bool strans) {
    if (_baraStransa != strans) setState(() => _baraStransa = strans);
  }

  bool _laDerulare(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.reverse && n.metrics.extentAfter > 0) {
      _strangeBara(true);
    } else if (n.direction == ScrollDirection.forward) {
      _strangeBara(false);
    }
    return false;
  }

  void _alegeFila(int i) => setState(() {
    _tab = i;
    _baraStransa = false;
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MonitorizareService.instance.deschideBiblioteca.addListener(_laNotificare);
    MonitorizareService.instance.deschideRezumat.addListener(_laRezumat);
    MonitorizareService.instance.deschideMonitorOficial.addListener(_laMonitorOficial);
    _laNotificare();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _laRezumat();
      _laMonitorOficial();
    });
    _actualizeaza();
    BibliotecaService.instance.addListener(_programeazaWidgeturi);
    ProService.instance.addListener(_programeazaWidgeturi);
    if (!kIsWeb && Platform.isAndroid) {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_dinWidget);
      _clicuriWidget = HomeWidget.widgetClicked.listen(_dinWidget);
    }
  }

  StreamSubscription<Uri?>? _clicuriWidget;
  Timer? _temporizatorWidgeturi;

  /// Orice schimbare în bibliotecă (citit, adăugat, șters) ajunge și pe
  /// widgeturi, adunată într-o singură actualizare.
  void _programeazaWidgeturi() {
    _temporizatorWidgeturi?.cancel();
    _temporizatorWidgeturi = Timer(
      const Duration(seconds: 2),
      actualizeazaWidgeturi,
    );
  }

  /// Atingerea unui widget: portaldosare://termene, ://actualizari,
  /// ://dosar?cheie=… sau ://widgeturi (widgetul blocat).
  Future<void> _dinWidget(Uri? uri) async {
    if (uri == null) return;
    // La pornirea din widget biblioteca poate fi încă necitită.
    if (uri.host == 'dosar') await BibliotecaService.instance.incarca();
    if (!mounted) return;
    final Widget? ecran = switch (uri.host) {
      'termene' => const DosareSelectieScreen(selectie: SelectieDosare.termene),
      'actualizari' => const DosareSelectieScreen(
        selectie: SelectieDosare.actualizari,
      ),
      'widgeturi' => const WidgeturiScreen(),
      'dosar' => () {
        final cheie = uri.queryParameters['cheie'];
        for (final s in BibliotecaService.instance.dosare) {
          if (s.dosar.cheie == cheie) return DosarDetaliuScreen(dosar: s.dosar);
        }
        return null;
      }(),
      _ => null,
    };
    if (ecran == null) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
  }

  /// Apăsările lupei rotunde, ascultate de ecranul Căutare.
  final _cereriCautare = ValueNotifier<int>(0);

  @override
  void dispose() {
    _cereriCautare.dispose();
    _clicuriWidget?.cancel();
    _temporizatorWidgeturi?.cancel();
    BibliotecaService.instance.removeListener(_programeazaWidgeturi);
    ProService.instance.removeListener(_programeazaWidgeturi);
    WidgetsBinding.instance.removeObserver(this);
    MonitorizareService.instance.deschideBiblioteca.removeListener(
      _laNotificare,
    );
    MonitorizareService.instance.deschideRezumat.removeListener(_laRezumat);
    MonitorizareService.instance.deschideMonitorOficial.removeListener(_laMonitorOficial);
    super.dispose();
  }

  // Verificarea din fundal scrie direct pe disc, deci la revenirea în
  // aplicație biblioteca trebuie recitită.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _actualizeaza();
  }

  Future<void> _actualizeaza() async {
    try {
      await BibliotecaService.instance.incarca();
      await CuloriDosareService.instance.incarca();
      await CalendarSyncService.instance.incarca();
      await PartiUrmariteService.instance.incarca();
      await ProService.instance.incarca();
      await ClientService.instance.incarca();
      final monitorizare = MonitorizareService.instance;
      // Cu foarte multe dosare, o deschidere la 15 minute ar trimite sute de
      // cereri: peste plafon verificăm la deschidere cel mult o dată pe oră.
      final multe = BibliotecaService.instance.dosare.length > plafonDosare;
      if (await monitorizare.eTimpulPentruVerificare(
        interval: multe
            ? const Duration(hours: 1)
            : const Duration(minutes: 15),
      )) {
        await monitorizare.verificaToate();
      }
      // Termenele noi apărute pe portal ajung și în calendarul ales.
      final sync = CalendarSyncService.instance;
      if (sync.configurat) {
        await sync.trimite([
          for (final s in BibliotecaService.instance.dosare) s.dosar,
        ]);
      }
    } catch (e) {
      // Fără rețea la pornire: rămân datele salvate, iar verificarea din
      // fundal reîncearcă.
      debugPrint('Verificarea la pornire a eșuat: $e');
    }
  }

  /// Aplicația deschisă dintr-o notificare sare direct la Notificări.
  /// Atingerea rezumatului zilnic deschide ecranul lui.
  void _laRezumat() {
    final semnal = MonitorizareService.instance.deschideRezumat;
    if (!semnal.value || !mounted) return;
    semnal.value = false;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RezumatZilnicScreen()));
  }

  /// O alertă din Monitorul Oficial deschide ecranul lui.
  void _laMonitorOficial() {
    final semnal = MonitorizareService.instance.deschideMonitorOficial;
    if (!semnal.value || !mounted) return;
    semnal.value = false;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MonitorOficialScreen()));
  }

  void _laNotificare() {
    final semnal = MonitorizareService.instance.deschideBiblioteca;
    if (!semnal.value) return;
    semnal.value = false;
    if (mounted) _alegeFila(_filaNotificari);
  }

  static const _file = [
    (Icons.search, Icons.search, 'Căutare'),
    // „Monitorizate” nu încape pe o filă din șase și se rupea în două.
    (Icons.bookmark_border, Icons.bookmark, 'Urmărite'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
    (Icons.menu_book_outlined, Icons.menu_book, 'Legislație'),
    (Icons.notifications_none, Icons.notifications, 'Notificări'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BibliotecaService.instance,
      builder: (context, _) {
        final necitite = BibliotecaService.instance.totalNecitite;
        Widget iconita(IconData icon, int fila) => fila == _filaNotificari
            ? Badge(
                isLabelVisible: necitite > 0,
                label: Text('$necitite'),
                child: Icon(icon),
              )
            : Icon(icon);

        return Scaffold(
          body: NotificationListener<UserScrollNotification>(
            onNotification: _laDerulare,
            child: IndexedStack(
              index: _tab,
              children: [
                CautareScreen(
                  onVeziMonitorizate: () => _alegeFila(_filaMonitorizate),
                  cereriCautare: _cereriCautare,
                ),
                const MonitorizateScreen(),
                const CalendarScreen(),
                const LegislatieScreen(),
                const NotificariScreen(),
              ],
            ),
          ),
          // Bara strânsă devine butonul rotund din colț, cu fila curentă.
          floatingActionButton: AnimatedScale(
            scale: _baraStransa ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            // Pe fila Căutare lupa chiar caută (și ascunde tastatura); pe
            // celelalte readuce bara de navigare.
            child: FloatingActionButton(
              tooltip: _tab == _filaCautare
                  ? 'Caută'
                  : 'Arată bara de navigare',
              onPressed: !_baraStransa
                  ? null
                  : _tab == _filaCautare
                  ? () => _cereriCautare.value++
                  : () => _strangeBara(false),
              child: iconita(_file[_tab].$2, _tab),
            ),
          ),
          bottomNavigationBar: ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: _baraStransa ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: NavigationBar(
                selectedIndex: _tab,
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                onDestinationSelected: (i) => i == _file.length
                    ? deschideUtilitati(context)
                    : _alegeFila(i),
                destinations: [
                  for (final (i, f) in _file.indexed)
                    NavigationDestination(
                      icon: iconita(f.$1, i),
                      selectedIcon: iconita(f.$2, i),
                      label: f.$3,
                    ),
                  const NavigationDestination(
                    icon: Icon(Icons.widgets_outlined),
                    label: 'Utilități',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
