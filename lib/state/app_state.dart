import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../logic/dates.dart';
import '../logic/occurrences.dart';
import '../models/app_settings.dart';
import '../models/category.dart';
import '../models/item.dart';
import '../models/priority.dart';
import '../services/notification_service.dart';

/// A qué apariciones afecta un cambio en algo que se repite.
enum EditScope { single, following, all }

/// Acción para deshacer un cambio.
typedef Undo = Future<void> Function();

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Estado global de la app.
class AppState extends ChangeNotifier {
  final LapsusDatabase db;
  final NotificationService? notifications;

  AppState(this.db, {this.notifications});

  List<Category> categories = const [];
  Agenda agenda = const Agenda(items: []);
  AppSettings settings = const AppSettings();
  bool loaded = false;

  Map<String, Category> get _categoryMap => {for (final c in categories) c.id: c};

  Category categoryOf(String id) =>
      _categoryMap[id] ?? _categoryMap[Category.otherId] ?? Category.defaults.last;

  Future<void> load() async {
    await db.ensureOpen();
    categories = await db.categories();
    agenda = await db.agenda();
    settings = AppSettings.fromMap(await db.settings());
    loaded = true;
    notifyListeners();
  }

  /// Recarga los datos y vuelve a programar los avisos.
  Future<void> _changed({bool reschedule = true}) async {
    await load();
    if (reschedule) unawaited(notifications?.reschedule(db));
  }

  Future<void> refresh() => _changed();

  // ---------------------------------------------------------------------------
  // Consultas para las pantallas
  // ---------------------------------------------------------------------------

  List<Occurrence> onDay(DateTime day) => agenda.onDay(day);
  List<Occurrence> between(DateTime a, DateTime b) => agenda.between(a, b);
  List<Occurrence> overdue(DateTime today) => agenda.overdueTasks(today);

