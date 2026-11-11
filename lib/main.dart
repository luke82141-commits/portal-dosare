import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/monitorizare_service.dart';
import 'theme/app_theme.dart';

void main() async {
  // Obligatoriu înainte de orice operație cu pluginuri.
  WidgetsFlutterBinding.ensureInitialized();

  // Notificările și verificarea periodică din fundal. O eroare aici nu
  // trebuie să împiedice pornirea aplicației.
  try {
    await MonitorizareService.instance.porneste();
  } catch (e) {
    debugPrint('Monitorizarea dosarelor nu a putut fi pornită: $e');
  }

  runApp(const LegalManagementApp());
}

class LegalManagementApp extends StatelessWidget {
  const LegalManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portal Dosare',
      theme: construiesteTema(),
      scrollBehavior: const FaraIntindere(),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Oprește efectul de „întindere” al Android 12+ când o listă e trasă peste
/// capăt (deforma textul). Listele se opresc pur și simplu la margine.
class FaraIntindere extends MaterialScrollBehavior {
  const FaraIntindere();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
