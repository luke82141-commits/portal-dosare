import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../services/biblioteca_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/culori_service.dart';
import '../services/monitorizare_service.dart';
import '../services/parti_urmarite_service.dart';
import 'calendar_screen.dart';
import 'cautare_screen.dart';
import 'instante_screen.dart';
import 'monitorizate_screen.dart';
import 'notificari_screen.dart';
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
    _laNotificare();
    _actualizeaza();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MonitorizareService.instance.deschideBiblioteca.removeListener(_laNotificare);
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
      await MonitorizareService.instance.verificaToate();
      // Termenele noi apărute pe portal ajung și în calendarul ales.
      final sync = CalendarSyncService.instance;
      if (sync.configurat) {
        await sync.trimite([for (final s in BibliotecaService.instance.dosare) s.dosar]);
      }
    } catch (e) {
      // Fără rețea la pornire: rămân datele salvate, iar verificarea din
      // fundal reîncearcă.
      debugPrint('Verificarea la pornire a eșuat: $e');
    }
  }

  /// Aplicația deschisă dintr-o notificare sare direct la Notificări.
  void _laNotificare() {
    final semnal = MonitorizareService.instance.deschideBiblioteca;
    if (!semnal.value) return;
    semnal.value = false;
    if (mounted) _alegeFila(_filaNotificari);
  }

  static const _file = [
    (Icons.search, Icons.search, 'Căutare'),
    (Icons.bookmark_border, Icons.bookmark, 'Monitorizate'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
    (Icons.account_balance_outlined, Icons.account_balance, 'Instanțe'),
    (Icons.notifications_none, Icons.notifications, 'Notificări'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BibliotecaService.instance,
      builder: (context, _) {
        final necitite = BibliotecaService.instance.totalNecitite;
        Widget iconita(IconData icon, int fila) => fila == _filaNotificari
            ? Badge(isLabelVisible: necitite > 0, label: Text('$necitite'), child: Icon(icon))
            : Icon(icon);

        return Scaffold(
          body: NotificationListener<UserScrollNotification>(
            onNotification: _laDerulare,
            child: IndexedStack(
              index: _tab,
              children: [
                CautareScreen(onVeziMonitorizate: () => _alegeFila(_filaMonitorizate)),
                const MonitorizateScreen(),
                const CalendarScreen(),
                const InstanteScreen(),
                const NotificariScreen(),
              ],
            ),
          ),
          // Bara strânsă devine butonul rotund din colț, cu fila curentă.
          floatingActionButton: AnimatedScale(
            scale: _baraStransa ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: FloatingActionButton(
              tooltip: 'Arată bara de navigare',
              onPressed: _baraStransa ? () => _strangeBara(false) : null,
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
                labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                onDestinationSelected: (i) =>
                    i == _file.length ? deschideUtilitati(context) : _alegeFila(i),
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
