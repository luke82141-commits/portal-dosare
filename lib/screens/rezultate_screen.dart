import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/soap_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dosar_card.dart';
import '../widgets/elemente.dart';

/// Rezultatele unei căutări (Figma: „02 · Rezultate”, „06 · se încarcă”,
/// „07 · eroare & fără rezultate”).
class RezultateScreen extends StatefulWidget {
  final String numar;
  final String obiect;

  /// Se poate înlocui în teste.
  final SoapService? soap;

  const RezultateScreen({super.key, this.numar = '', this.obiect = '', this.soap});

  @override
  State<RezultateScreen> createState() => _RezultateScreenState();
}

class _RezultateScreenState extends State<RezultateScreen> {
  late final SoapService _soap = widget.soap ?? SoapService();

  List<Dosar> _dosare = [];
  bool _limitaAtinsa = false;
  bool _seIncarca = true;
  Object? _eroare;
  String? _filtru;

  @override
  void initState() {
    super.initState();
    _cauta();
  }

  Future<void> _cauta() async {
    setState(() {
      _seIncarca = true;
      _eroare = null;
    });
    try {
      final r = await _soap.cautaDosare(numarDosar: widget.numar, obiectDosar: widget.obiect);
      if (!mounted) return;
      setState(() {
        _dosare = r.dosare;
        _limitaAtinsa = r.limitaAtinsa;
        _filtru = null;
      });
    } catch (e) {
      if (mounted) setState(() => _eroare = e);
    } finally {
      if (mounted) setState(() => _seIncarca = false);
    }
  }

  String get _subtitlu => [
        if (widget.numar.isNotEmpty) 'Număr: ${widget.numar}',
        if (widget.obiect.isNotEmpty) 'Obiect: „${widget.obiect}”',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final stadii = <String>{
      for (final d in _dosare)
        if (d.stadiuProcesual.isNotEmpty) d.stadiuProcesual,
    }.toList();
    final afisate = _filtru == null
        ? _dosare
        : _dosare.where((d) => d.stadiuProcesual == _filtru).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rezultate'),
            if (_subtitlu.isNotEmpty)
              Text(
                _subtitlu,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        bottom: !_seIncarca && _eroare == null && stadii.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      Pastila(
                        'Toate',
                        activ: _filtru == null,
                        onTap: () => setState(() => _filtru = null),
                      ),
                      for (final s in stadii) ...[
                        const SizedBox(width: 8),
                        Pastila(s, activ: _filtru == s, onTap: () => setState(() => _filtru = s)),
                      ],
                    ],
                  ),
                ),
              )
            : null,
        shape: const Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      body: _continut(afisate),
    );
  }

  Widget _continut(List<Dosar> afisate) {
    const padding = EdgeInsets.fromLTRB(16, 16, 16, 24);

    if (_seIncarca) {
      return ListView(
        padding: padding,
        children: const [
          IncarcarePortal(),
          SizedBox(height: 12),
          CardSchelet(),
          SizedBox(height: 12),
          CardSchelet(),
          SizedBox(height: 12),
          CardSchelet(),
        ],
      );
    }

    if (_eroare != null) {
      return ListView(
        padding: padding,
        children: [
          StareMesaj(
            icon: Icons.cloud_off,
            fundal: AppColors.warningContainer,
            culoare: AppColors.warning,
            titlu: 'Portalul nu răspunde',
            text: 'Nu am putut obține datele de pe portal.just.ro. '
                'Dosarele monitorizate rămân disponibile.\n\n$_eroare',
            buton: 'Încearcă din nou',
            butonPrincipal: true,
            onButon: _cauta,
          ),
        ],
      );
    }

    if (_dosare.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          StareMesaj(
            icon: Icons.search_off,
            titlu: 'Niciun dosar găsit',
            text: 'Verifică numărul (ex. 14993/299/2026) sau încearcă doar după '
                'obiectul dosarului.',
            buton: 'Modifică căutarea',
            onButon: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _cauta,
      child: ListView.separated(
        padding: padding,
        itemCount: afisate.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) return _rezumat(afisate.length);
          final d = afisate[i - 1];
          return DosarCardWidget(key: ValueKey(d.cheie), dosar: d, cuBiblioteca: true);
        },
      ),
    );
  }

  Widget _rezumat(int afisate) {
    final numar = Text(
      afisate == 1 ? 'Un dosar găsit' : '$afisate dosare găsite',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant,
      ),
    );
    if (!_limitaAtinsa) return numar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.warningContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info, size: 20, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Afișate primele ${_dosare.length} dosare (limita portalului). '
                  'Restrânge căutarea pentru rezultate complete.',
                  style: const TextStyle(fontSize: 13, height: 1.38, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        numar,
      ],
    );
  }
}
