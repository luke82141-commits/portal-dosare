import 'package:flutter/material.dart';

import '../services/biblioteca_service.dart';
import '../services/pro_service.dart';
import '../services/rezumat_service.dart';
import '../services/termene_procedurale_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import 'calculator_termene_screen.dart' show dataCuZi;
import 'dosar_detaliu_screen.dart';

/// „Rezumatul zilnic” (Pro): ce e azi și în următoarea zi lucrătoare, ce s-a
/// schimbat și ce termene procedurale expiră, plus setările notificării.
class RezumatZilnicScreen extends StatefulWidget {
  /// Momentul pentru care se arată rezumatul (în teste).
  final DateTime? acum;

  const RezumatZilnicScreen({super.key, this.acum});

  @override
  State<RezumatZilnicScreen> createState() => _RezumatZilnicScreenState();
}

class _RezumatZilnicScreenState extends State<RezumatZilnicScreen> {
  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
    RezumatService.instance.incarca();
    TermeneProceduraleService.instance.incarca();
  }

  Future<void> _alegeOra() async {
    final s = RezumatService.instance;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.ora, minute: s.minut),
      helpText: 'Ora rezumatului',
    );
    if (t == null) return;
    s
      ..ora = t.hour
      ..minut = t.minute;
    await s.salveaza();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezumatul zilnic')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          ProService.instance,
          RezumatService.instance,
          BibliotecaService.instance,
          TermeneProceduraleService.instance,
        ]),
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          final setari = RezumatService.instance;
          final acum = widget.acum ?? DateTime.now();
          final r = construiesteRezumat(
            BibliotecaService.instance.dosare,
            TermeneProceduraleService.instance.termene,
            acum: acum,
          );
          final ziUrm = numeZiUrmatoare(r);
          String doua(int n) => n.toString().padLeft(2, '0');

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notificare în fiecare dimineață'),
                subtitle: const Text(
                  'Doar în zilele lucrătoare și doar dacă ai ceva în ziua aceea',
                ),
                value: setari.activ,
                onChanged: (v) {
                  setari.activ = v;
                  setari.salveaza();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: setari.activ,
                title: const Text('Ora'),
                subtitle: const Text('Vine odată cu prima verificare de după această oră'),
                trailing: Text(
                  '${doua(setari.ora)}:${doua(setari.minut)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                onTap: _alegeOra,
              ),
              const Divider(height: 24),
              Text(
                'Azi, ${dataCuZi(r.zi)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (r.gol)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nimic de raportat: niciun termen azi sau în următoarea zi lucrătoare, nicio '
                    'actualizare nouă și niciun termen procedural care să expire.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              if (r.azi.isNotEmpty) ...[
                const _Titlu('Termenele de azi'),
                for (final t in r.azi) _Termen(t),
              ],
              if (r.urmatoare.isNotEmpty) ...[
                _Titlu('$ziUrm, ${formateazaData(r.ziUrmatoare)}'),
                for (final t in r.urmatoare) _Termen(t),
              ],
              if (r.procedurale.isNotEmpty) ...[
                const _Titlu('Termene procedurale care expiră'),
                for (final t in r.procedurale)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined, color: AppColors.error),
                    title: Text(t.act),
                    subtitle: Text(
                      [
                        'Ultima zi: ${dataCuZi(t.ultimaZi)}',
                        if (t.numarDosar.isNotEmpty) 'dosar ${t.numarDosar}',
                      ].join(' · '),
                    ),
                  ),
              ],
              if (r.actualizari.isNotEmpty) ...[
                const _Titlu('Actualizări din ultimele 24 de ore'),
                for (final a in r.actualizari)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fiber_new_outlined, color: AppColors.success),
                    title: Text('${a.dosar.numar} · ${a.dosar.instanta}'),
                    subtitle: Text(a.modificare.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: a.dosar))),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Titlu extends StatelessWidget {
  final String text;
  const _Titlu(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurfaceVariant,
      ),
    ),
  );
}

class _Termen extends StatelessWidget {
  final TermenZi t;
  const _Termen(this.t);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 48,
        child: Text(
          t.sedinta.ora.isEmpty ? '—' : t.sedinta.ora,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
        ),
      ),
      title: Text(t.dosar.numar),
      subtitle: Text(
        [
          t.dosar.instanta,
          if (t.sedinta.complet.isNotEmpty) 'complet ${t.sedinta.complet}',
          if (t.dosar.obiect.isNotEmpty) t.dosar.obiect,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => DosarDetaliuScreen(dosar: t.dosar))),
    );
  }
}

class _Blocat extends StatelessWidget {
  const _Blocat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium_outlined, size: 48, color: AppColors.accent),
            const SizedBox(height: 12),
            const Text(
              'Disponibil în Portal Dosare Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'În fiecare dimineață, termenele zilei și ce s-a schimbat în dosare.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => ProService.instance.seteaza(true),
              child: const Text('Activează Pro (test)'),
            ),
          ],
        ),
      ),
    );
  }
}
