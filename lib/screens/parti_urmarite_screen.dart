import 'package:flutter/material.dart';

import '../services/parti_urmarite_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatare.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';

/// Părțile (persoane sau firme) urmărite și dosarele noi apărute pe numele
/// lor. Se adaugă din rezultatele unei căutări după numele părții.
class PartiUrmariteScreen extends StatefulWidget {
  const PartiUrmariteScreen({super.key});

  @override
  State<PartiUrmariteScreen> createState() => _PartiUrmariteScreenState();
}

class _PartiUrmariteScreenState extends State<PartiUrmariteScreen> {
  final _service = PartiUrmariteService.instance;

  @override
  void initState() {
    super.initState();
    _service.incarca();
  }

  /// Ce a fost văzut pe ecran nu mai apare ca necitit la următoarea deschidere.
  @override
  void dispose() {
    for (final p in _service.parti) {
      if (p.necitite > 0) _service.marcheazaCitite(p.cheie);
    }
    super.dispose();
  }

  Future<void> _confirmaStergere(ParteUrmarita p) async {
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nu mai urmări partea?'),
        content: Text('Nu vei mai fi anunțat de dosarele noi pe numele „${p.eticheta}”.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nu mai urmări'),
          ),
        ],
      ),
    );
    if (da == true) await _service.sterge(p.cheie);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Părți urmărite')),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final parti = _service.parti;
          if (parti.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: StareMesaj(
                icon: Icons.person_search,
                titlu: 'Nicio parte urmărită',
                text:
                    'Caută după numele unei părți și apasă „Urmărește partea” în rezultate. '
                    'Vei primi o notificare când apare un dosar nou pe numele ei.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final p in parti) ...[
                _AntetParte(parte: p, onSterge: () => _confirmaStergere(p)),
                const SizedBox(height: 8),
                if (p.dosareNoi.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Niciun dosar nou de la începutul urmăririi.',
                      style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                    ),
                  )
                else
                  for (final d in p.dosareNoi) ...[
                    _EtichetaNou(d),
                    DosarCardWidget(
                      key: ValueKey('${p.cheie}/${d.dosar.cheie}'),
                      dosar: d.dosar,
                      cuBiblioteca: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AntetParte extends StatelessWidget {
  final ParteUrmarita parte;
  final VoidCallback onSterge;

  const _AntetParte({required this.parte, required this.onSterge});

  @override
  Widget build(BuildContext context) {
    final verificare = parte.ultimaVerificare;
    return Row(
      children: [
        const Icon(Icons.person_outline, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parte.eticheta,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                'Urmărită din ${formateazaData(parte.adaugataLa)}'
                '${verificare == null ? '' : ' · verificată ${formateazaDataOra(verificare)}'}',
                style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Nu mai urmări',
          icon: const Icon(Icons.close),
          color: AppColors.onSurfaceVariant,
          onPressed: onSterge,
        ),
      ],
    );
  }
}

class _EtichetaNou extends StatelessWidget {
  final DosarNouParte d;
  const _EtichetaNou(this.d);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Text(
        '${d.citit ? 'Găsit' : 'Nou'} · ${formateazaDataOra(d.gasitLa)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: d.citit ? FontWeight.w400 : FontWeight.w600,
          color: d.citit ? AppColors.onSurfaceVariant : AppColors.success,
        ),
      ),
    );
  }
}
