import 'package:flutter/material.dart';

import '../models/dosar_model.dart';
import '../services/culori_service.dart';
import '../theme/app_theme.dart';

/// Foaia de jos din care se alege culoarea unui dosar.
Future<void> alegeCuloare(BuildContext context, Dosar dosar) {
  final service = CuloriDosareService.instance;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final aleasa = service.aleasa(dosar.cheie);
      final actuala = service.culoare(dosar);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Culoarea dosarului ${dosar.numar}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'O vezi în calendar și pe cardul dosarului.',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final (c, nume) in paletaDosare)
                    Tooltip(
                      message: nume,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          service.seteaza(dosar.cheie, c);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: c == actuala
                                ? Border.all(color: AppColors.onSurface, width: 3)
                                : null,
                          ),
                          child: c == actuala ? const Icon(Icons.check, color: Colors.white) : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: aleasa == null
                    ? null
                    : () {
                        service.seteaza(dosar.cheie, null);
                        Navigator.pop(ctx);
                      },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(aleasa == null ? 'Culoare automată (activă)' : 'Revino la culoarea automată'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Bulina de culoare a unui dosar; tap pe ea deschide alegerea culorii.
class BulinaCuloare extends StatelessWidget {
  final Dosar dosar;
  final double marime;

  const BulinaCuloare(this.dosar, {super.key, this.marime = 14});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CuloriDosareService.instance,
      builder: (context, _) => Tooltip(
        message: 'Schimbă culoarea',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => alegeCuloare(context, dosar),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              width: marime,
              height: marime,
              decoration: BoxDecoration(
                color: CuloriDosareService.instance.culoare(dosar),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
