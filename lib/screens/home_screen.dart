import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';
import 'biblioteca_screen.dart';
import 'cautare_screen.dart';

/// Cadrul aplicației: căutarea și biblioteca, cu bară de navigare jos.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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

  void _laNotificare() {
    final semnal = MonitorizareService.instance.deschideBiblioteca;
    if (!semnal.value) return;
    semnal.value = false;
    if (mounted) setState(() => _tab = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [CautareScreen(), BibliotecaScreen()],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final necitite = BibliotecaService.instance.totalNecitite;
          return NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.search),
                label: 'Căutare',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: necitite > 0,
                  label: Text('$necitite'),
                  child: const Icon(Icons.bookmarks_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: necitite > 0,
                  label: Text('$necitite'),
                  child: const Icon(Icons.bookmarks),
                ),
                label: 'Bibliotecă',
              ),
            ],
          );
        },
      ),
    );
  }
}
