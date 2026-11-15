String _doua(int n) => n.toString().padLeft(2, '0');

/// 04.11.2026
String formateazaData(DateTime? d) =>
    d == null ? '' : '${_doua(d.day)}.${_doua(d.month)}.${d.year}';

/// 04.11.2026, 10:32
String formateazaDataOra(DateTime? d) =>
    d == null ? '' : '${formateazaData(d)}, ${_doua(d.hour)}:${_doua(d.minute)}';

String scurteaza(String s, [int max = 140]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}
