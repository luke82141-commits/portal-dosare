import 'package:flutter_test/flutter_test.dart';
import 'package:legal_management_app/models/dosar_model.dart';
import 'package:legal_management_app/services/widget_service.dart';

Dosar _d(String numar, {List<(DateTime, String)> termene = const []}) => Dosar(
  numar: numar,
  data: DateTime(2026, 1, 1),
  institutie: 'TribunalulPRAHOVA',
  obiect: 'pretenții',
  stadiuProcesual: 'Fond',
  sectie: '',
  categorie: 'Civil',
  parti: const [],
  sedinte: [
    for (final (zi, ora) in termene)
      Sedinta(complet: 'C1', data: zi, ora: ora, solutie: '', solutieSumar: ''),
  ],
);

DosarSalvat _s(Dosar d, {List<(DateTime, String)> modificari = const []}) =>
    DosarSalvat(
      dosar: d,
      adaugatLa: DateTime(2026, 1, 1),
      modificari: [
        for (final (la, text) in modificari)
          Modificare(detectataLa: la, text: text),
      ],
      necitite: modificari.length,
    );

void main() {
  // Sâmbătă, 14.11.2026, ora 15.
  final acum = DateTime(2026, 11, 14, 15);

  test('Ziua scurtă: Azi, Mâine, apoi ziua săptămânii și data', () {
    expect(ziScurta(DateTime(2026, 11, 14), acum), 'Azi');
    expect(ziScurta(DateTime(2026, 11, 15), acum), 'Mâine');
    expect(ziScurta(DateTime(2026, 11, 20), acum), 'Vin 20.11');
  });

  test('Termenele viitoare în ordine, agenda doar pe 7 zile', () {
    final date = dateWidgeturi(
      [
        _s(_d('1/1/2026', termene: [(DateTime(2026, 11, 25), '09:00')])),
        _s(_d('2/1/2026', termene: [(DateTime(2026, 11, 16), '11:00')])),
        _s(_d('3/1/2026', termene: [(DateTime(2026, 11, 16), '08:30')])),
        _s(_d('4/1/2026', termene: [(DateTime(2026, 11, 2), '09:00')])),
      ],
      pro: true,
      acum: acum,
    );

    expect(date['pro'], '1');
    expect(
      [date['t0_dosar'], date['t1_dosar'], date['t2_dosar']],
      ['3/1/2026', '2/1/2026', '1/1/2026'],
    );
    expect(date['t0_zi'], 'Lun 16.11');
    expect(date['t0_ora'], '08:30');
    expect(date['t0_cheie'], '3/1/2026|TribunalulPRAHOVA');
    expect(date['s_n'], '2');
    expect(date['s2_dosar'], '');
  });

  test(
    'Lista săptămânii are toate termenele; widgetul mic spune câte mai sunt',
    () {
      final date = dateWidgeturi(
        [
          for (var i = 0; i < 8; i++)
            _s(_d('$i/1/2026', termene: [(DateTime(2026, 11, 16), '09:0$i')])),
        ],
        pro: true,
        acum: acum,
      );
      expect(date['s_n'], '8');
      expect(date['s7_dosar'], isNotEmpty);
      expect(date['s8_dosar'], isEmpty);
      expect(date['t_n'], '8');
      expect(date['mic_mai'], '+ încă 7 termene în 7 zile');
    },
  );

  test('Actualizările: total și cea mai recentă modificare întâi', () {
    final date = dateWidgeturi(
      [
        _s(
          _d('1/1/2026'),
          modificari: [(DateTime(2026, 11, 10), 'Termen nou')],
        ),
        _s(_d('2/1/2026')),
        _s(
          _d('3/1/2026'),
          modificari: [
            (DateTime(2026, 11, 1), 'Vechi'),
            (DateTime(2026, 11, 14), 'Soluție'),
          ],
        ),
      ],
      pro: false,
      acum: acum,
    );
    expect(date['pro'], '0');
    expect(date['act_n'], '3');
    expect(date['act_text'], '3 actualizări noi');
    expect([date['a0_dosar'], date['a0_text']], ['3/1/2026', 'Soluție']);
    expect([date['a1_dosar'], date['a1_text']], ['1/1/2026', 'Termen nou']);
    expect(date['actualizat'], 'Actualizat 15:00');
  });

  test('Fără dosare, rândurile rămân goale', () {
    final date = dateWidgeturi([], pro: true, acum: acum);
    expect(date['t0_dosar'], '');
    expect(date['s_n'], '0');
    expect(date['act_text'], '');
  });
}
