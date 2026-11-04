import 'priority.dart';

/// Categoría de evento con su importancia por defecto. El usuario puede
/// crear, renombrar, borrar y cambiar la importancia por defecto.
class Category {
  final String id;
  final String name;
  final String icon;
  final int color;
  final Priority defaultPriority;
  final int sortOrder;

  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.defaultPriority,
    this.sortOrder = 0,
  });

  /// "Otros" no se puede borrar: es donde van los eventos de las categorías
  /// que se eliminan.
  static const otherId = 'other';
  static const birthdayId = 'birthday';

  bool get isDeletable => id != otherId;

  Category copyWith({
    String? name,
    String? icon,
    int? color,
    Priority? defaultPriority,
    int? sortOrder,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        defaultPriority: defaultPriority ?? this.defaultPriority,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'default_priority': defaultPriority.name,
        'sort_order': sortOrder,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        icon: (m['icon'] as String?) ?? 'note',
        color: (m['color'] as num).toInt(),
        defaultPriority: Priority.fromName(m['default_priority'] as String?),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );

  /// Categorías con las que arranca la app.
  static const defaults = <Category>[
    Category(id: 'health', name: 'Salud', icon: 'medical', color: 0xFFE5484D, defaultPriority: Priority.critical, sortOrder: 0),
    Category(id: 'payments', name: 'Pagos y trámites', icon: 'card', color: 0xFF8E4EC6, defaultPriority: Priority.important, sortOrder: 1),
    Category(id: birthdayId, name: 'Cumpleaños', icon: 'cake', color: 0xFFE93D82, defaultPriority: Priority.important, sortOrder: 2),
    Category(id: 'work', name: 'Trabajo y estudios', icon: 'work', color: 0xFF3E63DD, defaultPriority: Priority.important, sortOrder: 3),
    Category(id: 'home', name: 'Casa', icon: 'home', color: 0xFF30A46C, defaultPriority: Priority.normal, sortOrder: 4),
    Category(id: 'social', name: 'Social y planes', icon: 'people', color: 0xFFF76B15, defaultPriority: Priority.normal, sortOrder: 5),
    Category(id: otherId, name: 'Otros', icon: 'note', color: 0xFF8B8D98, defaultPriority: Priority.normal, sortOrder: 99),
  ];

  static Category? defaultFor(String id) {
    for (final c in defaults) {
      if (c.id == id) return c;
    }
    return null;
  }
}
