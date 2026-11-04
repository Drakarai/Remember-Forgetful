import '../models/recurrence.dart';
import 'dates.dart';

/// Resultado de leer una frase como "dentista mañana a las 5".
class QuickParse {
  /// El texto sin las partes de fecha/hora/repetición reconocidas.
  final String title;
  final DateTime? date;
  final int? hour;
  final int? minute;
  final Recurrence? recurrence;

  const QuickParse({required this.title, this.date, this.hour, this.minute, this.recurrence});

  bool get found => date != null || hour != null || recurrence != null;
}

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _weekdays = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];
const _numbers = {
  'un': 1, 'una': 1, 'uno': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5,
  'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10, 'once': 11, 'doce': 12,
  'quince': 15, 'veinte': 20, 'treinta': 30,
};

/// Quita tildes sin cambiar la longitud (para poder recortar el original).
String _plain(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

int? _toInt(String? s) => s == null ? null : (int.tryParse(s) ?? _numbers[s]);

int _weekday(String name) {
  final n = name.endsWith('s') && !name.endsWith('lunes') && !name.endsWith('martes') &&
          !name.endsWith('miercoles') && !name.endsWith('jueves') && !name.endsWith('viernes')
      ? name.substring(0, name.length - 1)
      : name;
  return _weekdays.indexOf(n) + 1;
}

const _wd = r'(lunes|martes|miercoles|jueves|viernes|sabados?|domingos?)';
const _num = r'(\d+|un|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|quince|veinte|treinta)';

/// Lee fecha, hora y repetición de un texto en español. Lo que no entiende
/// lo deja en el título.
QuickParse parseQuick(String input, DateTime now) {
  var text = input;
  var plain = _plain(input);
  final today = dateOnly(now);

  DateTime? date;
  int? hour, minute;
  Recurrence? recurrence;

  /// Busca [pattern]; si coincide, llama a [onMatch] y borra el trozo.
  bool take(String pattern, void Function(RegExpMatch m) onMatch) {
    final m = RegExp(pattern).firstMatch(plain);
    if (m == null) return false;
    onMatch(m);
    final blank = ' ' * (m.end - m.start);
    text = text.replaceRange(m.start, m.end, blank);
    plain = plain.replaceRange(m.start, m.end, blank);
    return true;
  }

  // --- Hora ------------------------------------------------------------------
  void setTime(int h, int min, String? extra, String? period, {bool guessAfternoon = true}) {
    if (extra == 'y media') min = 30;
    if (extra == 'y cuarto') min = 15;
    if (extra == 'menos cuarto') {
      h = h - 1;
      min = 45;
    }
    if (period != null) {
      if ((period.contains('tarde') || period == 'pm') && h < 12) h += 12;
      if (period.contains('noche') && h >= 6 && h < 12) h += 12;
      if ((period.contains('manana') || period.contains('madrugada') || period == 'am') && h == 12) h = 0;
    } else if (guessAfternoon && h >= 1 && h <= 7) {
      // "a las 5" casi siempre es por la tarde.
      h += 12;
    }
    if (h < 0) h += 24;
    if (h > 23 || min > 59) return;
    hour = h;
    minute = min;
  }

  const period = r'(?:\s+(de la manana|de la tarde|de la noche|de la madrugada|am|pm))?';
  const extra = r'(?:\s+(y media|y cuarto|menos cuarto))?';
  take(r'\b(?:a las|a la|sobre las|hacia las|para las)\s+(\d{1,2})(?:[:.h](\d{2}))?(?:\s*(?:h|horas)\b)?' + extra + period + r'\b',
      (m) => setTime(int.parse(m[1]!), int.tryParse(m[2] ?? '') ?? 0, m[3], m[4],
          guessAfternoon: m[2] == null)) ||
      take(r'\b(\d{1,2})[:h](\d{2})(?:\s*h\b)?' + period + r'\b',
          (m) => setTime(int.parse(m[1]!), int.parse(m[2]!), null, m[3], guessAfternoon: false)) ||
      take(r'\b(\d{1,2})\s*(?:h|hrs?)\b' + period, (m) => setTime(int.parse(m[1]!), 0, null, m[2], guessAfternoon: false)) ||
      take(r'\b(\d{1,2})\s*(am|pm)\b', (m) => setTime(int.parse(m[1]!), 0, null, m[2])) ||
      take(r'\b(?:al |a )?mediodia\b', (m) => setTime(12, 0, null, null));

  // --- Repetición ------------------------------------------------------------
  take(r'\bcada\s+' + _num + r'\s+(dias|semanas|meses|anos)\b', (m) {
    final n = _toInt(m[1]) ?? 1;
    final f = switch (m[2]) {
      'dias' => Frequency.daily,
      'semanas' => Frequency.weekly,
      'meses' => Frequency.monthly,
      _ => Frequency.yearly,
    };
    recurrence = Recurrence(frequency: f, interval: n);
  }) ||
      take(r'\b(?:cada dia|todos los dias|a diario|diariamente)\b',
          (_) => recurrence = const Recurrence(frequency: Frequency.daily)) ||
      take(r'\b(?:cada|todos los|todas las|los)\s+' + _wd + r'(?:\s*(?:,|y)\s*' + _wd + r')*\b', (m) {
        final days = RegExp(_wd).allMatches(m[0]!).map((d) => _weekday(d[1]!)).toSet();
        recurrence = Recurrence(frequency: Frequency.weekly, weekdays: days.length == 1 ? const {} : days);
        // Empieza el próximo de esos días (hoy incluido).
        for (var i = 0; i < 7; i++) {
          final d = addDays(today, i);
          if (days.contains(d.weekday)) {
            date ??= d;
            break;
          }
        }
      }) ||
      take(r'\b(?:cada semana|todas las semanas|semanalmente)\b',
          (_) => recurrence = const Recurrence(frequency: Frequency.weekly)) ||
      take(r'\b(?:cada mes|todos los meses|mensualmente)\b',
          (_) => recurrence = const Recurrence(frequency: Frequency.monthly)) ||
      take(r'\b(?:cada ano|todos los anos|anualmente)\b',
          (_) => recurrence = const Recurrence(frequency: Frequency.yearly));

  // --- Fecha -----------------------------------------------------------------
  if (date == null) {
    take(r'\bpasado manana\b', (_) => date = addDays(today, 2)) ||
        take(r'\bmanana\b', (_) => date = addDays(today, 1)) ||
        take(r'\b(?:hoy|esta tarde|esta noche)\b', (m) {
          date = today;
          if (hour == null && m[0] == 'esta tarde') setTime(17, 0, null, null);
          if (hour == null && m[0] == 'esta noche') setTime(21, 0, null, null);
        }) ||
        take(r'\b(?:dentro de|en)\s+' + _num + r'\s+(dias?|semanas?|mes|meses)\b', (m) {
          final n = _toInt(m[1]) ?? 1;
          final unit = m[2]!;
          date = unit.startsWith('dia')
              ? addDays(today, n)
              : unit.startsWith('semana')
                  ? addDays(today, 7 * n)
                  : DateTime(today.year, today.month + n, today.day);
        }) ||
        take(r'\b(?:el\s+)?(?:dia\s+)?(\d{1,2})\s+de\s+(' + _months.join('|') + r')(?:\s+de\s+(\d{4}))?\b', (m) {
          final day = int.parse(m[1]!);
          final month = _months.indexOf(m[2]!) + 1;
          var year = int.tryParse(m[3] ?? '') ?? today.year;
          var d = DateTime(year, month, day);
          if (m[3] == null && d.isBefore(today)) d = DateTime(year + 1, month, day);
          if (d.day == day) date = d;
        }) ||
        take(r'\b(?:el\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b', (m) {
          final day = int.parse(m[1]!), month = int.parse(m[2]!);
          if (month < 1 || month > 12) return;
          var year = int.tryParse(m[3] ?? '') ?? today.year;
          if (year < 100) year += 2000;
          var d = DateTime(year, month, day);
          if (m[3] == null && d.isBefore(today)) d = DateTime(year + 1, month, day);
          if (d.day == day && d.month == month) date = d;
        }) ||
        take(r'\b(?:el\s+|este\s+|esta\s+|el\s+proximo\s+|el\s+que\s+viene\s+)?' + _wd + r'(?:\s+que\s+viene|\s+proximo)?\b', (m) {
          final wd = _weekday(m[1]!);
          var diff = (wd - today.weekday + 7) % 7;
          if (diff == 0) diff = 7;
          date = addDays(today, diff);
        }) ||
        take(r'\b(?:el\s+)?dia\s+(\d{1,2})\b', (m) {
          final day = int.parse(m[1]!);
          var d = DateTime(today.year, today.month, day);
          if (d.isBefore(today)) d = DateTime(today.year, today.month + 1, day);
          if (d.day == day) date = d;
        });
  }

  // --- Título limpio ---------------------------------------------------------
  var title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final connector = RegExp(r'^(?:el|la|los|las|a|de|del|para|en|y|,|-|–)\s+|\s+(?:el|la|los|las|a|de|del|para|en|y|,|-|–)$',
      caseSensitive: false);
  for (var i = 0; i < 4; i++) {
    final cleaned = title.replaceAll(connector, '').replaceAll(RegExp(r'[,\-–]+$'), '').trim();
    if (cleaned == title) break;
    title = cleaned;
  }
  if (title.isNotEmpty) title = title[0].toUpperCase() + title.substring(1);

  return QuickParse(title: title, date: date, hour: hour, minute: minute, recurrence: recurrence);
}
