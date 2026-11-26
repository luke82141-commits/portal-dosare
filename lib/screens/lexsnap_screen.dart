import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../lexsnap/analiza_document.dart';
import '../lexsnap/fisier_service.dart';
import '../lexsnap/lexsnap_service.dart';
import '../lexsnap/ocr_service.dart';
import '../lexsnap/sugestii_aparare.dart';
import '../services/legislatie_service.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'act_normativ_screen.dart';

/// Alege o fotografie (cameră sau galerie) și întoarce calea ei.
typedef AlegeImagine = Future<String?> Function(ImageSource sursa);

Future<String?> _alegeCuImagePicker(ImageSource sursa) async =>
    (await ImagePicker().pickImage(source: sursa))?.path;

/// Alege un fișier (PDF sau imagine) și întoarce calea lui.
typedef AlegeFisier = Future<String?> Function();

Future<String?> _alegeCuFilePicker() async => (await FilePicker.pickFile(
  dialogTitle: 'Alege documentul',
  type: FileType.custom,
  allowedExtensions: extensiiFisiere,
))?.path;

/// LexSnap (Pro): fotografiezi o hârtie juridică, aplicația citește textul
/// pe telefon și caută în Legislație prevederile care o privesc.
class LexSnapScreen extends StatefulWidget {
  final OcrService? ocr;
  final LegislatieService? service;
  final AlegeImagine? alegeImagine;
  final AlegeFisier? alegeFisier;

  /// Citirea PDF-urilor (în teste, simulată).
  final DeschidePdf? deschidePdf;
  final FurnizorSugestii furnizorSugestii;

  const LexSnapScreen({
    super.key,
    this.ocr,
    this.service,
    this.alegeImagine,
    this.alegeFisier,
    this.deschidePdf,
    this.furnizorSugestii = const FurnizorNeconfigurat(),
  });

  @override
  State<LexSnapScreen> createState() => _LexSnapScreenState();
}

class _LexSnapScreenState extends State<LexSnapScreen> {
  final _text = TextEditingController();
  bool _citeste = false;
  bool _cauta = false;
  bool _arataText = false;
  String? _eroare;

  /// „Citesc pagina 2 din 5...” în timpul citirii unui PDF.
  String? _progres;

  /// De unde vine textul: „PDF, 3 pagini (1 scanată, citită cu OCR)”.
  String? _sursa;
  AnalizaDocument? _analiza;
  final _prevederi = <PrevedereGasita>[];
  StreamSubscription<PrevedereGasita>? _abonare;

  @override
  void initState() {
    super.initState();
    ProService.instance.incarca();
  }

