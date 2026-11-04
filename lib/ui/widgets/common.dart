import 'package:flutter/material.dart';

import '../../models/item.dart';
import '../../models/priority.dart';

/// Icono de importancia (rayo, exclamación, punto o círculo vacío).
class PriorityIcon extends StatelessWidget {
  final Priority priority;
  final double size;
  const PriorityIcon(this.priority, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final iconSize = switch (priority) {
      Priority.normal => size * 0.5,
      Priority.none => size * 0.6,
      _ => size,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: Icon(priority.icon, size: iconSize, color: priority.color)),
    );
  }
}

/// Importancia con icono y nombre.
class PriorityLabel extends StatelessWidget {
  final Priority priority;
  const PriorityLabel(this.priority, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PriorityIcon(priority, size: 16),
      const SizedBox(width: 4),
      Text(priority.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: priority == Priority.none ? Theme.of(context).colorScheme.onSurfaceVariant : priority.color,
                fontWeight: FontWeight.w700,
              )),
    ]);
  }
}

/// Título pequeño de sección.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Color? color;
  const SectionHeader(this.title, {super.key, this.trailing, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 8),
      child: Row(children: [
        Text(title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: c, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// Texto para listas vacías.
class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Nombre de la app escrito: "lapsus" con un punto del color del tema.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'lapsus', style: TextStyle(color: scheme.onSurface)),
        TextSpan(text: '.', style: TextStyle(color: scheme.primary)),
      ]),
      style: TextStyle(
        fontFamily: 'Manrope',
        fontWeight: FontWeight.w800,
        fontSize: size,
        letterSpacing: -size * 0.04,
        height: 1,
      ),
    );
  }
}

/// Marca pequeña de color: círculo para eventos, cuadrado para tareas.
class KindMarker extends StatelessWidget {
  final ItemKind kind;
  final Color color;
  final double size;
  final bool hollow;
  const KindMarker({super.key, required this.kind, required this.color, this.size = 6, this.hollow = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hollow ? null : color,
        border: hollow ? Border.all(color: color, width: 1.2) : null,
        shape: kind == ItemKind.event ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: kind == ItemKind.task ? BorderRadius.circular(size * 0.2) : null,
      ),
    );
  }
}
