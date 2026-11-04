import 'package:flutter_test/flutter_test.dart';
import 'package:lapsus/logic/dates.dart';
import 'package:lapsus/logic/occurrences.dart';
import 'package:lapsus/models/item.dart';
import 'package:lapsus/models/priority.dart';
import 'package:lapsus/models/recurrence.dart';

Item _item(DateTime start, {Recurrence? r, ItemKind kind = ItemKind.event}) => Item(
      id: 'x',
      title: 'Prueba',
      categoryId: 'other',
      priority: Priority.normal,
      start: start,
      recurrence: r,
      kind: kind,
      createdAt: DateTime(2026),
    );

List<String> _keys(List<DateTime> l) => l.map(dateKey).toList();

void main() {
  group('Repeticiones', () {
    test('sin repetición solo aparece su día', () {
      final i = _item(DateTime(2026, 11, 5, 17));
      expect(occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 11, 30)),
          [DateTime(2026, 11, 5, 17)]);
      expect(occurrenceStarts(i, DateTime(2026, 11, 6), DateTime(2026, 11, 30)), isEmpty);
    });

    test('diaria cada 2 días mantiene la hora', () {
      final i = _item(DateTime(2026, 11, 1, 9, 30),
          r: const Recurrence(frequency: Frequency.daily, interval: 2));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 11, 8));
      expect(_keys(l), ['2026-11-01', '2026-11-03', '2026-11-05', '2026-11-07']);
      expect(l.every((d) => d.hour == 9 && d.minute == 30), isTrue);
    });

    test('diaria con salto rápido a un rango lejano', () {
      final i = _item(DateTime(2020, 1, 1, 8),
          r: const Recurrence(frequency: Frequency.daily, interval: 3));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 11, 7));
      for (final d in l) {
        expect(dayDiff(DateTime(2020, 1, 1), d) % 3, 0);
      }
      expect(l.length, inInclusiveRange(2, 3));
    });

    test('semanal lunes y jueves', () {
      // 2 nov 2026 es lunes.
      final i = _item(DateTime(2026, 11, 2, 18),
          r: const Recurrence(frequency: Frequency.weekly, weekdays: {1, 4}));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 11, 15));
      expect(_keys(l), ['2026-11-02', '2026-11-05', '2026-11-09', '2026-11-12']);
    });

    test('semanal cada 2 semanas', () {
      final i = _item(DateTime(2026, 11, 4),
          r: const Recurrence(frequency: Frequency.weekly, interval: 2));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 12, 10));
      expect(_keys(l), ['2026-11-04', '2026-11-18', '2026-12-02']);
    });

    test('semanal no genera días anteriores al inicio', () {
      // Empieza en jueves con días lunes y jueves: el lunes de esa semana no cuenta.
      final i = _item(DateTime(2026, 11, 5),
          r: const Recurrence(frequency: Frequency.weekly, weekdays: {1, 4}));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 11, 10));
      expect(_keys(l), ['2026-11-05', '2026-11-09']);
    });

    test('mensual día 31 usa el último día en meses cortos', () {
      final i = _item(DateTime(2026, 1, 31),
          r: const Recurrence(frequency: Frequency.monthly));
      final l = occurrenceStarts(i, DateTime(2026, 1, 1), DateTime(2026, 5, 31));
      expect(_keys(l), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31']);
    });

    test('mensual el 3er martes', () {
      // 17 nov 2026 es el 3er martes.
      final i = _item(DateTime(2026, 11, 17),
          r: const Recurrence(frequency: Frequency.monthly, monthlyMode: MonthlyMode.nthWeekday));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2027, 1, 31));
      expect(_keys(l), ['2026-11-17', '2026-12-15', '2027-01-19']);
    });

    test('mensual el último viernes', () {
      final i = _item(DateTime(2026, 10, 30),
          r: const Recurrence(frequency: Frequency.monthly, monthlyMode: MonthlyMode.lastWeekday));
      final l = occurrenceStarts(i, DateTime(2026, 10, 1), DateTime(2027, 1, 31));
      expect(_keys(l), ['2026-10-30', '2026-11-27', '2026-12-25', '2027-01-29']);
    });

    test('anual 29 de febrero cae el 28 en años no bisiestos', () {
      final i = _item(DateTime(2024, 2, 29),
          r: const Recurrence(frequency: Frequency.yearly));
      final l = occurrenceStarts(i, DateTime(2024, 1, 1), DateTime(2028, 12, 31));
      expect(_keys(l), ['2024-02-29', '2025-02-28', '2026-02-28', '2027-02-28', '2028-02-29']);
    });

    test('hasta una fecha y número de veces', () {
      final until = _item(DateTime(2026, 11, 1),
          r: Recurrence(frequency: Frequency.daily, until: DateTime(2026, 11, 3)));
      expect(occurrenceStarts(until, DateTime(2026, 11, 1), DateTime(2026, 11, 30)).length, 3);

      final count = _item(DateTime(2026, 11, 1),
          r: const Recurrence(frequency: Frequency.weekly, count: 3));
      expect(_keys(occurrenceStarts(count, DateTime(2026, 11, 10), DateTime(2027, 1, 1))),
          ['2026-11-15']);
    });

    test('días saltados (solo esta borrada)', () {
      final i = _item(DateTime(2026, 11, 1), r: const Recurrence(frequency: Frequency.daily));
      final l = occurrenceStarts(i, DateTime(2026, 11, 1), DateTime(2026, 11, 3),
          skip: {'2026-11-02'});
      expect(_keys(l), ['2026-11-01', '2026-11-03']);
    });
  });

  group('RRULE', () {
    test('ida y vuelta', () {
      final start = DateTime(2026, 11, 17);
      final rules = [
        const Recurrence(frequency: Frequency.daily),
        const Recurrence(frequency: Frequency.weekly, interval: 2, weekdays: {1, 4}),
        const Recurrence(frequency: Frequency.monthly, monthlyMode: MonthlyMode.nthWeekday),
        const Recurrence(frequency: Frequency.monthly, monthlyMode: MonthlyMode.lastWeekday),
        Recurrence(frequency: Frequency.yearly, until: DateTime(2030, 1, 1)),
        const Recurrence(frequency: Frequency.daily, count: 10),
      ];
      for (final r in rules) {
        expect(Recurrence.fromRRule(r.toRRule(start)), r, reason: r.toRRule(start));
      }
      expect(rules[1].toRRule(start), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH');
      expect(rules[2].toRRule(start), 'FREQ=MONTHLY;BYDAY=3TU');
    });
  });

  group('Agenda', () {
    test('tareas pendientes de días anteriores', () {
      final once = _item(DateTime(2026, 11, 1, 10), kind: ItemKind.task);
      final weekly = Item(
        id: 'w',
        title: 'Basura',
        categoryId: 'home',
        priority: Priority.normal,
        kind: ItemKind.task,
        start: DateTime(2026, 10, 26),
        recurrence: const Recurrence(frequency: Frequency.weekly),
        createdAt: DateTime(2026),
      );
      final daily = Item(
        id: 'd',
        title: 'Pastilla',
        categoryId: 'health',
        priority: Priority.critical,
        kind: ItemKind.task,
        start: DateTime(2026, 10, 1, 9),
        recurrence: const Recurrence(frequency: Frequency.daily),
        createdAt: DateTime(2026),
      );
      final agenda = Agenda(items: [once, weekly, daily]);
      final overdue = agenda.overdueTasks(DateTime(2026, 11, 4));
      // La única, la última semanal sin hacer (2 nov) y nada de la diaria
      // porque hoy vuelve a tocar.
      expect(overdue.map((o) => '${o.item.id} ${o.key}'), ['x 2026-11-01', 'w 2026-11-02']);

      final done = Agenda(items: [once], completions: {Agenda.completionKey('x', '2026-11-01')});
      expect(done.overdueTasks(DateTime(2026, 11, 4)), isEmpty);
    });

    test('orden: todo el día primero, luego por hora', () {
      final a = _item(DateTime(2026, 11, 4, 18));
      final b = _item(DateTime(2026, 11, 4, 9)).copyWith(id: 'b');
      final c = _item(DateTime(2026, 11, 4)).copyWith(id: 'c', allDay: true);
      final l = Agenda(items: [a, b, c]).onDay(DateTime(2026, 11, 4));
      expect(l.map((o) => o.item.id), ['c', 'b', 'x']);
    });
  });
}