  @override
  void dispose() {
    _abonare?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _fotografie(ImageSource sursa) async {
    setState(() => _eroare = null);
    String? cale;
    try {
      cale = await (widget.alegeImagine ?? _alegeCuImagePicker)(sursa);
    } catch (e) {
      if (mounted) {
        setState(
          () => _eroare = sursa == ImageSource.camera
              ? 'Nu am putut deschide camera. Verifică permisiunea din setări.'
              : 'Nu am putut deschide galeria.',
        );
      }
      return;
    }
    if (cale == null || !mounted) return;
    await _citesteFisier(cale);
  }

  Future<void> _fisier() async {
    setState(() => _eroare = null);
    String? cale;
    try {
      cale = await (widget.alegeFisier ?? _alegeCuFilePicker)();
    } catch (e) {
      if (mounted) setState(() => _eroare = 'Nu am putut deschide fișierul.');
      return;
    }
    if (cale == null || !mounted) return;
    final ext = cale.split('.').last.toLowerCase();
    if (!extensiiFisiere.contains(ext)) {
      setState(
        () => _eroare = 'Pot citi doar PDF și imagini (JPG, JPEG, PNG).',
      );
      return;
    }
    await _citesteFisier(cale);
  }

  Future<void> _citesteFisier(String cale) async {
    final pdf = estePdf(cale);
    setState(() {
      _citeste = true;
      _progres = null;
      _sursa = null;
      _analiza = null;
      _prevederi.clear();
    });
    try {
      final r =
          await CititorFisiere(
            ocr: widget.ocr,
            deschidePdf: widget.deschidePdf,
          ).citeste(
            cale,
            progres: (p, total) {
              if (mounted && total > 1) {
                setState(() => _progres = 'Citesc pagina $p din $total...');
              }
            },
          );
      if (!mounted) return;
      _text.text = r.text;
      setState(() {
        _citeste = false;
        _progres = null;
        if (pdf) {
          final pagini = r.pagini == 1 ? '1 pagină' : '${r.pagini} pagini';
          _sursa = [
            'PDF, $pagini',
            if (r.paginiOcr > 0)
              r.paginiOcr == r.pagini
                  ? 'scanat, citit cu OCR'
                  : '${r.paginiOcr} scanate, citite cu OCR',
            if (r.trunchiat) 'doar primele $maxPaginiPdf',
          ].join(' · ');
        }
      });
      if (r.text.trim().isEmpty) {
        setState(() {
          _eroare = pdf
              ? 'Nu am găsit text în PDF. Dacă e o poză slabă, încearcă o '
                    'fotografie mai clară sau scrie textul de mână.'
              : 'Nu am găsit text în imagine. Încearcă din nou, cu lumină bună '
                    'și hârtia dreaptă, sau scrie textul de mână.';
          _arataText = true;
        });
        return;
      }
      _analizeaza();
    } catch (e) {
      if (mounted) {
        setState(() {
          _citeste = false;
          _progres = null;
          _eroare = pdf
              ? 'Nu am putut deschide PDF-ul (poate e protejat cu parolă).'
              : 'Nu am putut citi textul din imagine.';
        });
      }
    }
  }

  void _analizeaza() {
    FocusScope.of(context).unfocus();
    _abonare?.cancel();
    final analiza = analizeazaDocument(_text.text);
    setState(() {
      _eroare = null;
      _analiza = analiza;
      _prevederi.clear();
      _cauta = analiza.acte.isNotEmpty;
    });
    if (analiza.acte.isEmpty) return;
    _abonare = cautaPrevederi(analiza, service: widget.service).listen(
      (p) {
        if (mounted) setState(() => _prevederi.add(p));
      },
      onDone: () {
        if (mounted) setState(() => _cauta = false);
      },
    );
  }

  void _deschide(ActNormativ act, [String? articol]) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActNormativScreen(
            act: act,
            articolInitial: articol,
            service: widget.service,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LexSnap')),
      body: ListenableBuilder(
        listenable: ProService.instance,
        builder: (context, _) {
          if (!ProService.instance.activ) return const _Blocat();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              const Text(
                'Fotografiază sau încarcă o hârtie primită (proces-verbal, somație, citație, '
                'hotărâre) și îți arătăm legile și articolele care o privesc.',
              ),
              const SizedBox(height: 4),
              const Text(
                'Textul e citit pe telefon. Spre legislatie.just.ro pleacă doar '
                'numerele legilor și câteva cuvinte cheie, nu documentul.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _citeste
                          ? null
                          : () => _fotografie(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Fotografiază'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _citeste
                          ? null
                          : () => _fotografie(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Din galerie'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _citeste ? null : _fisier,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Încarcă fișier (PDF, JPG, PNG)'),
              ),
              if (!_arataText && _analiza == null && !_citeste)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _arataText = true),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Sau scrie / lipește textul'),
                  ),
                ),
              if (_citeste) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                Center(child: Text(_progres ?? 'Citesc textul...')),
              ],
              if (_eroare != null) ...[
                const SizedBox(height: 16),
                Text(_eroare!, style: const TextStyle(color: AppColors.error)),
              ],
              if (_arataText || _analiza != null) ..._campText(),
              if (_analiza != null) ..._rezultate(_analiza!),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _campText() => [
    const SizedBox(height: 16),
    Row(
      children: [
        const Expanded(
          child: Text(
            'Textul documentului',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (_analiza != null)
          TextButton(
            onPressed: () => setState(() => _arataText = !_arataText),
            child: Text(_arataText ? 'Ascunde' : 'Vezi și corectează'),
          ),
      ],
    ),
    if (_sursa != null)
      Text(
        _sursa!,
        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
      ),
    if (_arataText) ...[
      TextField(
        key: const Key('lexsnap_text'),
        controller: _text,
        minLines: 4,
        maxLines: 12,
        decoration: const InputDecoration(
          hintText: 'Textul documentului...',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonalIcon(
          onPressed: _cauta ? null : _analizeaza,
          icon: const Icon(Icons.search),
          label: Text(_analiza == null ? 'Caută prevederi' : 'Caută din nou'),
        ),
      ),
    ],
  ];

  List<Widget> _rezultate(AnalizaDocument a) {
    final tip = a.tipDocument;
    return [
      if (tip != null) ...[
        const SizedBox(height: 8),
        Card(
          color: AppColors.primaryContainer,
          child: ListTile(
            leading: const Icon(
              Icons.description_outlined,
              color: AppColors.onPrimaryContainer,
            ),
            title: Text(tip.nume),
            subtitle: Text(tip.indicatie),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const Text(
        'Prevederi găsite',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      if (a.goala)
        const Text(
          'Nu am găsit în text trimiteri la lege sau termeni juridici '
          'cunoscuți. Verifică textul citit și corectează-l dacă e nevoie.',
        ),
      for (final p in _prevederi) _CardPrevedere(p, onDeschide: _deschide),
      if (_cauta)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Caut în Legislație '
                  '(${_prevederi.length + 1} din ${a.acte.length})...',
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),
      _CardSugestii(disponibil: widget.furnizorSugestii.disponibil),
    ];
  }
}

class _CardPrevedere extends StatelessWidget {
  final PrevedereGasita p;
  final void Function(ActNormativ act, [String? articol]) onDeschide;

  const _CardPrevedere(this.p, {required this.onDeschide});

  @override
  Widget build(BuildContext context) {
    final c = p.cautare;
    final motiv = switch (c.motiv) {
      MotivPrevedere.citatInDocument => 'Citat în document',
      MotivPrevedere.tipDocument => c.explicatie,
      MotivPrevedere.termenCheie => 'Termen din document',
    };
    if (!p.gasita) {
      return Card(
        child: ListTile(
          leading: const Icon(
            Icons.help_outline,
            color: AppColors.onSurfaceVariant,
          ),
          title: Text(c.eticheta),
          subtitle: Text(
            p.eroare != null
                ? 'Legislație nu a răspuns: ${p.eroare}'
                : 'Nu l-am găsit pe legislatie.just.ro',
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final act in p.acte)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: () => onDeschide(act),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      motiv,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.motiv == MotivPrevedere.termenCheie
                          ? act.denumireScurta
                          : c.eticheta,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titluCurat(act.titlu),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                    if (c.articole.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final art in c.articole)
                            ActionChip(
                              avatar: const Icon(
                                Icons.article_outlined,
                                size: 18,
                              ),
                              label: Text(art.eticheta),
                              onPressed: () => onDeschide(act, art.articol),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pasul 3, încă nepornit: locul sugestiilor de apărare.
class _CardSugestii extends StatelessWidget {
  final bool disponibil;
  const _CardSugestii({required this.disponibil});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.accentContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: AppColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sugestii de apărare',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              disponibil
                  ? 'Argumente bazate doar pe articolele de mai sus, fiecare cu '
                        'citatul exact din lege.'
                  : 'În curând: argumente bazate doar pe articolele de mai sus, '
                        'fiecare cu citatul exact din lege.',
            ),
            const SizedBox(height: 8),
            const Text(
              avertismentLexSnap,
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blocat extends StatelessWidget {
  const _Blocat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 48,
              color: AppColors.accent,
            ),
            SizedBox(height: 12),
            Text(
              'Disponibil în Portal Dosare Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Fotografiezi o hârtie și vezi legile și articolele care o privesc.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
