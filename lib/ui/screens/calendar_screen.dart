import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/dates.dart';
import '../../models/item.dart';
import '../../models/priority.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/occurrence_tile.dart';

enum CalendarView { month, week }

/// Calendario con vista de mes o semana y la lista del día elegido.
class CalendarScreen extends StatefulWidget {
  final ValueNotifier<DateTime> selected;
  const CalendarScreen({super.key, required this.selected});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarView view = CalendarView.month;
  late DateTime anchor = widget.selected.value;

  DateTime get selected => widget.selected.value;

  void _select(DateTime d) => setState(() {
        widget.selected.value = dateOnly(d);
        anchor = widget.selected.value;
      });

  void _shift(int dir) => setState(() {
        anchor = view == CalendarView.month
            ? DateTime(anchor.year, anchor.month + dir, 1)
            : addDays(anchor, 7 * dir);
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());

    // Rango visible para calcular los puntos de cada día.
    final DateTime gridStart;
    final int days;
    if (view == CalendarView.month) {
      gridStart = startOfWeek(DateTime(anchor.year, anchor.month, 1));
      final last = DateTime(anchor.year, anchor.month + 1, 0);
      days = dayDiff(gridStart, addDays(startOfWeek(last), 6)) + 1;
    } else {
      gridStart = startOfWeek(anchor);
      days = 7;
    }
    final all = state.between(gridStart, addDays(gridStart, days - 1));
    final byDay = <String, List<Occurrence>>{};
    for (final o in all) {
      byDay.putIfAbsent(o.key, () => []).add(o);
    }
    final dayList = byDay[dateKey(selected)] ?? const <Occurrence>[];

    final title = view == CalendarView.month
        ? fmtMonthYear(anchor)
        : fmtWeekRange(gridStart, addDays(gridStart, 6));

    return SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: theme.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(tooltip: 'Anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
              IconButton(tooltip: 'Siguiente', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              SegmentedButton<CalendarView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: CalendarView.month, label: Text('Mes')),
                  ButtonSegment(value: CalendarView.week, label: Text('Semana')),
                ],
                selected: {view},
                onSelectionChanged: (s) => setState(() {
                  view = s.first;
                  anchor = selected;
                }),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _select(today),
                icon: const Icon(Icons.today_rounded),
                label: const Text('Hoy'),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 250) _shift(v < 0 ? 1 : -1);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                  child: Column(children: [
                    Row(children: [
                      for (final l in weekdayShort)
                        Expanded(
                          child: Center(
                            child: Text(l,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    for (var w = 0; w < days ~/ 7; w++)
                      Row(children: [
                        for (var d = 0; d < 7; d++)
                          Expanded(
                            child: _DayCell(
                              day: addDays(gridStart, w * 7 + d),
                              inMonth: view == CalendarView.week ||
                                  addDays(gridStart, w * 7 + d).month == anchor.month,
                              isToday: isSameDay(addDays(gridStart, w * 7 + d), today),
                              isSelected: isSameDay(addDays(gridStart, w * 7 + d), selected),
                              items: byDay[dateKey(addDays(gridStart, w * 7 + d))] ?? const [],
                              tall: view == CalendarView.week,
                              onTap: () => _select(addDays(gridStart, w * 7 + d)),
                            ),
                          ),
                      ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          sliver: SliverList.list(children: [
            SectionHeader(fmtLongDate(selected)),
            if (dayList.isEmpty) const EmptyNote('Nada apuntado este día.') else OccurrenceGroup(dayList),
          ]),
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool tall;
  final List<Occurrence> items;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.items,
    required this.tall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = items.where((o) => !o.done).toList()
      ..sort((a, b) => b.item.priority.weight.compareTo(a.item.priority.weight));
    final dots = pending.take(3).toList();
    final fg = isSelected
        ? scheme.onPrimary
        : (inMonth ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.3));

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        height: tall ? 64 : 50,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? scheme.primary : null,
              border: isToday && !isSelected ? Border.all(color: scheme.primary, width: 1.5) : null,
            ),
            child: Text('${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isToday && !isSelected ? scheme.primary : fg,
                  fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                  fontFeatures: tabularFigures,
                )),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 5,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final o in dots)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: o.item.priority == Priority.none ? scheme.outline : o.item.priority.color,
                  ),
                ),
            ]),
          ),
          if (tall && pending.length > 3)
            Text('+${pending.length - 3}', style: theme.textTheme.labelSmall?.copyWith(color: fg)),
        ]),
      ),
    );
  }
}
