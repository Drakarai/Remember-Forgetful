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
    final when = item.allDay ? '${fmtRelativeDay(o.start)} · todo el día' : '${fmtRelativeDay(o.start)} · ${fmtTime(o.start)}';

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
            if (item.notes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(child: Text(item.notes, style: theme.textTheme.bodyLarge)),
              ),
            ] else
              const Spacer(),
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
