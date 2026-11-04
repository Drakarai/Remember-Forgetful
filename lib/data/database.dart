import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logic/notification_planner.dart';
import '../logic/occurrences.dart';
import '../models/category.dart';
import '../models/item.dart';

/// Acceso a la base de datos SQLite local. Todo se guarda en el móvil:
/// funciona sin conexión y sin servidores.
class LapsusDatabase {
  Database db;
  final DatabaseFactory _factory;
  final String _path;
  final bool _singleInstance;
  LapsusDatabase._(this.db, this._factory, this._path, this._singleInstance);

  static const _version = 1;

  /// [shared] = false abre una conexión propia. Lo usan las tareas en
  /// segundo plano: en Android la conexión compartida es la misma que la de
  /// la app abierta, y cerrarla la dejaría sin base de datos.
  static Future<LapsusDatabase> open({String? path, DatabaseFactory? factory, bool shared = true}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'lapsus.db');
    final db = await _openRaw(f, dbPath, shared);
    return LapsusDatabase._(db, f, dbPath, shared);
  }

  /// Vuelve a abrir la base de datos si algo la ha cerrado.
  Future<void> ensureOpen() async {
    if (!db.isOpen) db = await _openRaw(_factory, _path, _singleInstance);
  }

  static Future<Database> _openRaw(DatabaseFactory f, String dbPath, bool shared) {
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        singleInstance: shared,
        version: _version,
        onCreate: (db, _) async {
          await _createSchema(db);
          final batch = db.batch();
          for (final c in Category.defaults) {
            batch.insert('categories', c.toMap());
          }
          await batch.commit(noResult: true);
        },
      ),
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        default_priority TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE items(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL,
        category_id TEXT NOT NULL,
        priority TEXT NOT NULL,
        all_day INTEGER NOT NULL DEFAULT 0,
        start TEXT NOT NULL,
        rrule TEXT,
        parent_id TEXT,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE skips(
        item_id TEXT NOT NULL,
        day_key TEXT NOT NULL,
        PRIMARY KEY(item_id, day_key)
      )''');
    await db.execute('''
      CREATE TABLE completions(
        item_id TEXT NOT NULL,
        day_key TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        PRIMARY KEY(item_id, day_key)
      )''');
    await db.execute('''
      CREATE TABLE snoozes(
        item_id TEXT NOT NULL,
        day_key TEXT NOT NULL,
        fire_at TEXT NOT NULL,
        PRIMARY KEY(item_id, day_key)
      )''');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  Future<void> close() => db.close();

  // ---------------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------------

  Future<List<Category>> categories() async {
    final rows = await db.query('categories', orderBy: 'sort_order, name');
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Item>> items() async {
    final rows = await db.query('items');
    return rows.map(Item.fromMap).toList();
  }

  Future<Agenda> agenda() async {
    final items = await this.items();
    final skips = <String, Set<String>>{};
    for (final r in await db.query('skips')) {
      skips.putIfAbsent(r['item_id'] as String, () => {}).add(r['day_key'] as String);
    }
    final completions = {
      for (final r in await db.query('completions'))
        Agenda.completionKey(r['item_id'] as String, r['day_key'] as String),
    };
    return Agenda(items: items, skips: skips, completions: completions);
  }

  Future<List<Snooze>> snoozes() async {
    final rows = await db.query('snoozes');
    return [
      for (final r in rows)
        Snooze(
          itemId: r['item_id'] as String,
          dayKey: r['day_key'] as String,
          fireAt: DateTime.parse(r['fire_at'] as String),
        ),
    ];
  }

  Future<Map<String, String>> settings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  // ---------------------------------------------------------------------------
  // Escritura
  // ---------------------------------------------------------------------------

  Future<void> setSetting(String key, String value) => db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> upsertItem(Item item) =>
      db.insert('items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Borra un evento entero, con sus excepciones, completados y avisos.
  Future<void> deleteItem(String id) => db.transaction((txn) async {
        final children = await txn.query('items', columns: ['id'], where: 'parent_id = ?', whereArgs: [id]);
        final ids = [id, ...children.map((r) => r['id'] as String)];
        for (final i in ids) {
          await txn.delete('items', where: 'id = ?', whereArgs: [i]);
          await txn.delete('skips', where: 'item_id = ?', whereArgs: [i]);
          await txn.delete('completions', where: 'item_id = ?', whereArgs: [i]);
          await txn.delete('snoozes', where: 'item_id = ?', whereArgs: [i]);
        }
      });

  Future<void> addSkip(String itemId, String dayKey) => db.insert(
        'skips',
        {'item_id': itemId, 'day_key': dayKey},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  Future<void> setDone(String itemId, String dayKey, bool done) async {
    if (done) {
      await db.insert(
        'completions',
        {'item_id': itemId, 'day_key': dayKey, 'completed_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.delete('snoozes', where: 'item_id = ? AND day_key = ?', whereArgs: [itemId, dayKey]);
    } else {
      await db.delete('completions', where: 'item_id = ? AND day_key = ?', whereArgs: [itemId, dayKey]);
    }
  }

  Future<void> snooze(String itemId, String dayKey, DateTime fireAt) => db.insert(
        'snoozes',
        {'item_id': itemId, 'day_key': dayKey, 'fire_at': fireAt.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> cleanupSnoozes(DateTime now) =>
      db.delete('snoozes', where: 'fire_at < ?', whereArgs: [now.subtract(const Duration(days: 1)).toIso8601String()]);

  Future<void> upsertCategory(Category c) =>
      db.insert('categories', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Borra una categoría moviendo sus eventos a [moveTo].
  Future<void> deleteCategory(String id, String moveTo) => db.transaction((txn) async {
        await txn.update('items', {'category_id': moveTo}, where: 'category_id = ?', whereArgs: [id]);
        await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
      });

  Future<int> countItemsInCategory(String id) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM items WHERE category_id = ?', [id]);
    return (r.first['n'] as num).toInt();
  }

  // ---------------------------------------------------------------------------
  // Copia de seguridad
  // ---------------------------------------------------------------------------

  static const _tables = ['categories', 'items', 'skips', 'completions', 'settings'];

  Future<Map<String, Object?>> exportAll() async => {
        'app': 'lapsus',
        'format': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        for (final t in _tables) t: await db.query(t),
      };

  /// Sustituye todo por el contenido de una copia. Lanza [FormatException]
  /// si el archivo no es una copia de Lapsus.
  Future<void> importAll(Map<String, Object?> data) async {
    if (data['app'] != 'lapsus') {
      throw const FormatException('El archivo no es una exportación de Lapsus');
    }
    await db.transaction((txn) async {
      for (final t in [..._tables, 'snoozes']) {
        await txn.delete(t);
      }
      for (final t in _tables) {
        final rows = (data[t] as List?) ?? const [];
        for (final r in rows) {
          await txn.insert(t, Map<String, Object?>.from(r as Map),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      final cats = await txn.query('categories', where: 'id = ?', whereArgs: [Category.otherId]);
      if (cats.isEmpty) {
        await txn.insert('categories', Category.defaults.last.toMap());
      }
    });
  }
}
