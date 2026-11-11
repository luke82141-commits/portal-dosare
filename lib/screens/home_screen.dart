import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';
import 'cautare_screen.dart';
import 'monitorizate_screen.dart';
import 'notificari_screen.dart';

/// Cadrul aplicației: Căutare, Monitorizate și Notificări, cu bara de
/// navigare jos (Figma: „Bară navigare”).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _filaMonitorizate = 1;
  static const _filaNotificari = 2;

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
      await MonitorizareService.instance.verificaToate();
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
