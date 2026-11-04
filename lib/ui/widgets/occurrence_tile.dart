import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../logic/dates.dart';
import '../../models/item.dart';
import '../../models/priority.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../category_icons.dart';
import '../format.dart';
import '../screens/editor_screen.dart';

/// Lista de eventos agrupados en un mismo bloque.
class OccurrenceGroup extends StatelessWidget {
  final List<Occurrence> items;
  final String? Function(Occurrence o)? note;
  final bool showDate;

  const OccurrenceGroup(this.items, {super.key, this.note, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(indent: 72),
          OccurrenceTile(items[i], note: note?.call(items[i]), showDate: showDate),
        ],
      ]),
    );
  }
}

/// Una fila: hora, marca de importancia, título y botón de hecho.
class OccurrenceTile extends StatelessWidget {
  final Occurrence occurrence;
  final String? note;
  final bool showDate;

  const OccurrenceTile(this.occurrence, {super.key, this.note, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = occurrence;
    final item = o.item;
    final category = context.read<AppState>().categoryOf(item.categoryId);
    final past = item.kind == ItemKind.event && o.effectiveEnd.isBefore(DateTime.now());
    final faded = o.done || past;
    final muted = scheme.onSurfaceVariant;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(color: muted);

    final checked = item.checklist.where((c) => c.done).length;
    final meta = [
      if (showDate) fmtRelativeDay(o.start),
      category.name,
      ?item.yearsLabel(o.start),
      ?note,
    ].join(' · ');

    final row = InkWell(
      onTap: () => openEditor(context, occurrence: o),
      child: Opacity(
        opacity: faded ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(children: [
            SizedBox(
              width: 46,
              child: item.allDay
                  ? Text('todo\nel día', style: metaStyle?.copyWith(height: 1.15, fontWeight: FontWeight.w600))
                  : Text(fmtTime(o.start),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      )),
            ),
            Container(
              width: 3,
              height: 36,
              margin: const EdgeInsets.only(left: 6, right: 12),
              decoration: BoxDecoration(
                color: Color(category.color),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (item.priority == Priority.critical || item.priority == Priority.important)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Icon(item.priority.icon, size: 18, color: item.priority.color),
                    ),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: o.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(categoryIcon(category.icon), size: 14, color: Color(category.color)),
                  const SizedBox(width: 4),
                  Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle)),
                  if (item.checklist.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.checklist_rounded, size: 14, color: muted),
                    const SizedBox(width: 2),
                    Text('$checked/${item.checklist.length}', style: metaStyle),
                  ],
                  if (item.isRecurring || item.parentId != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.repeat_rounded, size: 14, color: muted),
                  ],
                ]),
              ]),
            ),
            _DoneButton(occurrence: o),
          ]),
        ),
      ),
    );

    // Deslizar: a la derecha marca como hecho; a la izquierda lo pasa a otro
    // día (a hoy si estaba atrasado; si no, al día siguiente).
    final today = dateOnly(DateTime.now());
    final day = dateOnly(o.start);
    final target = day.isBefore(today) ? today : addDays(day, 1);
    final moveLabel = day.isBefore(today) ? 'A hoy' : (isSameDay(day, today) ? 'A mañana' : '+1 día');
    return Dismissible(
      key: ValueKey('${item.id}|${o.key}'),
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: scheme.primary,
        icon: o.done ? Icons.undo_rounded : Icons.check_rounded,
        label: o.done ? 'Desmarcar' : 'Hecho',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: Priority.important.color,
        icon: Icons.east_rounded,
        label: moveLabel,
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          await toggleDoneWithUndo(context, o);
        } else {
          await moveWithUndo(context, o, target);
        }
        // La lista se actualiza sola: la fila no tiene que desaparecer.
        return false;
      },
      child: row,
    );
  }
}

/// Marca o desmarca como hecho y ofrece deshacerlo.
Future<void> toggleDoneWithUndo(BuildContext context, Occurrence o) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final nowDone = !o.done;
  await state.setDone(o, nowDone);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(nowDone ? 'Hecho: ${o.item.title}' : 'Marcado como pendiente'),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => state.setDone(o.withDone(nowDone), !nowDone)),
    ));
}

/// Pasa una aparición a otro día y ofrece deshacerlo.
Future<void> moveWithUndo(BuildContext context, Occurrence o, DateTime day) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final undo = await state.moveOccurrence(o, day);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('${o.item.title} → ${fmtRelativeDay(day).toLowerCase()}'),
      action: SnackBarAction(label: 'Deshacer', onPressed: undo),
    ));
}

class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;
  const _SwipeBackground({required this.alignment, required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    final content = [
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ];
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: left ? content : content.reversed.toList(),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  final Occurrence occurrence;
  const _DoneButton({required this.occurrence});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = occurrence.done;
    final isTask = occurrence.item.kind == ItemKind.task;
    return IconButton(
      tooltip: done ? 'Marcar como pendiente' : 'Marcar como hecho',
      onPressed: () {
        HapticFeedback.lightImpact();
        toggleDoneWithUndo(context, occurrence);
      },
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: done
            ? Icon(isTask ? Icons.check_box_rounded : Icons.check_circle_rounded,
                key: const ValueKey(1), color: scheme.primary, size: 26)
            : Icon(isTask ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded,
                key: const ValueKey(0), color: scheme.outline, size: 26),
      ),
    );
  }
}
