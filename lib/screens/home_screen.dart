import 'package:flutter/material.dart';

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

/// Cadrul aplicației: Căutare, Monitorizate, Calendar, Instanțe și Notificări, cu bara de
/// navigare jos (Figma: „Bară navigare”).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _filaMonitorizate = 1;
  static const _filaNotificari = 4;

  int _tab = 0;

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
    if (mounted) setState(() => _tab = _filaNotificari);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          CautareScreen(onVeziMonitorizate: () => setState(() => _tab = _filaMonitorizate)),
          const MonitorizateScreen(),
          const CalendarScreen(),
          const InstanteScreen(),
          const NotificariScreen(),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final necitite = BibliotecaService.instance.totalNecitite;
          Widget clopotel(IconData icon) => Badge(
                isLabelVisible: necitite > 0,
                label: Text('$necitite'),
                child: Icon(icon),
              );
          return NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.search), label: 'Căutare'),
              const NavigationDestination(
                icon: Icon(Icons.bookmark_border),
                selectedIcon: Icon(Icons.bookmark),
                label: 'Monitorizate',
              ),
              const NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Calendar',
              ),
              const NavigationDestination(
                icon: Icon(Icons.account_balance_outlined),
                selectedIcon: Icon(Icons.account_balance),
                label: 'Instanțe',
              ),
              NavigationDestination(
                icon: clopotel(Icons.notifications_none),
                selectedIcon: clopotel(Icons.notifications),
                label: 'Notificări',
              ),
            ],
          );
        },
      ),
    );
  }
}
