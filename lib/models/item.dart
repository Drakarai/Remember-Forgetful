import 'dart:convert';

import '../logic/dates.dart';
import 'category.dart';
import 'priority.dart';
import 'recurrence.dart';

/// Evento: pasa en un momento (dentista a las 17:00). Si pasa, pasa.
/// Tarea: hay que hacerla. Si no se marca como hecha, sigue pendiente.
enum ItemKind {
  event,
  task;

  String get label => this == ItemKind.event ? 'Evento' : 'Tarea';
}

/// Una línea de la lista de comprobación de un evento.
class CheckEntry {
  final String text;
  final bool done;
  const CheckEntry(this.text, {this.done = false});

  CheckEntry copyWith({String? text, bool? done}) => CheckEntry(text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() => {'t': text, 'd': done};
  factory CheckEntry.fromJson(Map<String, Object?> m) => CheckEntry(m['t'] as String? ?? '', done: m['d'] == true);

  @override
  bool operator ==(Object other) => other is CheckEntry && other.text == text && other.done == done;
  @override
  int get hashCode => Object.hash(text, done);
}

/// Un evento o tarea apuntado por el usuario (posiblemente repetido).
class Item {
  final String id;
  final String title;
  final String notes;
  final ItemKind kind;
  final String categoryId;
  final Priority priority;
  final bool allDay;

  /// Fecha y hora de inicio (en todo el día, la hora es 00:00).
  final DateTime start;
  final Recurrence? recurrence;

  /// Si es una excepción editada de una serie ("solo esta"), id de la serie.
  final String? parentId;
  final DateTime createdAt;

  /// Año de nacimiento (cumpleaños) o de inicio (aniversarios).
  final int? sinceYear;

  /// Lista de comprobación opcional ("DNI, cargador, billetes…").
  final List<CheckEntry> checklist;

  const Item({
    required this.id,
    required this.title,
    this.notes = '',
    this.kind = ItemKind.event,
    required this.categoryId,
    required this.priority,
    this.allDay = false,
    required this.start,
    this.recurrence,
    this.parentId,
    required this.createdAt,
    this.sinceYear,
    this.checklist = const [],
  });

  bool get isRecurring => recurrence != null;

  Item copyWith({
    String? id,
    String? title,
    String? notes,
    ItemKind? kind,
    String? categoryId,
    Priority? priority,
    bool? allDay,
    DateTime? start,
    Recurrence? recurrence,
    bool clearRecurrence = false,
    String? parentId,
    bool clearParent = false,
    DateTime? createdAt,
    int? sinceYear,
    bool clearSinceYear = false,
    List<CheckEntry>? checklist,
  }) =>
      Item(
        id: id ?? this.id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        kind: kind ?? this.kind,
        categoryId: categoryId ?? this.categoryId,
        priority: priority ?? this.priority,
        allDay: allDay ?? this.allDay,
        start: start ?? this.start,
        recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
        parentId: clearParent ? null : (parentId ?? this.parentId),
        createdAt: createdAt ?? this.createdAt,
        sinceYear: clearSinceYear ? null : (sinceYear ?? this.sinceYear),
        checklist: checklist ?? this.checklist,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'notes': notes,
        'kind': kind.name,
        'category_id': categoryId,
        'priority': priority.name,
        'all_day': allDay ? 1 : 0,
        'start': start.toIso8601String(),
        'rrule': recurrence?.toRRule(start),
        'parent_id': parentId,
        'created_at': createdAt.toIso8601String(),
        'since_year': sinceYear,
        'checklist': checklist.isEmpty ? null : jsonEncode([for (final c in checklist) c.toJson()]),
      };

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        title: m['title'] as String,
        notes: (m['notes'] as String?) ?? '',
        kind: (m['kind'] as String?) == 'task' ? ItemKind.task : ItemKind.event,
        categoryId: m['category_id'] as String,
        priority: Priority.fromName(m['priority'] as String?),
        allDay: (m['all_day'] as num?) == 1,
        start: DateTime.parse(m['start'] as String),
        recurrence: Recurrence.fromRRule(m['rrule'] as String?),
        parentId: m['parent_id'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        sinceYear: (m['since_year'] as num?)?.toInt(),
        checklist: _parseChecklist(m['checklist'] as String?),
      );
}

List<CheckEntry> _parseChecklist(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [for (final e in jsonDecode(raw) as List) CheckEntry.fromJson(Map<String, Object?>.from(e as Map))];
  } catch (_) {
    return const [];
  }
}

extension ItemYears on Item {
  /// "cumple 30" en cumpleaños, "30 años" en aniversarios (solo si se repite
  /// cada año y se conoce el año de inicio).
  String? yearsLabel(DateTime at) {
    final y = sinceYear;
    if (y == null || recurrence?.frequency != Frequency.yearly) return null;
    final n = at.year - y;
    if (n <= 0) return null;
    return categoryId == Category.birthdayId ? 'cumple $n' : '$n ${n == 1 ? 'año' : 'años'}';
  }
}

/// Una aparición concreta de un [Item] en un día.
class Occurrence {
  final Item item;
  final DateTime start;
  final bool done;

  const Occurrence({required this.item, required this.start, this.done = false});

  /// Clave de la aparición: el día (`yyyy-MM-dd`).
  String get key => dateKey(start);

  /// Para eventos, la hora a la que "ocurre"; en todo el día, fin del día.
  DateTime get effectiveEnd =>
      item.allDay ? DateTime(start.year, start.month, start.day, 23, 59) : start;

  Occurrence withDone(bool value) =>
      Occurrence(item: item, start: start, done: value);

  @override
  bool operator ==(Object other) =>
      other is Occurrence && other.item.id == item.id && other.key == key;

  @override
  int get hashCode => Object.hash(item.id, key);
}
