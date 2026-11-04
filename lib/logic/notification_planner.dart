import '../models/item.dart';
import '../models/priority.dart';
import 'dates.dart';

/// Ajustes que afectan a los avisos.
class PlannerSettings {
  /// Hora a la que se avisa de las cosas de "todo el día".
  final int allDayHour;
  final int allDayMinute;

  /// Hora del aviso "Mañana tienes..." la víspera (críticos).
  final int eveningHour;

  /// Cada cuántos minutos insiste un aviso crítico sin confirmar.
  final int nagIntervalMinutes;

  /// Cuántas veces insiste como máximo.
  final int nagCount;

  final bool summaryEnabled;
  final int summaryHour;
  final int summaryMinute;

  const PlannerSettings({
    this.allDayHour = 9,
    this.allDayMinute = 0,
    this.eveningHour = 20,
    this.nagIntervalMinutes = 5,
    this.nagCount = 6,
    this.summaryEnabled = true,
    this.summaryHour = 8,
    this.summaryMinute = 0,
  });
}

enum PlanKind { dayBefore, hourBefore, atTime, nag, followUp, snooze, summary }

class Snooze {
  final String itemId;
  final String dayKey;
  final DateTime fireAt;

  const Snooze({required this.itemId, required this.dayKey, required this.fireAt});
}

/// Un aviso concreto que hay que programar en el sistema.
class PlannedNotification {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final Priority priority;
  final PlanKind kind;
  final String? itemId;
  final String? dayKey;
  final bool isTask;

  /// Sonido repetido hasta que se toca (solo el aviso crítico principal).
  final bool insistent;

