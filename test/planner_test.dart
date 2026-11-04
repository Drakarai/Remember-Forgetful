import 'package:flutter_test/flutter_test.dart';
import 'package:lapsus/logic/notification_planner.dart';
import 'package:lapsus/models/item.dart';
import 'package:lapsus/models/priority.dart';
import 'package:lapsus/models/recurrence.dart';

Occurrence _occ(Priority p, DateTime start,
        {bool allDay = false, ItemKind kind = ItemKind.event, bool done = false}) =>
    Occurrence(
      item: Item(
        id: 'i-${p.name}',
        title: 'Cosa',
        categoryId: 'other',
        priority: p,
        allDay: allDay,
        kind: kind,
        start: start,
        createdAt: DateTime(2026),
      ),
      start: start,
      done: done,
    );

void main() {
  final now = DateTime(2026, 11, 3, 12);
  const settings = PlannerSettings(summaryEnabled: false);

  List<PlanKind> kinds(List<PlannedNotification> l) => l.map((n) => n.kind).toList();

  test('crítico: víspera, 1 h antes, en el momento e insistencias', () {
    final l = planNotifications(
      occurrences: [_occ(Priority.critical, DateTime(2026, 11, 5, 17))],
      now: now,
      settings: settings,
    );
    expect(kinds(l), [
      PlanKind.dayBefore,
      PlanKind.hourBefore,
      PlanKind.atTime,
      ...List.filled(6, PlanKind.nag),
    ]);
    expect(l[2].insistent, isTrue);
    expect(l.last.when, DateTime(2026, 11, 5, 17, 30));
  });

  test('importante: 1 h antes, momento y "¿lo hiciste?" solo en tareas', () {
    final ev = planNotifications(
        occurrences: [_occ(Priority.important, DateTime(2026, 11, 5, 17))], now: now, settings: settings);
    expect(kinds(ev), [PlanKind.hourBefore, PlanKind.atTime]);
    final task = planNotifications(
        occurrences: [_occ(Priority.important, DateTime(2026, 11, 5, 17), kind: ItemKind.task)],
        now: now,
        settings: settings);
    expect(kinds(task), [PlanKind.hourBefore, PlanKind.atTime, PlanKind.followUp]);
  });

  test('normal un aviso; sin aviso nada; hecho nada', () {
    expect(
        kinds(planNotifications(
            occurrences: [_occ(Priority.normal, DateTime(2026, 11, 5, 17))], now: now, settings: settings)),
        [PlanKind.atTime]);
    expect(
        planNotifications(
            occurrences: [_occ(Priority.none, DateTime(2026, 11, 5, 17))], now: now, settings: settings),
        isEmpty);
    expect(
        planNotifications(
            occurrences: [_occ(Priority.critical, DateTime(2026, 11, 5, 17), done: true)],
            now: now,
            settings: settings),
        isEmpty);
  });

  test('no programa nada en el pasado', () {
    final l = planNotifications(
        occurrences: [_occ(Priority.critical, DateTime(2026, 11, 3, 12, 12))], now: now, settings: settings);
    // Ya pasó la víspera y la hora antes; quedan el momento y las insistencias.
    expect(kinds(l).first, PlanKind.atTime);
    expect(l.every((n) => n.when.isAfter(now)), isTrue);
  });

  test('todo el día usa la hora configurada', () {
    final l = planNotifications(
      occurrences: [_occ(Priority.normal, DateTime(2026, 11, 5), allDay: true)],
      now: now,
      settings: const PlannerSettings(summaryEnabled: false, allDayHour: 10, allDayMinute: 30),
    );
    expect(l.single.when, DateTime(2026, 11, 5, 10, 30));
  });

  test('posponer evita insistencias hasta la nueva hora', () {
    final o = _occ(Priority.critical, DateTime(2026, 11, 3, 12, 1));
    final l = planNotifications(
      occurrences: [o],
      now: DateTime(2026, 11, 3, 12, 2),
      settings: settings,
      snoozes: [Snooze(itemId: o.item.id, dayKey: o.key, fireAt: DateTime(2026, 11, 3, 13))],
    );
    expect(l.first.kind, PlanKind.snooze);
    expect(l.first.when, DateTime(2026, 11, 3, 13));
    expect(l.where((n) => n.kind == PlanKind.nag).every((n) => n.when.isAfter(DateTime(2026, 11, 3, 13))),
        isTrue);
  });

  test('resumen diario lista lo del día', () {
    final l = planNotifications(
      occurrences: [
        _occ(Priority.critical, DateTime(2026, 11, 4, 9)),
        _occ(Priority.none, DateTime(2026, 11, 4, 18)),
      ],
      now: now,
      settings: const PlannerSettings(summaryHour: 8),
    );
    final s = l.firstWhere((n) => n.kind == PlanKind.summary);
    expect(s.when, DateTime(2026, 11, 4, 8));
    expect(s.title, 'Hoy: 2 pendientes');
    expect(s.body, contains('09:00  Cosa (!)'));
  });

  test('ids estables y sin repetir', () {
    final occs = [
      for (var d = 4; d < 20; d++) _occ(Priority.critical, DateTime(2026, 11, d, 9)),
    ];
    final occs2 = [
      for (final o in occs)
        Occurrence(item: o.item.copyWith(id: 'id-${o.key}'), start: o.start),
    ];
    final a = planNotifications(occurrences: occs2, now: now, settings: const PlannerSettings());
    final b = planNotifications(occurrences: occs2, now: now, settings: const PlannerSettings());
    expect(a.map((n) => n.id).toSet().length, a.length);
    expect(a.map((n) => n.id).toList(), b.map((n) => n.id).toList());
  });

  test('respeta el máximo de avisos', () {
    final occs = [
      for (var d = 4; d < 200; d++)
        Occurrence(
          item: _occ(Priority.critical, DateTime(2026, 11, 4, 9)).item.copyWith(id: 'n$d'),
          start: DateTime(2026, 11, d, 9),
        ),
    ];
    final l = planNotifications(occurrences: occs, now: now, settings: settings, maxCount: 50);
    expect(l.length, 50);
  });

  test('horas de silencio: lo normal espera, lo crítico no', () {
    const quiet = PlannerSettings(summaryEnabled: false, quietEnabled: true, quietStart: 23 * 60, quietEnd: 8 * 60);
    final normal = planNotifications(
        occurrences: [_occ(Priority.normal, DateTime(2026, 11, 5, 23, 30))], now: now, settings: quiet);
    expect(normal.single.when, DateTime(2026, 11, 6, 8));
    expect(normal.single.body, 'Era a las 23:30');

    final important = planNotifications(
        occurrences: [_occ(Priority.important, DateTime(2026, 11, 6, 7, 30), kind: ItemKind.task)],
        now: now,
        settings: quiet);
    // El de 1 h antes y el "¿lo hiciste?" (8:00) caen o no en silencio:
    // solo queda el principal (movido a las 8) y el recordatorio de las 8:00.
    expect(important.map((n) => n.when).toSet(), {DateTime(2026, 11, 6, 8)});

    final critical = planNotifications(
        occurrences: [_occ(Priority.critical, DateTime(2026, 11, 5, 23, 30))], now: now, settings: quiet);
    expect(critical.any((n) => n.kind == PlanKind.atTime && n.when == DateTime(2026, 11, 5, 23, 30)), isTrue);

    const daytime = PlannerSettings(quietEnabled: true, quietStart: 14 * 60, quietEnd: 16 * 60);
    expect(daytime.quietUntil(DateTime(2026, 11, 5, 15)), DateTime(2026, 11, 5, 16));
    expect(daytime.quietUntil(DateTime(2026, 11, 5, 17)), isNull);
  });

  test('cumpleaños con año: el aviso dice la edad', () {
    final item = Item(
      id: 'b',
      title: 'Cumpleaños de Laura',
      categoryId: 'birthday',
      priority: Priority.normal,
      allDay: true,
      start: DateTime(1996, 11, 5),
      recurrence: const Recurrence(frequency: Frequency.yearly),
      sinceYear: 1996,
      createdAt: DateTime(2026),
    );
    final l = planNotifications(
      occurrences: [Occurrence(item: item, start: DateTime(2026, 11, 5))],
      now: now,
      settings: settings,
    );
    expect(l.single.body, 'Hoy · cumple 30');
    expect(item.copyWith(categoryId: 'other').yearsLabel(DateTime(2026, 11, 5)), '30 años');
  });
}
