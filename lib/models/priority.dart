import 'package:flutter/material.dart';

/// Nivel de importancia de un evento o tarea.
///
/// El nivel no es solo un color: decide cómo de insistente es la app
/// a la hora de avisar (ver `NotificationPlanner`).
enum Priority {
  critical,
  important,
  normal,
  none;

  String get label => switch (this) {
        Priority.critical => 'Crítico',
        Priority.important => 'Importante',
        Priority.normal => 'Normal',
        Priority.none => 'Sin aviso',
      };

  String get description => switch (this) {
        Priority.critical => 'Aviso el día antes, 1 h antes y a la hora, con sonido de alarma. '
            'Se repite hasta que lo marques.',
        Priority.important => 'Aviso 1 h antes y a la hora. En tareas, un recordatorio más si no está hecha.',
        Priority.normal => 'Un aviso a la hora.',
        Priority.none => 'Solo aparece en la agenda.',
      };

  IconData get icon => switch (this) {
        Priority.critical => Icons.bolt_rounded,
        Priority.important => Icons.priority_high_rounded,
        Priority.normal => Icons.circle,
        Priority.none => Icons.circle_outlined,
      };

  /// Los colores de importancia son fijos en todos los temas para que
  /// siempre signifiquen lo mismo. Además se acompañan siempre de un icono
  /// para que no dependan solo del color (daltonismo).
  Color get color => switch (this) {
        Priority.critical => const Color(0xFFE5484D),
        Priority.important => const Color(0xFFF2A516),
        Priority.normal => const Color(0xFF3E8EF7),
        Priority.none => const Color(0xFF8B8D98),
      };

  /// Mayor número = más importante (útil para ordenar).
  int get weight => switch (this) {
        Priority.critical => 3,
        Priority.important => 2,
        Priority.normal => 1,
        Priority.none => 0,
      };

  static Priority fromName(String? name) => Priority.values.firstWhere(
        (p) => p.name == name,
        orElse: () => Priority.normal,
      );
}
