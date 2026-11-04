import '../models/item.dart';
import '../models/recurrence.dart';
import 'dates.dart';

/// Calcula las fechas de inicio de las apariciones de [item] cuyo día cae
/// entre [rangeStart] y [rangeEnd] (ambos incluidos, por días).
///
/// [skip] contiene las claves de día (`yyyy-MM-dd`) borradas o editadas
/// por separado ("solo esta").
List<DateTime> occurrenceStarts(
  Item item,
  DateTime rangeStart,
  DateTime rangeEnd, {
  Set<String> skip = const {},
}) {
  final from = dateOnly(rangeStart);
  final to = dateOnly(rangeEnd);
  final result = <DateTime>[];
  final rule = item.recurrence;

  if (rule == null) {
    final d = dateOnly(item.start);
    if (!d.isBefore(from) && !d.isAfter(to) && !skip.contains(dateKey(d))) {
      result.add(item.start);
    }
    return result;
  }

  final until = rule.until == null ? null : dateOnly(rule.until!);
  var produced = 0;
  // Si hay límite de veces hay que contar desde el principio; si no, se
  // puede saltar directamente cerca del rango pedido.
  final k0 = rule.count == null ? _fastForward(item.start, rule, from) : 0;
  const maxIterations = 200000;

  for (var k = k0, guard = 0; guard < maxIterations; k++, guard++) {
    var stop = false;
    for (final candidate in _period(item.start, rule, k)) {
      final day = dateOnly(candidate);
      if (day.isAfter(to) || (until != null && day.isAfter(until))) {
        stop = true;
        break;
      }
      if (rule.count != null && produced >= rule.count!) {
        stop = true;
        break;
      }
      produced++;
      if (!day.isBefore(from) && !skip.contains(dateKey(day))) {
        result.add(candidate);
      }
    }
    if (stop) break;
  }
  return result;
}

/// Primer índice de periodo que merece la pena mirar para llegar a [from].
int _fastForward(DateTime start, Recurrence rule, DateTime from) {
  if (!from.isAfter(start)) return 0;
  final n = switch (rule.frequency) {
    Frequency.daily => dayDiff(start, from) ~/ rule.interval,
    Frequency.weekly =>
      (dayDiff(startOfWeek(start), from) ~/ 7) ~/ rule.interval,
    Frequency.monthly =>
      ((from.year - start.year) * 12 + from.month - start.month) ~/
          rule.interval,
    Frequency.yearly => (from.year - start.year) ~/ rule.interval,
  };
  // Un periodo de margen por seguridad.
  return n > 0 ? n - 1 : 0;
}

/// Candidatos (ordenados) del periodo número [k] de la regla.
List<DateTime> _period(DateTime start, Recurrence rule, int k) {
  final h = start.hour, min = start.minute;
  switch (rule.frequency) {
    case Frequency.daily:
      return [DateTime(start.year, start.month, start.day + k * rule.interval, h, min)];

    case Frequency.weekly:
      final week = startOfWeek(start);
      final base = DateTime(week.year, week.month, week.day + 7 * rule.interval * k);
      final days = (rule.weekdays.isEmpty ? {start.weekday} : rule.weekdays).toList()
        ..sort();
      final firstDay = dateOnly(start);
      return [
        for (final wd in days)
          DateTime(base.year, base.month, base.day + wd - 1, h, min),
      ].where((d) => !dateOnly(d).isBefore(firstDay)).toList();

    case Frequency.monthly:
      final total = (start.month - 1) + k * rule.interval;
      final y = start.year + total ~/ 12;
      final m = total % 12 + 1;
      final dim = daysInMonth(y, m);
      int? day;
      switch (rule.monthlyMode) {
        case MonthlyMode.dayOfMonth:
          day = start.day > dim ? dim : start.day;
        case MonthlyMode.nthWeekday:
          final nth = Recurrence.nthOfMonth(start);
          final first = DateTime(y, m, 1);
          final offset = (start.weekday - first.weekday + 7) % 7;
          final d = 1 + offset + 7 * (nth - 1);
          day = d <= dim ? d : null; // Ese mes no tiene un 5º martes.
        case MonthlyMode.lastWeekday:
          final last = DateTime(y, m, dim);
          final offset = (last.weekday - start.weekday + 7) % 7;
          day = dim - offset;
      }
      return day == null ? const [] : [DateTime(y, m, day, h, min)];

    case Frequency.yearly:
      final y = start.year + k * rule.interval;
      final dim = daysInMonth(y, start.month);
      // 29 de febrero en años no bisiestos -> 28 de febrero.
      final day = start.day > dim ? dim : start.day;
      return [DateTime(y, start.month, day, h, min)];
  }
}

/// Índice en memoria de todo lo apuntado, para calcular apariciones rápido.
class Agenda {
  final List<Item> items;

  /// itemId -> claves de día saltadas.
  final Map<String, Set<String>> skips;

  /// Claves `itemId|yyyy-MM-dd` completadas.
  final Set<String> completions;

  const Agenda({
    required this.items,
    this.skips = const {},
    this.completions = const {},
  });

  static String completionKey(String itemId, String dayKey) => '$itemId|$dayKey';

  bool isDone(String itemId, String dayKey) =>
      completions.contains(completionKey(itemId, dayKey));

  /// Todas las apariciones entre dos días (incluidos), ordenadas.
  List<Occurrence> between(DateTime from, DateTime to) {
    final list = <Occurrence>[];
    for (final item in items) {
      for (final s in occurrenceStarts(item, from, to, skip: skips[item.id] ?? const {})) {
        list.add(Occurrence(item: item, start: s, done: isDone(item.id, dateKey(s))));
      }
    }
    list.sort(compareOccurrences);
    return list;
  }

  List<Occurrence> onDay(DateTime day) => between(day, day);

  /// Tareas sin hacer de días anteriores (hasta [lookbackDays] atrás).
  ///
  /// En tareas repetidas solo se muestra la última que se quedó sin hacer, y
  /// solo si hoy no toca otra vez (si hoy toca, ya aparece en "Hoy").
  List<Occurrence> overdueTasks(DateTime today, {int lookbackDays = 365}) {
    final t = dateOnly(today);
    final from = addDays(t, -lookbackDays);
    final yesterday = addDays(t, -1);
    final result = <Occurrence>[];
    for (final item in items.where((i) => i.kind == ItemKind.task)) {
      final skip = skips[item.id] ?? const <String>{};
      final starts = occurrenceStarts(item, from, yesterday, skip: skip);
      final missed = starts.where((s) => !isDone(item.id, dateKey(s))).toList();
      if (missed.isEmpty) continue;
      if (item.isRecurring) {
        if (occurrenceStarts(item, t, t, skip: skip).isNotEmpty) continue;
        result.add(Occurrence(item: item, start: missed.last));
      } else {
        result.addAll(missed.map((s) => Occurrence(item: item, start: s)));
      }
    }
    result.sort(compareOccurrences);
    return result;
  }
}

/// Orden: por día; dentro del día, primero "todo el día" y luego por hora;
/// a igualdad, lo más importante primero.
int compareOccurrences(Occurrence a, Occurrence b) {
  final day = dateOnly(a.start).compareTo(dateOnly(b.start));
  if (day != 0) return day;
  if (a.item.allDay != b.item.allDay) return a.item.allDay ? -1 : 1;
  final time = a.start.compareTo(b.start);
  if (time != 0) return time;
  final p = b.item.priority.weight.compareTo(a.item.priority.weight);
  if (p != 0) return p;
  return a.item.title.compareTo(b.item.title);
}
