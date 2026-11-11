import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/soap_service.dart';
import '../widgets/dosar_card.dart';

class CautareScreen extends StatefulWidget {
  const CautareScreen({super.key});

  @override
  State<CautareScreen> createState() => _CautareScreenState();
}

class _CautareScreenState extends State<CautareScreen> {
  final TextEditingController _numarController = TextEditingController();
  final TextEditingController _obiectController = TextEditingController();
  final SoapService _soapService = SoapService();

  List<Dosar> _dosare = [];
  bool _isLoading = false;
  bool _limitaAtinsa = false;
  bool _cautareEfectuata = false;

  @override
  void dispose() {
    _numarController.dispose();
    _obiectController.dispose();
    super.dispose();
  }

  Future<void> _cautaDosare() async {
    final numar = _numarController.text.trim();
    final obiect = _obiectController.text.trim();
    if (numar.isEmpty && obiect.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introdu numărul dosarului sau obiectul.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final rezultat = await _soapService.cautaDosare(
        numarDosar: numar,
        obiectDosar: obiect,
      );
      if (!mounted) return;
      setState(() {
        _dosare = rezultat.dosare;
        _limitaAtinsa = rezultat.limitaAtinsa;
        _cautareEfectuata = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la căutare: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Căutare dosare'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _numarController,
              decoration: InputDecoration(
                labelText: 'Număr dosar',
                hintText: 'Ex: 12345/300/2023',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cautaDosare(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obiectController,
              decoration: InputDecoration(
                labelText: 'Obiectul dosarului',
                hintText: 'Ex: uzucapiune, pretenții, divorț',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cautaDosare(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isLoading ? null : _cautaDosare,
              icon: const Icon(Icons.search),
              label: const Text('Caută'),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_cautareEfectuata && _dosare.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _limitaAtinsa
                        ? 'Afișate primele ${_dosare.length} dosare (limita portalului). '
                            'Restrânge căutarea pentru rezultate complete.'
                        : _dosare.length == 1
                            ? 'Un dosar găsit'
                            : '${_dosare.length} dosare găsite',
                    style: TextStyle(
                      color: _limitaAtinsa ? Colors.orange[800] : Colors.grey[700],
                    ),
                  ),
                ),
              Expanded(
                child: _dosare.isEmpty
                    ? Center(
                        child: Text(
                          _cautareEfectuata
                              ? 'Niciun dosar găsit.'
                              : 'Caută după număr, după obiect sau după ambele.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _dosare.length,
                        itemBuilder: (context, index) => DosarCardWidget(
                          key: ValueKey(_dosare[index].cheie),
                          dosar: _dosare[index],
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