  const PlannedNotification({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.priority,
    required this.kind,
    this.itemId,
    this.dayKey,
    this.isTask = false,
    this.insistent = false,
  });
}

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Id numérico estable a partir de un texto (FNV-1a de 31 bits).
int stableId(String s) {
  var hash = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Decide qué avisos hay que programar. Es una función pura: recibe lo que
/// hay apuntado y devuelve la lista de avisos, sin tocar el sistema.
///
/// Android permite unas 500 alarmas por app, así que se programan solo las
/// más próximas ([maxCount]) y se recalcula cada vez que algo cambia o se
/// abre la app.
List<PlannedNotification> planNotifications({
  required List<Occurrence> occurrences,
  required DateTime now,
  required PlannerSettings settings,
  List<Snooze> snoozes = const [],
  int maxCount = 400,
}) {
  final out = <PlannedNotification>[];
  final byKey = {for (final o in occurrences) '${o.item.id}|${o.key}': o};
  final snoozeByKey = <String, DateTime>{};
  for (final s in snoozes) {
    final k = '${s.itemId}|${s.dayKey}';
    final prev = snoozeByKey[k];
    if (prev == null || s.fireAt.isAfter(prev)) snoozeByKey[k] = s.fireAt;
  }

  void add(Occurrence o, PlanKind kind, DateTime when, String title, String body,
      {int n = 0, bool insistent = false}) {
    if (!when.isAfter(now)) return;
    final key = '${o.item.id}|${o.key}';
    // Si está pospuesto, no molestar con insistencias antes de la hora nueva.
    final snoozedUntil = snoozeByKey[key];
    if (snoozedUntil != null &&
        snoozedUntil.isAfter(now) &&
        (kind == PlanKind.nag || kind == PlanKind.followUp || kind == PlanKind.atTime) &&
        when.isBefore(snoozedUntil)) {
      return;
    }
    out.add(PlannedNotification(
      // El id incluye hora y textos: si algo cambia, es otro aviso distinto.
      id: stableId('$key|${kind.name}|$n|${when.millisecondsSinceEpoch}|$title|$body'),
      when: when,
      title: title,
      body: body,
      priority: o.item.priority,
      kind: kind,
      itemId: o.item.id,
      dayKey: o.key,
      isTask: o.item.kind == ItemKind.task,
      insistent: insistent,
    ));
  }

  for (final o in occurrences) {
    final item = o.item;
    if (o.done || item.priority == Priority.none) continue;
    final title = item.title;
    final isTask = item.kind == ItemKind.task;
    final day = dateOnly(o.start);

    if (item.allDay) {
      final at = DateTime(day.year, day.month, day.day, settings.allDayHour, settings.allDayMinute);
      switch (item.priority) {
        case Priority.critical:
          add(o, PlanKind.dayBefore,
              DateTime(day.year, day.month, day.day - 1, settings.eveningHour), title, 'Mañana');
          add(o, PlanKind.atTime, at, title, 'Hoy', insistent: true);
          for (var n = 1; n <= settings.nagCount; n++) {
            add(o, PlanKind.nag, at.add(Duration(minutes: settings.nagIntervalMinutes * n * 6)), title,
                'Sigue pendiente', n: n);
          }
        case Priority.important:
          add(o, PlanKind.atTime, at, title, 'Hoy');
          final evening = DateTime(day.year, day.month, day.day, 19);
          if (isTask && evening.isAfter(at)) {
            add(o, PlanKind.followUp, evening, title, 'Aún sin marcar como hecho');
          }
        case Priority.normal:
          add(o, PlanKind.atTime, at, title, 'Hoy');
        case Priority.none:
          break;
      }
    } else {
      final t = o.start;
      final time = hhmm(t);
      switch (item.priority) {
        case Priority.critical:
          add(o, PlanKind.dayBefore, t.subtract(const Duration(days: 1)), title, 'Mañana a las $time');
          add(o, PlanKind.hourBefore, t.subtract(const Duration(hours: 1)), title, 'Dentro de 1 hora · $time');
          add(o, PlanKind.atTime, t, title, 'Ahora · $time', insistent: true);
          for (var n = 1; n <= settings.nagCount; n++) {
            add(o, PlanKind.nag, t.add(Duration(minutes: settings.nagIntervalMinutes * n)), title,
                'Sigue pendiente (era a las $time)', n: n);
          }
        case Priority.important:
          add(o, PlanKind.hourBefore, t.subtract(const Duration(hours: 1)), title, 'Dentro de 1 hora · $time');
          add(o, PlanKind.atTime, t, title, 'Ahora · $time');
          if (isTask) {
            add(o, PlanKind.followUp, t.add(const Duration(minutes: 30)), title, 'Aún sin marcar como hecho');
          }
        case Priority.normal:
          add(o, PlanKind.atTime, t, title, 'Ahora · $time');
        case Priority.none:
          break;
      }
    }
  }

  // Avisos pospuestos ("10 min", "1 hora").
  for (final entry in snoozeByKey.entries) {
    final o = byKey[entry.key];
    if (o == null || o.done) continue;
    final when = entry.value;
    if (!when.isAfter(now)) continue;
    out.add(PlannedNotification(
      id: stableId('${entry.key}|snooze|${when.millisecondsSinceEpoch}'),
      when: when,
      title: o.item.title,
      body: 'Pospuesto',
      priority: o.item.priority,
      kind: PlanKind.snooze,
      itemId: o.item.id,
      dayKey: o.key,
      isTask: o.item.kind == ItemKind.task,
      insistent: o.item.priority == Priority.critical,
    ));
    if (o.item.priority == Priority.critical) {
      for (var n = 1; n <= 3; n++) {
        add(o, PlanKind.nag, when.add(Duration(minutes: settings.nagIntervalMinutes * n)), o.item.title,
            'Sigue pendiente', n: 100 + n);
      }
    }
  }

  // Resumen de cada mañana.
  if (settings.summaryEnabled) {
    final byDay = <String, List<Occurrence>>{};
    for (final o in occurrences) {
      if (o.done) continue;
      byDay.putIfAbsent(o.key, () => []).add(o);
    }
    for (final entry in byDay.entries) {
      final day = parseDateKey(entry.key);
      final when = DateTime(day.year, day.month, day.day, settings.summaryHour, settings.summaryMinute);
      if (!when.isAfter(now)) continue;
      final list = entry.value;
      final n = list.length;
      final lines = list.take(6).map((o) {
        final time = o.item.allDay ? '' : '${hhmm(o.start)}  ';
        final mark = o.item.priority == Priority.critical ? ' (!)' : '';
        return '$time${o.item.title}$mark';
      }).toList();
      if (n > 6) lines.add('+${n - 6} más');
      out.add(PlannedNotification(
        id: stableId('summary|${entry.key}|${when.millisecondsSinceEpoch}|${lines.join('/')}'),
        when: when,
        title: n == 1 ? 'Hoy: 1 pendiente' : 'Hoy: $n pendientes',
        body: lines.join('\n'),
        priority: Priority.normal,
        kind: PlanKind.summary,
      ));
    }
  }

  out.sort((a, b) => a.when.compareTo(b.when));
  return out.length > maxCount ? out.sublist(0, maxCount) : out;
}
