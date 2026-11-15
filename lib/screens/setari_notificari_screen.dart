import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/setari_notificari_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elemente.dart';

/// Orele de liniște și dosarele care anunță cu sunet oricând.
class SetariNotificariScreen extends StatefulWidget {
  const SetariNotificariScreen({super.key});

  @override
  State<SetariNotificariScreen> createState() => _SetariNotificariScreenState();
}

class _SetariNotificariScreenState extends State<SetariNotificariScreen> {
  final _setari = SetariNotificariService.instance;

  @override
  void initState() {
    super.initState();
    _setari.incarca();
  }

  String _ora(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _alegeOra({required bool inceput}) async {
    final ales = await showTimePicker(
      context: context,
      initialTime: inceput ? _setari.start : _setari.stop,
      helpText: inceput ? 'Liniște de la' : 'Liniște până la',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (ales == null) return;
    await _setari.seteazaLiniste(start: inceput ? ales : null, stop: inceput ? null : ales);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ore de liniște')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_setari, BibliotecaService.instance]),
        builder: (context, _) {
          final activ = _setari.linisteActiva;
          final dosare = BibliotecaService.instance.dosare;
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
            children: [
              SwitchListTile(
                title: const Text('Ore de liniște'),
                subtitle: const Text(
                  'Modificările apărute în acest interval ajung pe telefon fără sunet și fără '
                  'vibrație. Le găsești dimineață în Notificări.',
                ),
                value: activ,
                onChanged: (v) => _setari.seteazaLiniste(activ: v),
              ),
              ListTile(
                enabled: activ,
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('De la'),
                trailing: Text(_ora(_setari.start), style: const TextStyle(fontSize: 16)),
                onTap: () => _alegeOra(inceput: true),
              ),
              ListTile(
                enabled: activ,
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Până la'),
                trailing: Text(_ora(_setari.stop), style: const TextStyle(fontSize: 16)),
                onTap: () => _alegeOra(inceput: false),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: AntetSectiune('Sună oricând'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Dosarele importante anunță cu sunet și în orele de liniște.',
                  style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              ),
              if (dosare.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Nu ai încă dosare monitorizate.',
                    style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                )
              else
                for (final s in dosare)
                  SwitchListTile(
                    title: Text(s.dosar.numar),
                    subtitle: Text(
                      [s.dosar.instanta, s.dosar.obiect].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: _setari.important(s.dosar.cheie),
                    onChanged: activ ? (v) => _setari.seteazaImportant(s.dosar.cheie, v) : null,
                  ),
            ],
          );
        },
      ),
    );
  }
}
