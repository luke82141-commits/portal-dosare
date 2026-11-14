import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/dosar_model.dart';
import '../utils/formatare.dart';
import '../utils/termene.dart';
import 'biblioteca_service.dart';
import 'pro_service.dart';

/// Widgeturile de pe ecranul principal (Android): clasele native din
/// android/app/src/main/kotlin/.../Widgeturi.kt citesc cheile de mai jos.
const widgetMic = 'ro.legaltech.legal_management_app.WidgetMic';
const widgetMediu = 'ro.legaltech.legal_management_app.WidgetMediu';
const widgetMare = 'ro.legaltech.legal_management_app.WidgetMare';
const widgeturi = [widgetMic, widgetMediu, widgetMare];

/// Câte rânduri au layout-urile native.
const randuriUrmatoare = 3;
const randuriSaptamana = 6;
const randuriActualizari = 2;

const _zile = ['Lun', 'Mar', 'Mie', 'Joi', 'Vin', 'Sâm', 'Dum'];

/// „Azi”, „Mâine” sau „Vin 21.11”.
String ziScurta(DateTime zi, DateTime acum) {
  final a = DateTime(acum.year, acum.month, acum.day);
  final z = DateTime(zi.year, zi.month, zi.day);
  final dif = z.difference(a).inDays;
  if (dif == 0) return 'Azi';
  if (dif == 1) return 'Mâine';
  return '${_zile[z.weekday - 1]} ${z.day.toString().padLeft(2, '0')}.${z.month.toString().padLeft(2, '0')}';
}

DateTime _moment(Sedinta s) {
  final p = s.ora.split(':');
  return s.data!.add(
    Duration(
      hours: int.tryParse(p.first) ?? 0,
      minutes: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    ),
  );
}

/// Datele pentru cele trei widgeturi, ca perechi cheie–text. Funcție pură,
/// testată separat de partea nativă.
Map<String, String> dateWidgeturi(List<DosarSalvat> dosare, {required bool pro, DateTime? acum}) {
  final azi = acum ?? DateTime.now();
  final date = <String, String>{'pro': pro ? '1' : '0'};

  final termene = [
    for (final s in dosare)
      for (final t in s.dosar.sedinte)
        if (esteTermenViitor(t, acum: azi)) (s.dosar, t),
  ]..sort((a, b) => _moment(a.$2).compareTo(_moment(b.$2)));

  void rand(String p, int i, (Dosar, Sedinta)? t) {
    date['${p}${i}_zi'] = t == null ? '' : ziScurta(t.$2.data!, azi);
    date['${p}${i}_ora'] = t == null ? '' : t.$2.ora;
    date['${p}${i}_dosar'] = t?.$1.numar ?? '';
    date['${p}${i}_inst'] = t?.$1.instanta ?? '';
    date['${p}${i}_cheie'] = t?.$1.cheie ?? '';
  }

  for (var i = 0; i < randuriUrmatoare; i++) {
    rand('t', i, i < termene.length ? termene[i] : null);
  }
  final ziAzi = DateTime(azi.year, azi.month, azi.day);
  final saptamana = [
    for (final t in termene)
      if (t.$2.data!.difference(ziAzi).inDays < 7) t,
  ];
  date['s_n'] = '${saptamana.length}';
  for (var i = 0; i < randuriSaptamana; i++) {
    rand('s', i, i < saptamana.length ? saptamana[i] : null);
  }
  final ramase = saptamana.length - randuriSaptamana;
  date['s_mai_multe'] = ramase > 0 ? '+ încă $ramase ${ramase == 1 ? 'termen' : 'termene'}' : '';

  final necitite = dosare.fold(0, (n, s) => n + s.necitite);
  date['act_n'] = '$necitite';
  date['act_text'] = switch (necitite) {
    0 => '',
    1 => '1 actualizare nouă',
    _ => '$necitite actualizări noi',
  };
  // Cea mai recentă modificare din fiecare dosar cu actualizări necitite.
  final cuActualizari = [
    for (final s in dosare)
      if (s.necitite > 0 && s.modificari.isNotEmpty)
        (s, s.modificari.reduce((a, b) => b.detectataLa.isAfter(a.detectataLa) ? b : a)),
  ]..sort((a, b) => b.$2.detectataLa.compareTo(a.$2.detectataLa));
  for (var i = 0; i < randuriActualizari; i++) {
    final a = i < cuActualizari.length ? cuActualizari[i] : null;
    date['a${i}_text'] = a == null ? '' : scurteaza(a.$2.text, 90);
    date['a${i}_dosar'] = a?.$1.dosar.numar ?? '';
    date['a${i}_cheie'] = a?.$1.dosar.cheie ?? '';
  }

  final ora = '${azi.hour.toString().padLeft(2, '0')}:${azi.minute.toString().padLeft(2, '0')}';
  date['actualizat'] = 'Actualizat $ora';
  return date;
}

/// Trimite datele către widgeturi și le redesenează. Doar pe Android; o
/// eroare aici nu trebuie să strice verificarea.
Future<void> actualizeazaWidgeturi({DateTime? acum}) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await BibliotecaService.instance.incarca();
    await ProService.instance.incarca();
    final date = dateWidgeturi(
      BibliotecaService.instance.dosare,
      pro: ProService.instance.activ,
      acum: acum,
    );
    for (final e in date.entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
    for (final w in widgeturi) {
      await HomeWidget.updateWidget(qualifiedAndroidName: w);
    }
  } catch (e) {
    debugPrint('Widgeturile nu au putut fi actualizate: $e');
  }
}
