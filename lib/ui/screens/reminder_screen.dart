import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item.dart';
import '../../models/priority.dart';
import '../../state/app_state.dart';
import '../category_icons.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'editor_screen.dart';

/// Se abre al tocar una notificación (o a pantalla completa en las
/// críticas): muestra el recordatorio y deja marcarlo o posponerlo.
class ReminderScreen extends StatelessWidget {
  final String itemId;
  final String dayKey;
  const ReminderScreen({super.key, required this.itemId, required this.dayKey});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = state.findOccurrence(itemId, dayKey);

    if (o == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: EmptyNote('Este recordatorio ya no existe: se ha borrado o cambiado de fecha.'),
        ),
      );
    }

    final item = o.item;
    final category = state.categoryOf(item.categoryId);
    final years = item.yearsLabel(o.start);
    final when = [
      fmtRelativeDay(o.start),
      item.allDay ? 'todo el día' : fmtTime(o.start),
      ?years,
    ].join(' · ');

    Future<void> act(Future<void> Function() f, String message) async {
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      await f();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      if (nav.canPop()) nav.pop();
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => EditorScreen(occurrence: o),
            )),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PriorityLabel(item.priority),
            const SizedBox(height: 12),
            Text(item.title, style: theme.textTheme.displaySmall?.copyWith(fontSize: 34)),
            const SizedBox(height: 12),
            Text(when, style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Row(children: [
              Icon(categoryIcon(category.icon), size: 18, color: Color(category.color)),
              const SizedBox(width: 6),
              Text(category.name, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
                if (item.notes.isNotEmpty) Text(item.notes, style: theme.textTheme.bodyLarge),
                if (item.checklist.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < item.checklist.length; i++)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: item.checklist[i].done,
                      title: Text(item.checklist[i].text,
                          style: TextStyle(
                            decoration: item.checklist[i].done ? TextDecoration.lineThrough : null,
                            color: item.checklist[i].done ? scheme.onSurfaceVariant : null,
                          )),
                      onChanged: (v) {
                        final list = [...item.checklist];
                        list[i] = list[i].copyWith(done: v ?? false);
                        state.updateChecklist(item, list);
                      },
                    ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            if (o.done)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () => act(() => state.setDone(o, false), 'Marcado como pendiente'),
                  child: const Text('Hecho ✓  ·  Desmarcar'),
                ),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton(
                  style: item.priority == Priority.critical
                      ? FilledButton.styleFrom(backgroundColor: Priority.critical.color, foregroundColor: Colors.white)
                      : null,
                  onPressed: () => act(() => state.setDone(o, true), 'Hecho'),
                  child: Text(item.kind == ItemKind.task ? 'Hecho' : 'Entendido',
                      style: const TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => act(() => state.snooze(o, const Duration(minutes: 10)), 'Te aviso en 10 minutos'),
                      child: const Text('En 10 min'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => act(() => state.snooze(o, const Duration(hours: 1)), 'Te aviso en 1 hora'),
                      child: const Text('En 1 hora'),
                    ),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
