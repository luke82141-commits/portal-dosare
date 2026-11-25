import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/legislatie_service.dart' show etichetaTip, tipuriActe;
import '../services/monitor_oficial_service.dart';
import '../services/pro_service.dart';
import '../services/sursa_legislatie_mo.dart';
import '../theme/app_theme.dart';

/// „Monitorul Oficial” (Pro): domeniile de interes, alertele, raportul de
/// dimineață și actele apărute într-o zi, pe domeniile alese sau toate.
class MonitorOficialScreen extends StatefulWidget {
  /// Momentul de referință (în teste).
  final DateTime? acum;

  const MonitorOficialScreen({super.key, this.acum});

  @override
  State<MonitorOficialScreen> createState() => _MonitorOficialScreenState();
}

class _MonitorOficialScreenState extends State<MonitorOficialScreen> {
  final _mo = MonitorOficialService.instance;
  late DateTime _zi;
  bool _toate = false;
  bool _seIncarca = false;
  String? _eroare;

  DateTime get _acum => widget.acum ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final a = _acum;
    _zi = DateTime(a.year, a.month, a.day - 1);
    ProService.instance.incarca();
    _mo.sursa ??= SursaLegislatieMO();
    _mo.incarca().then((_) => _aduce());
  }

  Future<void> _aduce({bool fortat = false}) async {
    setState(() {
      _seIncarca = true;
      _eroare = null;
    });
    try {
      await _mo.aduce(_zi, acum: _acum, fortat: fortat);
    } catch (e) {
      _eroare = e is MonitorOficialException
          ? e.mesaj
          : 'Nu am putut afla ce a apărut în Monitorul Oficial. Reîncearcă.';
    }
    if (mounted) setState(() => _seIncarca = false);
  }

  void _schimbaZiua(int delta) {
    final azi = DateTime(_acum.year, _acum.month, _acum.day);
    final z = DateTime(_zi.year, _zi.month, _zi.day + delta);
    if (z.isAfter(azi) || azi.difference(z).inDays > 13) return;
    _zi = z;
    _aduce();
  }

  Future<void> _alegeOra() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _mo.ora, minute: _mo.minut),
      helpText: 'Ora raportului',
    );
    if (t == null) return;
    _mo
      ..ora = t.hour
      ..minut = t.minute;
    await _mo.salveaza();
  }

  Future<void> _editeaza([DomeniuInteres? d]) async {
    final rezultat = await Navigator.of(context).push<DomeniuInteres>(
      MaterialPageRoute(builder: (_) => DomeniuPropriuScreen(domeniu: d, acum: _acum)),
    );
    if (rezultat != null) await _mo.salveazaPropriu(rezultat);
  }

  String _numeZi(DateTime z) {
    final azi = DateTime(_acum.year, _acum.month, _acum.day);
    final d = azi.difference(z).inDays;
    final data = dataLunga(z);
    return d == 0 ? 'Azi, $data' : d == 1 ? 'Ieri, $data' : data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monitorul Oficial')),
      body: ListenableBuilder(
        listenable: Listenable.merge([ProService.instance, _mo]),
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          final domenii = _mo.domeniiActive;
          final acte = _mo.acteDin(_zi);
          final gasite = acte == null ? const <ActGasit>[] : potriveste(acte, domenii);
          String doua(int n) => n.toString().padLeft(2, '0');

          return RefreshIndicator(
            onRefresh: () => _aduce(fortat: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                // --- Ziua
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Ziua dinainte',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _schimbaZiua(-1),
                    ),
                    Expanded(
                      child: Text(
                        _numeZi(_zi),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Ziua următoare',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _schimbaZiua(1),
                    ),
                  ],
                ),
                Center(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Pe domeniile mele')),
                      ButtonSegment(value: true, label: Text('Toate actele')),
                    ],
                    selected: {_toate},
                    onSelectionChanged: (s) => setState(() => _toate = s.first),
                  ),
                ),
                const SizedBox(height: 8),
                if (_seIncarca)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_eroare != null)
                  _Mesaj(_eroare!, actiune: ('Reîncearcă', () => _aduce(fortat: true)))
                else if (acte == null)
                  const _Mesaj('Încă nu știm ce a apărut în ziua aceasta.')
                else if (acte.isEmpty)
                  const _Mesaj('Niciun act găsit în Monitorul Oficial, Partea I, în ziua aceasta.')
                else if (_toate)
                  for (final a in acte) _Act(act: a)
                else if (domenii.isEmpty)
                  _Mesaj(
                    'Au apărut ${acte.length} acte. Alege mai jos domeniile care te '
                    'interesează și îți arătăm doar ce contează pentru tine.',
                  )
                else if (gasite.isEmpty)
                  _Mesaj('Nimic pe domeniile tale. În total au apărut ${acte.length} acte.')
                else
                  for (final g in gasite) _Act(act: g.act, domenii: g.domenii, motiv: g.motiv),

                // --- Domenii
                const _Titlu('Domeniile mele'),
                for (final d in _mo.proprii)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune, color: AppColors.primary),
                    title: Text(d.nume),
                    subtitle: Text(descriereDomeniu(d), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: 'Șterge',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _mo.stergePropriu(d.id),
                    ),
                    onTap: () => _editeaza(d),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Definește un domeniu propriu'),
                    onPressed: () => _editeaza(),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sau alege din listă:',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
                for (final d in domeniiPredefinite)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(d.nume),
                    value: _mo.predefiniteAlese.contains(d.id),
                    onChanged: (v) => _mo.comutaPredefinit(d.id, v ?? false),
                  ),

                // --- Setări
                const _Titlu('Notificări'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alertă când apare un act'),
                  subtitle: const Text('Verificăm Monitorul la câteva ore, între 7 și 23'),
                  value: _mo.alerteImediate,
                  onChanged: (v) {
                    _mo.alerteImediate = v;
                    _mo.salveaza();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Raport în fiecare dimineață'),
                  subtitle: const Text('Ce a apărut ieri pe domeniile tale (lunea, și weekendul)'),
                  value: _mo.raportActiv,
                  onChanged: (v) {
                    _mo.raportActiv = v;
                    _mo.salveaza();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: _mo.raportActiv,
                  title: const Text('Ora raportului'),
                  subtitle: const Text('Vine odată cu prima verificare de după această oră'),
                  trailing: Text(
                    '${doua(_mo.ora)}:${doua(_mo.minut)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  onTap: _alegeOra,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Și când nu a apărut nimic'),
                  subtitle: const Text('Ca să știi că s-a verificat'),
                  value: _mo.raportSiCandEGol,
                  onChanged: _mo.raportActiv
                      ? (v) {
                          _mo.raportSiCandEGol = v;
                          _mo.salveaza();
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  'Sursa: ${_mo.sursa?.nume ?? '-'}. Partea I a Monitorului Oficial.',
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// „cuvinte: impozit, TVA · emitent: ANAF · doar Ordin”.
String descriereDomeniu(DomeniuInteres d) => [
  if (d.cuvinte.isNotEmpty) 'cuvinte: ${d.cuvinte.join(', ')}',
  if (d.emitenti.isNotEmpty) 'emitent: ${d.emitenti.join(', ')}',
  if (d.tipuri.isNotEmpty) 'doar ${d.tipuri.map(etichetaTip).join(', ')}',
  if (d.excluse.isNotEmpty) 'fără: ${d.excluse.join(', ')}',
].join(' · ');

class _Act extends StatelessWidget {
  final ActPublicat act;
  final List<String> domenii;
  final String? motiv;

  const _Act({required this.act, this.domenii = const [], this.motiv});

  Future<void> _deschide(BuildContext context) async {
    final uri = Uri.tryParse(act.link);
    if (uri == null || act.link.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    var reusit = false;
    try {
      reusit = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
    if (!reusit) {
      messenger.showSnackBar(const SnackBar(content: Text('Actul nu a putut fi deschis.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: act.link.isEmpty ? null : () => _deschide(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(act.denumire, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(act.titlu),
              const SizedBox(height: 4),
              Text(
                [
                  if (act.emitent.isNotEmpty) act.emitent,
                  if (act.monitor.isNotEmpty) 'MO nr. ${act.monitor}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
              if (domenii.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final d in domenii)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          d,
                          style: const TextStyle(fontSize: 12, color: AppColors.onPrimaryContainer),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Editorul unui domeniu propriu: nume, cuvinte cheie, emitenți, tipuri de
/// act și cuvinte excluse, cu actele pe care le-ar fi prins în zilele știute.
class DomeniuPropriuScreen extends StatefulWidget {
  final DomeniuInteres? domeniu;
  final DateTime? acum;

  const DomeniuPropriuScreen({super.key, this.domeniu, this.acum});

  @override
  State<DomeniuPropriuScreen> createState() => _DomeniuPropriuScreenState();
}

class _DomeniuPropriuScreenState extends State<DomeniuPropriuScreen> {
  late final _nume = TextEditingController(text: widget.domeniu?.nume ?? '');
  late final _cuvinte = TextEditingController(text: widget.domeniu?.cuvinte.join(', ') ?? '');
  late final _emitenti = TextEditingController(text: widget.domeniu?.emitenti.join(', ') ?? '');
  late final _excluse = TextEditingController(text: widget.domeniu?.excluse.join(', ') ?? '');
  late Set<String> _tipuri = {...?widget.domeniu?.tipuri};
  late bool _oricare = widget.domeniu?.combinare == Combinare.oricare;

  @override
  void dispose() {
    for (final c in [_nume, _cuvinte, _emitenti, _excluse]) {
      c.dispose();
    }
    super.dispose();
  }

  DomeniuInteres get _domeniu => DomeniuInteres(
    id: widget.domeniu?.id ?? 'propriu_${DateTime.now().microsecondsSinceEpoch}',
    nume: _nume.text.trim().isEmpty ? 'Domeniul meu' : _nume.text.trim(),
    cuvinte: cuvinteDinText(_cuvinte.text),
    emitenti: cuvinteDinText(_emitenti.text),
    tipuri: _tipuri,
    excluse: cuvinteDinText(_excluse.text),
    combinare: _oricare ? Combinare.oricare : Combinare.toate,
  );

  @override
  Widget build(BuildContext context) {
    final d = _domeniu;
    final acum = widget.acum ?? DateTime.now();
    final mo = MonitorOficialService.instance;
    final stiute = [
      for (var i = 0; i < 14; i++) ...?mo.acteDin(DateTime(acum.year, acum.month, acum.day - i)),
    ];
    final prinse = d.gol ? const <ActGasit>[] : potriveste(stiute, [d]);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.domeniu == null ? 'Domeniu nou' : 'Editează domeniul'),
        actions: [
          TextButton(
            onPressed: d.gol ? null : () => Navigator.of(context).pop(d),
            child: const Text('Salvează'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _nume,
            decoration: const InputDecoration(labelText: 'Nume', hintText: 'ex. Executare silită'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cuvinte,
            decoration: const InputDecoration(
              labelText: 'Cuvinte din titlu',
              hintText: 'ex. executare silită, poprire, executor',
              helperText: 'Separate prin virgulă. „poprir” prinde și „poprirea”, „popririi”.',
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emitenti,
            decoration: const InputDecoration(
              labelText: 'Emitent (opțional)',
              hintText: 'ex. Ministerul Justiției, ANAF',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (d.cuvinte.isNotEmpty && d.emitenti.isNotEmpty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ajunge una dintre ele'),
              subtitle: Text(
                _oricare
                    ? 'Un cuvânt din titlu SAU un emitent din listă'
                    : 'Un cuvânt din titlu ȘI un emitent din listă',
              ),
              value: _oricare,
              onChanged: (v) => setState(() => _oricare = v),
            ),
          const SizedBox(height: 12),
          const Text('Doar aceste tipuri de acte (niciunul bifat = toate):'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tipuriActe.where((t) => t != 'COD' && t != 'CONSTITUTIE'))
                FilterChip(
                  label: Text(etichetaTip(t)),
                  selected: _tipuri.contains(t),
                  onSelected: (v) => setState(() {
                    _tipuri = {..._tipuri};
                    v ? _tipuri.add(t) : _tipuri.remove(t);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _excluse,
            decoration: const InputDecoration(
              labelText: 'Fără aceste cuvinte (opțional)',
              hintText: 'ex. rectificare',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const _Titlu('Ce ar fi prins în ultimele zile'),
          if (d.gol)
            const _Mesaj('Scrie cel puțin un cuvânt, un emitent sau alege un tip de act.')
          else if (stiute.isEmpty)
            const _Mesaj('Încă nu avem acte din zilele trecute pentru o probă.')
          else if (prinse.isEmpty)
            _Mesaj('Niciunul dintre cele ${stiute.length} acte din zilele știute.')
          else
            for (final g in prinse.take(20)) _Act(act: g.act),
        ],
      ),
    );
  }
}

class _Titlu extends StatelessWidget {
  final String text;
  const _Titlu(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 4),
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

class _Mesaj extends StatelessWidget {
  final String text;
  final (String, VoidCallback)? actiune;
  const _Mesaj(this.text, {this.actiune});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        if (actiune != null)
          TextButton(onPressed: actiune!.$2, child: Text(actiune!.$1)),
      ],
    ),
  );
}

class _Blocat extends StatelessWidget {
  const _Blocat();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_outlined, size: 48, color: AppColors.accent),
          SizedBox(height: 12),
          Text(
            'Disponibil în Portal Dosare Pro',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Alerte din Monitorul Oficial pe domeniile tale și raportul de dimineață.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
