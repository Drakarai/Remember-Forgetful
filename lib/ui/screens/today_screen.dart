import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../logic/dates.dart';
import '../../models/item.dart';
import '../../models/priority.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/occurrence_tile.dart';
import 'permissions_screen.dart';

class TodayScreen extends StatelessWidget {
  final PermissionStatusReport? permissions;
  const TodayScreen({super.key, this.permissions});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = dateOnly(now);
    final overdue = state.overdue(today);
    final todayList = state.onDay(today);
    final upcoming = state.between(addDays(today, 1), addDays(today, 7));
    // Pendiente: tareas sin hacer y eventos que aún no han pasado.
    final pending = todayList
        .where((o) => !o.done && (o.item.kind == ItemKind.task || o.effectiveEnd.isAfter(now)))
        .length;

    final status = [
      if (todayList.isEmpty)
        'Nada para hoy'
      else if (pending == 0)
        'Nada pendiente'
      else
        '$pending pendiente${pending == 1 ? '' : 's'}',
      if (overdue.isNotEmpty) '${overdue.length} de días anteriores',
    ].join(' · ');

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 110), children: [
        Text(DateFormat('EEEE', 'es').format(now).toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.4)),
        const SizedBox(height: 4),
        Text(DateFormat("d 'de' MMMM", 'es').format(now), style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(status, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (permissions != null && !permissions!.allGood) ...[
          const SizedBox(height: 16),
          _PermissionBanner(report: permissions!),
        ],
        if (overdue.isNotEmpty) ...[
          SectionHeader('Sin hacer', color: Priority.important.color),
          OccurrenceGroup(overdue, note: (o) => fmtAgo(o.start)),
        ],
        const SectionHeader('Hoy'),
        if (todayList.isEmpty)
          const EmptyNote('No hay nada apuntado. Usa el botón + para añadir algo.')
        else
          OccurrenceGroup(todayList),
        if (upcoming.isNotEmpty) ...[
          const SectionHeader('Próximos 7 días'),
          ..._byDay(context, upcoming),
        ],
      ]),
    );
  }

  List<Widget> _byDay(BuildContext context, List<Occurrence> list) {
    final theme = Theme.of(context);
    final groups = <String, List<Occurrence>>{};
    for (final o in list) {
      groups.putIfAbsent(o.key, () => []).add(o);
    }
    return [
      for (final g in groups.values) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
          child: Text(fmtRelativeDay(g.first.start), style: theme.textTheme.titleSmall),
        ),
        OccurrenceGroup(g),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class _PermissionBanner extends StatelessWidget {
  final PermissionStatusReport report;
  const _PermissionBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Priority.critical.color;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c)),
      child: ListTile(
        leading: Icon(Icons.notifications_off_outlined, color: c),
        title: Text(!report.notifications ? 'Notificaciones desactivadas' : 'Faltan permisos',
            style: theme.textTheme.titleSmall),
        subtitle: const Text('Los avisos podrían no llegar. Toca para revisarlo.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsScreen())),
      ),
    );
  }
}
