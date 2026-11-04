import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lapsus/data/database.dart';
import 'package:lapsus/logic/dates.dart';
import 'package:lapsus/models/category.dart';
import 'package:lapsus/models/item.dart';
import 'package:lapsus/models/priority.dart';
import 'package:lapsus/models/recurrence.dart';
import 'package:lapsus/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _n = 0;

Future<AppState> _state() async {
  sqfliteFfiInit();
  // Una base de datos en memoria distinta para cada prueba.
  final db = await LapsusDatabase.open(
      path: 'file:lapsus_test_${_n++}?mode=memory&cache=shared', factory: databaseFactoryFfiNoIsolate);
  final s = AppState(db);
  await s.load();
  return s;
}

Item _daily(String id) => Item(
      id: id,
      title: 'Pastilla',
      categoryId: 'health',
      priority: Priority.critical,
      kind: ItemKind.task,
      start: DateTime(2026, 11, 1, 9),
      recurrence: const Recurrence(frequency: Frequency.daily),
      createdAt: DateTime(2026),
    );

void main() {
  test('categorías por defecto', () async {
    final s = await _state();
    expect(s.categories.map((c) => c.id), contains(Category.otherId));
    expect(s.defaultPriorityFor('health'), Priority.critical);
  });

  test('editar solo esta vez', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    final occ = s.onDay(DateTime(2026, 11, 3)).single;
    await s.saveItem(occ.item.copyWith(title: 'Pastilla doble', start: DateTime(2026, 11, 3, 10)),
        original: occ.item, occurrence: occ, scope: EditScope.single);
    final day = s.onDay(DateTime(2026, 11, 3));
    expect(day.single.item.title, 'Pastilla doble');
    expect(day.single.start.hour, 10);
    expect(s.onDay(DateTime(2026, 11, 4)).single.item.title, 'Pastilla');
  });

  test('editar esta y las siguientes', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    final occ = s.onDay(DateTime(2026, 11, 5)).single;
    await s.saveItem(occ.item.copyWith(start: DateTime(2026, 11, 5, 21)),
        original: occ.item, occurrence: occ, scope: EditScope.following);
    expect(s.onDay(DateTime(2026, 11, 4)).single.start.hour, 9);
    expect(s.onDay(DateTime(2026, 11, 5)).single.start.hour, 21);
    expect(s.onDay(DateTime(2026, 11, 9)).single.start.hour, 21);
  });

  test('editar todas mueve la serie entera', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    final occ = s.onDay(DateTime(2026, 11, 5)).single;
    await s.saveItem(occ.item.copyWith(start: DateTime(2026, 11, 5, 8)),
        original: occ.item, occurrence: occ, scope: EditScope.all);
    expect(s.onDay(DateTime(2026, 11, 1)).single.start.hour, 8);
    expect(s.itemById('a')!.start, DateTime(2026, 11, 1, 8));
  });

  test('borrar solo esta, siguientes y todas', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    await s.deleteOccurrence(s.onDay(DateTime(2026, 11, 3)).single, EditScope.single);
    expect(s.onDay(DateTime(2026, 11, 3)), isEmpty);
    expect(s.onDay(DateTime(2026, 11, 4)), isNotEmpty);

    await s.deleteOccurrence(s.onDay(DateTime(2026, 11, 10)).single, EditScope.following);
    expect(s.onDay(DateTime(2026, 11, 9)), isNotEmpty);
    expect(s.onDay(DateTime(2026, 11, 10)), isEmpty);

    await s.deleteOccurrence(s.onDay(DateTime(2026, 11, 5)).single, EditScope.all);
    expect(s.agenda.items, isEmpty);
  });

  test('marcar como hecho y pendientes', () async {
    final s = await _state();
    final once = Item(
      id: 'b',
      title: 'Pagar luz',
      categoryId: 'payments',
      priority: Priority.important,
      kind: ItemKind.task,
      start: addDays(dateOnly(DateTime.now()), -2),
      allDay: true,
      createdAt: DateTime.now(),
    );
    await s.saveItem(once);
    expect(s.overdue(DateTime.now()).length, 1);
    await s.toggleDone(s.overdue(DateTime.now()).single);
    expect(s.overdue(DateTime.now()), isEmpty);
  });

  test('borrar categoría mueve sus cosas a Otros', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    await s.deleteCategory(s.categoryOf('health'));
    expect(s.itemById('a')!.categoryId, Category.otherId);
    expect(s.categories.any((c) => c.id == 'health'), isFalse);
  });

  test('restaurar importancias por defecto', () async {
    final s = await _state();
    await s.saveCategory(s.categoryOf('health').copyWith(defaultPriority: Priority.none));
    expect(s.defaultPriorityFor('health'), Priority.none);
    await s.restoreDefaultPriorities();
    expect(s.defaultPriorityFor('health'), Priority.critical);
  });

  test('copia de seguridad: exportar e importar', () async {
    final a = await _state();
    await a.saveItem(_daily('a'));
    await a.toggleDone(a.onDay(DateTime(2026, 11, 2)).single);
    final bytes = await a.exportBackup();

    final b = await _state();
    await b.importBackup(bytes);
    expect(b.itemById('a')!.recurrence, const Recurrence(frequency: Frequency.daily));
    expect(b.onDay(DateTime(2026, 11, 2)).single.done, isTrue);

    expect(() => b.importBackup(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('si algo cierra la base de datos, la app la vuelve a abrir', () async {
    sqfliteFfiInit();
    final dir = await databaseFactoryFfiNoIsolate.getDatabasesPath();
    final path = '$dir/reopen_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = await LapsusDatabase.open(path: path, factory: databaseFactoryFfiNoIsolate);
    final s = AppState(db);
    await s.load();
    await s.saveItem(_daily('a'));
    await db.db.close(); // Lo que hacía antes el botón de la notificación.
    await s.refresh();
    expect(s.itemById('a'), isNotNull);
    await s.toggleDone(s.onDay(DateTime(2026, 11, 2)).single);
    expect(s.onDay(DateTime(2026, 11, 2)).single.done, isTrue);
    await db.close();
    await databaseFactoryFfiNoIsolate.deleteDatabase(path);
  });
}
