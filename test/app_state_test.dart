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

  test('deshacer un borrado lo deja todo como estaba', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    await s.toggleDone(s.onDay(DateTime(2026, 11, 2)).single);
    final undo = await s.deleteOccurrence(s.onDay(DateTime(2026, 11, 3)).single, EditScope.all);
    expect(s.agenda.items, isEmpty);
    await undo();
    expect(s.itemById('a'), isNotNull);
    expect(s.onDay(DateTime(2026, 11, 2)).single.done, isTrue);
  });

  test('pasar a mañana: una vez en las repetidas, la fecha en las sueltas', () async {
    final s = await _state();
    await s.saveItem(_daily('a'));
    final undo = await s.moveOccurrence(s.onDay(DateTime(2026, 11, 3)).single, DateTime(2026, 11, 4));
    expect(s.onDay(DateTime(2026, 11, 3)), isEmpty);
    expect(s.onDay(DateTime(2026, 11, 4)).length, 2, reason: 'la de siempre y la movida');
    expect(s.onDay(DateTime(2026, 11, 4)).every((o) => o.start.hour == 9), isTrue);
    await undo();
    expect(s.onDay(DateTime(2026, 11, 3)).length, 1);
    expect(s.onDay(DateTime(2026, 11, 4)).length, 1);

    final single = Item(
      id: 'b',
      title: 'Pagar',
      categoryId: 'payments',
      priority: Priority.normal,
      kind: ItemKind.task,
      start: DateTime(2026, 11, 1, 18),
      createdAt: DateTime(2026),
    );
    await s.saveItem(single);
    await s.moveOccurrence(s.onDay(DateTime(2026, 11, 1)).firstWhere((o) => o.item.id == 'b'), DateTime(2026, 11, 5));
    expect(s.itemById('b')!.start, DateTime(2026, 11, 5, 18));
  });

  test('lista de comprobación y año se guardan', () async {
    final s = await _state();
    await s.saveItem(_daily('a').copyWith(sinceYear: 1990, checklist: const [CheckEntry('DNI'), CheckEntry('Cargador')]));
    var item = s.itemById('a')!;
    expect(item.sinceYear, 1990);
    expect(item.checklist.map((c) => c.text), ['DNI', 'Cargador']);
    await s.updateChecklist(item, [item.checklist.first.copyWith(done: true), item.checklist.last]);
    item = s.itemById('a')!;
    expect(item.checklist.first.done, isTrue);
  });

  test('actualizar desde la versión 1 de la base de datos no pierde nada', () async {
    sqfliteFfiInit();
    final f = databaseFactoryFfiNoIsolate;
    final path = '${await f.getDatabasesPath()}/upgrade_${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await f.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL, '
          'color INTEGER NOT NULL, default_priority TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)');
      await db.execute("CREATE TABLE items(id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', "
          'kind TEXT NOT NULL, category_id TEXT NOT NULL, priority TEXT NOT NULL, all_day INTEGER NOT NULL DEFAULT 0, '
          'start TEXT NOT NULL, rrule TEXT, parent_id TEXT, created_at TEXT NOT NULL)');
      for (final t in ['skips', 'completions', 'snoozes']) {
        final extra = t == 'completions' ? ', completed_at TEXT NOT NULL' : (t == 'snoozes' ? ', fire_at TEXT NOT NULL' : '');
        await db.execute('CREATE TABLE $t(item_id TEXT NOT NULL, day_key TEXT NOT NULL$extra, PRIMARY KEY(item_id, day_key))');
      }
      await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.insert('items', {
        'id': 'old', 'title': 'Viejo', 'kind': 'event', 'category_id': 'other', 'priority': 'normal',
        'start': DateTime(2026, 11, 1, 9).toIso8601String(), 'created_at': DateTime(2026).toIso8601String(),
      });
    }));
    await old.close();

    final db = await LapsusDatabase.open(path: path, factory: f);
    final s = AppState(db);
    await s.load();
    expect(s.itemById('old')!.title, 'Viejo');
    await s.saveItem(s.itemById('old')!.copyWith(sinceYear: 2000, checklist: const [CheckEntry('x')]));
    expect(s.itemById('old')!.sinceYear, 2000);
    await db.close();
    await f.deleteDatabase(path);
  });
}