  Item? itemById(String id) {
    for (final i in agenda.items) {
      if (i.id == id) return i;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Eventos
  // ---------------------------------------------------------------------------

  Future<void> toggleDone(Occurrence o) => setDone(o, !o.done);

  Future<void> setDone(Occurrence o, bool done) async {
    await db.setDone(o.item.id, o.key, done);
    if (done) unawaited(notifications?.cancelShownFor(o.item.id, dayKey: o.key));
    await _changed();
  }

  /// Pospone los avisos de una aparición.
  Future<void> snooze(Occurrence o, Duration d) async {
    await db.snooze(o.item.id, o.key, DateTime.now().add(d));
    unawaited(notifications?.cancelShownFor(o.item.id, dayKey: o.key));
    await _changed();
  }

  /// Busca una aparición concreta (para abrirla desde una notificación).
  Occurrence? findOccurrence(String itemId, String dayKey) {
    final day = parseDateKey(dayKey);
    for (final o in agenda.onDay(day)) {
      if (o.item.id == itemId) return o;
    }
    return null;
  }

  /// Guarda un evento nuevo o editado.
  ///
  /// [original] y [occurrence] son el evento y la aparición que se estaban
  /// editando (null si es nuevo). [scope] solo importa si se repite.
  Future<void> saveItem(Item edited, {Item? original, Occurrence? occurrence, EditScope scope = EditScope.all}) async {
    if (original == null || !original.isRecurring || occurrence == null) {
      await db.upsertItem(edited);
      return _changed();
    }

    final isFirst = isSameDay(dateOnly(original.start), occurrence.start);
    if (scope == EditScope.following && isFirst) scope = EditScope.all;

    switch (scope) {
      case EditScope.all:
        // Se mueve toda la serie lo mismo que se ha movido esta aparición.
        final delta = edited.start.difference(occurrence.start);
        await db.upsertItem(edited.copyWith(start: original.start.add(delta)));
      case EditScope.single:
        await db.addSkip(original.id, occurrence.key);
        final single = edited.copyWith(id: newId(), clearRecurrence: true, parentId: original.id);
        await db.upsertItem(single);
        if (occurrence.done) await db.setDone(single.id, dateKey(single.start), true);
      case EditScope.following:
        await _cutSeries(original, occurrence);
        var rule = edited.recurrence;
        if (rule?.count != null) {
          final before = occurrenceStarts(original, original.start, addDays(occurrence.start, -1)).length;
          final remaining = rule!.count! - before;
          rule = remaining > 0 ? rule.copyWith(count: remaining) : rule.copyWith(clearCount: true);
        }
        await db.upsertItem(edited.copyWith(
          id: newId(),
          recurrence: rule,
          clearRecurrence: rule == null,
          clearParent: true,
          createdAt: DateTime.now(),
        ));
    }
    await _changed();
  }

  /// Termina una serie el día antes de [from].
  Future<void> _cutSeries(Item original, Occurrence from) async {
    final rule = original.recurrence!;
    await db.upsertItem(original.copyWith(
      recurrence: rule.copyWith(until: dateOnly(addDays(from.start, -1)), clearCount: true),
    ));
  }

  /// Borra y devuelve cómo deshacerlo.
  Future<Undo> deleteOccurrence(Occurrence o, EditScope scope) async {
    final item = o.item;
    final snapshot = await db.snapshotItem(item.id);
    unawaited(notifications?.cancelShownFor(item.id, dayKey: scope == EditScope.single ? o.key : null));
    if (!item.isRecurring || scope == EditScope.all ||
        (scope == EditScope.following && isSameDay(dateOnly(item.start), o.start))) {
      await db.deleteItem(item.id);
    } else if (scope == EditScope.single) {
      await db.addSkip(item.id, o.key);
    } else {
      await _cutSeries(item, o);
    }
    await _changed();
    return () => _restore(snapshot);
  }

  Future<void> _restore(Map<String, List<Map<String, Object?>>> snapshot) async {
    await db.restoreSnapshot(snapshot);
    await _changed();
  }

  /// Mueve una aparición a otro día (manteniendo la hora). Si se repite,
  /// solo se mueve esa vez. Devuelve cómo deshacerlo.
  Future<Undo> moveOccurrence(Occurrence o, DateTime day) async {
    final item = o.item;
    final snapshot = await db.snapshotItem(item.id);
    final start = DateTime(day.year, day.month, day.day, o.start.hour, o.start.minute);
    unawaited(notifications?.cancelShownFor(item.id, dayKey: o.key));
    if (item.isRecurring) {
      await saveItem(item.copyWith(start: start), original: item, occurrence: o, scope: EditScope.single);
    } else {
      await db.setDone(item.id, o.key, false);
      await db.upsertItem(item.copyWith(start: start));
      await _changed();
    }
    return () => _restore(snapshot);
  }

  /// Guarda la lista de comprobación de un elemento.
  Future<void> updateChecklist(Item item, List<CheckEntry> list) async {
    await db.upsertItem(item.copyWith(checklist: list));
    await _changed(reschedule: false);
  }

  // ---------------------------------------------------------------------------
  // Categorías
  // ---------------------------------------------------------------------------

  Future<void> saveCategory(Category c) async {
    await db.upsertCategory(c);
    await _changed(reschedule: false);
  }

  Future<void> deleteCategory(Category c) async {
    if (!c.isDeletable) return;
    await db.deleteCategory(c.id, Category.otherId);
    await _changed();
  }

  Future<int> countItemsInCategory(String id) => db.countItemsInCategory(id);

  /// Restaura la importancia por defecto original de las categorías de
  /// serie (las creadas por el usuario no cambian).
  Future<void> restoreDefaultPriorities() async {
    for (final c in categories) {
      final d = Category.defaultFor(c.id);
      if (d != null) await db.upsertCategory(c.copyWith(defaultPriority: d.defaultPriority));
    }
    await _changed(reschedule: false);
  }

  int get nextCategoryOrder =>
      categories.where((c) => c.id != Category.otherId).fold(0, (m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;

  // ---------------------------------------------------------------------------
  // Ajustes
  // ---------------------------------------------------------------------------

  Future<void> updateSettings(AppSettings s, {bool reschedule = false}) async {
    settings = s;
    notifyListeners();
    for (final e in s.toMap().entries) {
      await db.setSetting(e.key, e.value);
    }
    if (reschedule) unawaited(notifications?.reschedule(db));
  }

  // ---------------------------------------------------------------------------
  // Copia de seguridad
  // ---------------------------------------------------------------------------

  Future<Uint8List> exportBackup() async {
    final data = await db.exportAll();
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
  }

  Future<void> importBackup(Uint8List bytes) async {
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('Archivo no válido');
    }
    if (data is! Map<String, Object?>) {
      throw const FormatException('Archivo no válido');
    }
    await db.importAll(data);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // Ayudas para crear eventos
  // ---------------------------------------------------------------------------

  Item draft({DateTime? day}) {
    final now = DateTime.now();
    final base = day ?? now;
    // Por defecto, la próxima hora en punto.
    var start = DateTime(base.year, base.month, base.day, now.hour + 1);
    if (!isSameDay(start, base)) start = DateTime(base.year, base.month, base.day, 23);
    final cat = categoryOf(Category.otherId);
    return Item(
      id: newId(),
      title: '',
      categoryId: cat.id,
      priority: cat.defaultPriority,
      start: start,
      createdAt: now,
    );
  }

  Priority defaultPriorityFor(String categoryId) => categoryOf(categoryId).defaultPriority;
}
