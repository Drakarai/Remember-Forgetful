import 'package:flutter_test/flutter_test.dart';
import 'package:lapsus/logic/quick_parse.dart';
import 'package:lapsus/models/recurrence.dart';

// Miércoles 4 de noviembre de 2026, 10:00.
final now = DateTime(2026, 11, 4, 10);

void main() {
  void expectParse(String input,
      {required String title, DateTime? date, int? hour, int? minute, Recurrence? rec}) {
    final p = parseQuick(input, now);
    expect(p.title, title, reason: input);
    expect(p.date, date, reason: '$input (fecha)');
    expect(p.hour, hour, reason: '$input (hora)');
    if (minute != null) expect(p.minute, minute, reason: '$input (minutos)');
    expect(p.recurrence, rec, reason: '$input (repetición)');
  }

  test('días relativos', () {
    expectParse('Dentista mañana', title: 'Dentista', date: DateTime(2026, 11, 5));
    expectParse('pagar luz hoy', title: 'Pagar luz', date: DateTime(2026, 11, 4));
    expectParse('Llamar a Ana pasado mañana', title: 'Llamar a Ana', date: DateTime(2026, 11, 6));
    expectParse('revisar coche dentro de 3 días', title: 'Revisar coche', date: DateTime(2026, 11, 7));
    expectParse('renovar dni en dos semanas', title: 'Renovar dni', date: DateTime(2026, 11, 18));
  });

  test('días de la semana y fechas', () {
    expectParse('Cena el viernes', title: 'Cena', date: DateTime(2026, 11, 6));
    expectParse('reunión el miércoles', title: 'Reunión', date: DateTime(2026, 11, 11));
    expectParse('examen el 15 de diciembre', title: 'Examen', date: DateTime(2026, 12, 15));
    expectParse('boda 3 de marzo', title: 'Boda', date: DateTime(2027, 3, 3));
    expectParse('ITV 20/1', title: 'ITV', date: DateTime(2027, 1, 20));
    expectParse('vuelo 2/12/2026', title: 'Vuelo', date: DateTime(2026, 12, 2));
    expectParse('alquiler el día 1', title: 'Alquiler', date: DateTime(2026, 12, 1));
  });

  test('horas', () {
    expectParse('Dentista mañana a las 5', title: 'Dentista', date: DateTime(2026, 11, 5), hour: 17, minute: 0);
    expectParse('médico a las 9', title: 'Médico', hour: 9, minute: 0);
    expectParse('cine a las 8 y media de la tarde', title: 'Cine', hour: 20, minute: 30);
    expectParse('llamar a las 6 menos cuarto', title: 'Llamar', hour: 17, minute: 45);
    expectParse('desayuno a las 7 de la mañana', title: 'Desayuno', hour: 7, minute: 0);
    expectParse('reunión 17:30', title: 'Reunión', hour: 17, minute: 30);
    expectParse('gimnasio 19h', title: 'Gimnasio', hour: 19, minute: 0);
    expectParse('comida con papá a mediodía', title: 'Comida con papá', hour: 12, minute: 0);
    expectParse('Mañana a las 10 de la mañana dentista',
        title: 'Dentista', date: DateTime(2026, 11, 5), hour: 10, minute: 0);
  });

  test('repeticiones', () {
    expectParse('Tomar pastilla todos los días a las 9',
        title: 'Tomar pastilla', hour: 9, rec: const Recurrence(frequency: Frequency.daily));
    expectParse('sacar la basura todos los lunes y jueves',
        title: 'Sacar la basura',
        date: DateTime(2026, 11, 5),
        rec: const Recurrence(frequency: Frequency.weekly, weekdays: {1, 4}));
    expectParse('clase de inglés cada martes',
        title: 'Clase de inglés', date: DateTime(2026, 11, 10), rec: const Recurrence(frequency: Frequency.weekly));
    expectParse('regar plantas cada 3 días',
        title: 'Regar plantas', rec: const Recurrence(frequency: Frequency.daily, interval: 3));
    expectParse('pagar alquiler cada mes', title: 'Pagar alquiler', rec: const Recurrence(frequency: Frequency.monthly));
  });

  test('sin fechas no cambia nada', () {
    final p = parseQuick('Comprar pan', now);
    expect(p.found, isFalse);
    expect(p.title, 'Comprar pan');
    // "mañana" dentro de otra palabra no cuenta.
    expect(parseQuick('Mañanas de yoga', now).date, isNull);
  });
}
