import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../services/pro_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';

/// „Widgeturi pe ecran”: cele trei mărimi, butoane de adăugare și, până la
/// abonament, eticheta Pro din perioada de lansare.
class WidgeturiScreen extends StatefulWidget {
  const WidgeturiScreen({super.key});

  @override
  State<WidgeturiScreen> createState() => _WidgeturiScreenState();
}

class _WidgeturiScreenState extends State<WidgeturiScreen> {
  static const _marimi = [
    (
      widgetMic,
      Icons.crop_square,
      'Mic (2 × 2)',
      'Următorul termen și numărul de actualizări noi.',
    ),
    (
      widgetMediu,
      Icons.crop_7_5,
      'Mediu (4 × 2)',
      'Următoarele trei termene, cu ziua, ora și instanța.',
    ),
    (
      widgetMare,
      Icons.crop_din,
      'Mare (4 × 4)',
      'Agenda pe 7 zile și ultimele actualizări din dosare.',
    ),
  ];

  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
  }

  Future<void> _adauga(String nume) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() ?? false) {
        await actualizeazaWidgeturi();
        await HomeWidget.requestPinWidget(qualifiedAndroidName: nume);
        return;
      }
    } catch (e) {
      debugPrint('Adăugarea widgetului a eșuat: $e');
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Ține apăsat pe ecranul principal, alege „Widgeturi” și caută Portal Dosare.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widgeturi pe ecran')),
      body: ListenableBuilder(
        listenable: ProService.instance,
        builder: (context, _) {
          final pro = ProService.instance.activ;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Vezi termenele și actualizările fără să deschizi aplicația. '
                  'Widgeturile se actualizează odată cu verificarea dosarelor, '
                  'cam o dată pe oră. Atingerea unui termen deschide dosarul.',
                ),
              ),
              if (!_android)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Deocamdată widgeturile sunt disponibile doar pe Android.',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              for (final (nume, icon, titlu, text) in _marimi)
                ListTile(
                  leading: Icon(icon, color: AppColors.primary),
                  title: Text(titlu),
                  subtitle: Text(text),
                  trailing: _android
                      ? TextButton(onPressed: () => _adauga(nume), child: const Text('Adaugă'))
                      : null,
                ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined, color: AppColors.accent),
                title: const Text(ProService.etichetaLansare),
                subtitle: Text(
                  pro
                      ? 'Widgeturile arată datele dosarelor. Mai târziu vor face parte din abonamentul Pro.'
                      : 'Widgeturile fac parte din Portal Dosare Pro. Fără abonament arată „Disponibil în Portal Dosare Pro”.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
