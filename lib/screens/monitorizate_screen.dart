import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/biblioteca_service.dart';
import '../services/monitorizare_service.dart';
import '../services/parti_urmarite_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';
import 'dosare_filtrate_screen.dart';
import 'dosare_selectie_screen.dart';
import 'parti_urmarite_screen.dart';
import 'selecteaza_monitorizate_screen.dart';
import 'sincronizare_calendar_screen.dart';

/// Dosarele monitorizate (Figma: „04 · Dosare monitorizate”).
class MonitorizateScreen extends StatefulWidget {
  const MonitorizateScreen({super.key});

  @override
  State<MonitorizateScreen> createState() => _MonitorizateScreenState();
}

class _MonitorizateScreenState extends State<MonitorizateScreen> {
  bool _verifica = false;
  final _derulare = ScrollController();

  @override
  void dispose() {
    _derulare.dispose();
    super.dispose();
  }

  /// Numărul de dosare la care utilizatorul a închis avertizarea de plafon.
  /// Ea reapare doar dacă urmărește și mai multe dosare de atât.
  int? _plafonAscunsLa;
  static const _cheiePlafonAscuns = 'avertizare_plafon_ascunsa_la';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted)
        setState(() => _plafonAscunsLa = p.getInt(_cheiePlafonAscuns));
    });
  }

  Future<void> _ascundePlafon(int dosare) async {
    setState(() => _plafonAscunsLa = dosare);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_cheiePlafonAscuns, dosare);
  }

  bool _aratPlafon(int dosare) =>
      dosare > plafonDosare &&
      (_plafonAscunsLa == null || dosare > _plafonAscunsLa!);

  Future<void> _verificaAcum() async {
    if (_verifica) return;
    setState(() => _verifica = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final monitorizare = MonitorizareService.instance;
      final rezultate = await monitorizare.verificaToate();
      final noi = monitorizare.dosareNoiParti.fold(
        0,
        (s, r) => s + r.dosareNoi.length,
      );
      final mesaje = [
        if (rezultate.length == 1) 'Un dosar are modificări.',
        if (rezultate.length > 1) '${rezultate.length} dosare au modificări.',
        if (noi == 1) 'Un dosar nou pe numele părților urmărite.',
        if (noi > 1) '$noi dosare noi pe numele părților urmărite.',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mesaje.isEmpty ? 'Nicio modificare pe portal.' : mesaje.join(' '),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Verificarea a eșuat: $e')),
      );
    } finally {
      if (mounted) setState(() => _verifica = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: BibliotecaService.instance,
        builder: (context, _) {
          final biblioteca = BibliotecaService.instance;
          final dosare = biblioteca.dosare;
          final verificari = [
            for (final d in dosare)
              if (d.ultimaVerificare != null) d.ultimaVerificare!,
          ]..sort();
          final peSaptamana = dosareCuTermenInSaptamana(dosare).length;

          final sus = <Widget>[
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Pe ecrane înguste titlul se micșorează în loc să
                        // se rupă pe două rânduri lângă butoane.
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Monitorizate',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (dosare.isNotEmpty) ...[
                          _butonRotund(
                            tooltip: 'Sincronizare Google / iCloud Calendar',
                            icon: Icons.event_repeat,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SincronizareCalendarScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _butonRotund(
                            tooltip: 'Filtrează dosarele',
                            icon: Icons.tune,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DosareFiltrateScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        _butonParti(),
                        const SizedBox(width: 8),
                        _butonVerificare(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descriereProgramVerificare(dosare.length) +
                          '${verificari.isEmpty ? '' : ' · ultima: ${formateazaDataOra(verificari.last)}'}',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.38,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: dosare.isEmpty
                  ? const StareMesaj(
                      icon: Icons.bookmark_border,
                      titlu: 'Niciun dosar monitorizat',
                      text:
                          'Deschide un dosar și pornește „Monitorizează dosarul”. '
                          'Vei primi o notificare la fiecare schimbare apărută pe portal.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Sumar(
                                '${dosare.length}',
                                dosare.length == 1
                                    ? 'dosar urmărit'
                                    : 'dosare urmărite',
                              ),
                              const SizedBox(width: 10),
                              _Sumar(
                                '${biblioteca.totalNecitite}',
                                biblioteca.totalNecitite == 1
                                    ? 'actualizare nouă'
                                    : 'actualizări noi',
                                fundal: AppColors.successContainer,
                                culoare: AppColors.success,
                                onTap: () =>
                                    _deschide(SelectieDosare.actualizari),
                              ),
                              const SizedBox(width: 10),
                              _Sumar(
                                '$peSaptamana',
                                'termene în 7 zile',
                                fundal: AppColors.accentContainer,
                                culoare: AppColors.accent,
                                onTap: () => _deschide(SelectieDosare.termene),
                              ),
                            ],
                          ),
                        ),
                        if (_aratPlafon(dosare.length)) ...[
                          const SizedBox(height: 12),
                          AvertizarePlafon(
                            dosare: dosare.length,
                            onAlege: () => _selecteaza(),
                            onInchide: () => _ascundePlafon(dosare.length),
                          ),
                        ],
                        if (dosare.length > 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _selecteaza(),
                              icon: const Icon(Icons.checklist, size: 18),
                              label: const Text('Selectează mai multe'),
                            ),
                          )
                        else
                          const SizedBox(height: 12),
                      ],
                    ),
            ),
          ];

          // Cardurile se construiesc doar când apar pe ecran: cu sute de
          // dosare, o listă construită dintr-odată ar merge greu. Bara din
          // dreapta se trage cu degetul ca să ajungi repede sus sau jos.
          return RefreshIndicator(
            onRefresh: _verificaAcum,
            child: Scrollbar(
              controller: _derulare,
              interactive: true,
              thickness: 8,
              radius: const Radius.circular(4),
              child: ListView.builder(
                controller: _derulare,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: sus.length + dosare.length,
                itemBuilder: (context, i) {
                  if (i < sus.length) return sus[i];
                  final s = dosare[i - sus.length];
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      i == sus.length ? 0 : 12,
                      16,
                      0,
                    ),
                    child: DosarCardWidget(
                      key: ValueKey(s.dosar.cheie),
                      dosar: s.dosar,
                      salvat: s,
                      onLongPress: () => _selecteaza(s.dosar.cheie),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _selecteaza([String? cheie]) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SelecteazaMonitorizateScreen(cheieInitiala: cheie),
    ),
  );

  void _deschide(SelectieDosare selectie) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => DosareSelectieScreen(selectie: selectie)),
  );

  Widget _butonRotund({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 20,
          color: AppColors.primary,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }

  /// Deschide părțile urmărite; bulina arată câte dosare noi n-au fost văzute.
  Widget _butonParti() {
    return ListenableBuilder(
      listenable: PartiUrmariteService.instance,
      builder: (context, _) {
        final necitite = PartiUrmariteService.instance.totalNecitite;
        return Badge(
          isLabelVisible: necitite > 0,
          label: Text('$necitite'),
          backgroundColor: AppColors.success,
          child: _butonRotund(
            tooltip: 'Părți urmărite',
            icon: Icons.person_search,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PartiUrmariteScreen()),
            ),
          ),
        );
      },
    );
  }

  Widget _butonVerificare() {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: SizedBox(
        width: 40,
        height: 40,
        child: _verifica
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Verifică acum pe portal',
                padding: EdgeInsets.zero,
                iconSize: 20,
                color: AppColors.primary,
                onPressed: _verificaAcum,
                icon: const Icon(Icons.refresh),
              ),
      ),
    );
  }
}

class _Sumar extends StatelessWidget {
  final String valoare;
  final String eticheta;
  final Color? fundal;
  final Color culoare;
  final VoidCallback? onTap;

  const _Sumar(
    this.valoare,
    this.eticheta, {
    this.fundal,
    this.culoare = AppColors.onSurface,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: fundal ?? AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: fundal == null
                  ? Border.all(color: AppColors.outline)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valoare,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: culoare,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eticheta,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: fundal == null
                        ? AppColors.onSurfaceVariant
                        : culoare,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
