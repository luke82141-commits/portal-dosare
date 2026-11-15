import 'package:flutter/material.dart' show DateUtils;

import '../models/dosar_model.dart';
import 'formatare.dart';

const _luni = ['IAN', 'FEB', 'MAR', 'APR', 'MAI', 'IUN', 'IUL', 'AUG', 'SEP', 'OCT', 'NOI', 'DEC'];

/// „NOI 2026”, pentru caseta de dată a unei ședințe.
String lunaScurta(DateTime d) => '${_luni[d.month - 1]} ${d.year}';

/// True dacă ședința e azi sau mai târziu și nu are încă soluție.
bool esteTermenViitor(Sedinta s, {DateTime? acum}) {
  final azi = DateUtils.dateOnly(acum ?? DateTime.now());
  return !s.arePronuntare && s.data != null && !s.data!.isBefore(azi);
}

/// Cel mai apropiat termen viitor al dosarului, dacă există.
Sedinta? urmatorulTermen(Dosar d, {DateTime? acum}) {
  final viitoare = d.sedinte.where((s) => esteTermenViitor(s, acum: acum)).toList()
    ..sort((a, b) => a.data!.compareTo(b.data!));
  return viitoare.firstOrNull;
}

/// Cea mai recentă ședință cu soluție publicată.
Sedinta? ultimaPronuntare(Dosar d) => d.sedinteSortate.where((s) => s.arePronuntare).firstOrNull;

/// Rândul de jos al cardului: următorul termen sau, dacă nu există, ultima
/// soluție.
String rezumatTermen(Dosar d, {DateTime? acum}) {
  final t = urmatorulTermen(d, acum: acum);
  if (t != null) {
    return 'Următorul termen: ${formateazaData(t.data)}${t.ora.isEmpty ? '' : ', ${t.ora}'}';
  }
  final p = ultimaPronuntare(d);
  if (p != null) {
    final text = p.solutie.isNotEmpty ? p.solutie : p.solutieSumar;
    return 'Ultima soluție: ${scurteaza(text, 60)}';
  }
  if (d.data != null) return 'Înregistrat: ${formateazaData(d.data)}';
  return 'Fără ședințe publicate';
}

/// Inițialele unei părți, pentru avatar: „Nistor Marian” → „NM”.
String initiale(String nume) {
  final cuvinte = nume
      .split(RegExp(r'[\s\-]+'))
      .where((c) => c.isNotEmpty && RegExp(r'[A-Za-zĂÂÎȘȚăâîșț]').hasMatch(c[0]))
      .toList();
  if (cuvinte.isEmpty) return '?';
  final litere = cuvinte.take(2).map((c) => c[0].toUpperCase()).join();
  return litere;
}
