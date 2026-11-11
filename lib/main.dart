import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() async {
  // Obligatoriu pentru a inițializa canalele native înainte de orice operatie cu pluginuri
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const LegalManagementApp()); // sau numele clasei tale principale
}

class LegalManagementApp extends StatelessWidget {
  const LegalManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legal Management App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}