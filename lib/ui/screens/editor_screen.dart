import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../logic/dates.dart';
import '../../models/category.dart';
import '../../models/item.dart';
import '../../models/priority.dart';
import '../../models/recurrence.dart';
import '../../state/app_state.dart';
import '../category_icons.dart';
import '../format.dart';
import '../widgets/common.dart';

/// Abre el editor para crear (sin [occurrence]) o editar.
Future<void> openEditor(BuildContext context, {Occurrence? occurrence, DateTime? day}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EditorScreen(occurrence: occurrence, day: day),
  ));
}

class EditorScreen extends StatefulWidget {
  final Occurrence? occurrence;
  final DateTime? day;
  const EditorScreen({super.key, this.occurrence, this.day});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final AppState state = context.read<AppState>();
  late final Item original;
  late final bool isNew;
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _titleFocus = FocusNode();
  final _scroll = ScrollController();

  late ItemKind kind;
  late String categoryId;
  late Priority priority;
  bool priorityTouched = false;
  late bool allDay;
  late DateTime date;
  late TimeOfDay time;
  Recurrence? recurrence;

  /// Se activa al pulsar Guardar con algo mal: a partir de ahí se marcan en
  /// rojo los campos que faltan.
  bool _showErrors = false;
  bool _saving = false;
  late final String _initialSignature;

  @override
  void initState() {
    super.initState();
    final o = widget.occurrence;
    isNew = o == null;
    original = o?.item ?? state.draft(day: widget.day);
    final start = o?.start ?? original.start;
    _title.text = original.title;
    _notes.text = original.notes;
    kind = original.kind;
    categoryId = original.categoryId;
    priority = original.priority;
    priorityTouched = !isNew;
    allDay = original.allDay;
    date = dateOnly(start);
    time = TimeOfDay.fromDateTime(start);
    recurrence = original.recurrence;
    _initialSignature = _signature;
    _title.addListener(() {
      if (_showErrors) setState(() {});
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _titleFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime get start => allDay ? date : DateTime(date.year, date.month, date.day, time.hour, time.minute);

  String get _signature => [
        _title.text.trim(),
        _notes.text.trim(),
        kind.name,
        categoryId,
        priority.name,
        allDay,
        start.toIso8601String(),
        recurrence?.toRRule(start),
      ].join('|');

  bool get _dirty => _signature != _initialSignature;

  // --- Validación ------------------------------------------------------------

  bool get _titleMissing => _title.text.trim().isEmpty;

  bool get _recurrenceEndsBeforeStart {
    final until = recurrence?.until;
    return until != null && dateOnly(until).isBefore(date);
  }

  List<String> get _problems => [
        if (_titleMissing) 'Falta el título',
        if (_recurrenceEndsBeforeStart) 'La repetición termina antes de la fecha de inicio',
      ];

  bool get _inPast {
    final now = DateTime.now();
    return allDay ? date.isBefore(dateOnly(now)) : start.isBefore(now);
  }

  void _selectCategory(Category c) {
    setState(() {
      categoryId = c.id;
      if (!priorityTouched) priority = c.defaultPriority;
      if (isNew && c.id == Category.birthdayId) {
        allDay = true;
        kind = ItemKind.event;
        recurrence ??= const Recurrence(frequency: Frequency.yearly);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_problems.isNotEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _showErrors = true);
      if (_scroll.hasClients) {
        await _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
      if (_titleMissing) _titleFocus.requestFocus();
      return;
    }
    final edited = original.copyWith(
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      kind: kind,
      categoryId: categoryId,
      priority: priority,
      allDay: allDay,
      start: start,
      recurrence: recurrence,
      clearRecurrence: recurrence == null,
    );
    var scope = EditScope.all;
    final o = widget.occurrence;
    if (!isNew && original.isRecurring) {
      final s = await askScope(context, question: 'Se repite. ¿Qué quieres cambiar?');
      if (s == null) return;
      scope = s;
    }
    setState(() => _saving = true);
    try {
      await state.saveItem(edited, original: isNew ? null : original, occurrence: o, scope: scope);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) await _showError('No se ha podido guardar', e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showError(String title, Object e) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(Icons.error_outline_rounded, color: Theme.of(c).colorScheme.error),
          title: Text(title),
          content: Text('$e'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
        ),
      );

  Future<void> _delete() async {
    final o = widget.occurrence!;
    EditScope scope = EditScope.all;
    if (original.isRecurring) {
      final s = await askScope(context, question: 'Se repite. ¿Qué quieres borrar?');
      if (s == null) return;
      scope = s;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Borrar?'),
          content: Text('Se borrará "${original.title}".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Borrar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await state.deleteOccurrence(o, scope);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) await _showError('No se ha podido borrar', e);
    }
  }

  /// Pregunta antes de salir si hay cambios sin guardar.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('Lo que has escrito no se guardará.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir editando')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descartar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _close() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es'),
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: time,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) setState(() => time = t);
  }

  Future<void> _pickRecurrence() async {
    final r = await showRecurrencePicker(context, current: recurrence, start: start);
    if (r != null) setState(() => recurrence = r.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = scheme.error;
    final today = dateOnly(DateTime.now());
    final cats = context.watch<AppState>().categories;
    final problems = _showErrors ? _problems : const <String>[];
    final titleError = _showErrors && _titleMissing;
    final recurrenceError = _showErrors && _recurrenceEndsBeforeStart;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded),
            onPressed: _close,
          ),
          title: Text(isNew ? 'Nuevo' : 'Editar'),
          actions: [
            if (!isNew)
              IconButton(
                tooltip: 'Borrar',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _saving ? null : _delete,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
        body: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            if (problems.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: error),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, color: error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Revisa lo marcado en rojo',
                          style: theme.textTheme.titleSmall?.copyWith(color: error)),
                      for (final p in problems) Text('• $p', style: theme.textTheme.bodyMedium),
                    ]),
                  ),
                ]),
              ),
            SegmentedButton<ItemKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ItemKind.event, label: Text('Evento'), icon: Icon(Icons.event_rounded)),
                ButtonSegment(value: ItemKind.task, label: Text('Tarea'), icon: Icon(Icons.task_alt_rounded)),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setState(() => kind = s.first),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                kind == ItemKind.event
                    ? 'Citas, cumpleaños, reuniones…'
                    : 'Si no la marcas como hecha, sigue apareciendo los días siguientes.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            SectionHeader('Título *', color: titleError ? error : null),
            TextField(
              controller: _title,
              focusNode: _titleFocus,
              autofocus: isNew,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: theme.textTheme.titleLarge,
              decoration: InputDecoration(
                hintText: 'Ej.: Llamar al dentista',
                errorText: titleError ? 'Escribe un título' : null,
              ),
              onSubmitted: (_) => _save(),
            ),

            const SectionHeader('Categoría'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in cats)
                ChoiceChip(
                  avatar: Icon(categoryIcon(c.icon), size: 18, color: Color(c.color)),
                  label: Text(c.name),
                  selected: categoryId == c.id,
                  onSelected: (_) => _selectCategory(c),
                  showCheckmark: false,
                ),
            ]),

            const SectionHeader('Importancia'),
            _PriorityPicker(
              value: priority,
              onChanged: (p) => setState(() {
                priority = p;
                priorityTouched = true;
              }),
            ),

            SectionHeader('Cuándo', color: recurrenceError ? error : null),
            Card(
              shape: recurrenceError
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: error))
                  : null,
              child: Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    ChoiceChip(
                      label: const Text('Hoy'),
                      selected: isSameDay(date, today),
                      onSelected: (_) => setState(() => date = today),
                    ),
                    ChoiceChip(
                      label: const Text('Mañana'),
                      selected: isSameDay(date, addDays(today, 1)),
                      onSelected: (_) => setState(() => date = addDays(today, 1)),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(fmtLongDate(date)),
                      onPressed: _pickDate,
                    ),
                  ]),
                ),
                if (_inPast && (isNew || recurrence == null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Priority.important.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Esta fecha ya ha pasado: no habrá avisos.',
                            style: theme.textTheme.bodySmall?.copyWith(color: Priority.important.color)),
                      ),
                    ]),
                  ),
                SwitchListTile(
                  title: const Text('Todo el día'),
                  subtitle: allDay ? Text('Aviso a las ${fmtTimeOfDay(state.settings.allDayTime)}') : null,
                  value: allDay,
                  onChanged: (v) => setState(() => allDay = v),
                ),
                if (!allDay)
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Hora'),
                    trailing: Text(fmtTimeOfDay(time), style: theme.textTheme.titleMedium),
                    onTap: _pickTime,
                  ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.repeat_rounded, color: recurrenceError ? error : null),
                  title: Text('Repetir', style: TextStyle(color: recurrenceError ? error : null)),
                  subtitle: Text(
                    recurrenceError
                        ? 'Termina antes de la fecha de inicio'
                        : describeRecurrence(recurrence, start),
                    style: TextStyle(color: recurrenceError ? error : null),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickRecurrence,
                ),
              ]),
            ),

            const SectionHeader('Notas'),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Opcional'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityPicker extends StatelessWidget {
  final Priority value;
  final ValueChanged<Priority> onChanged;
  const _PriorityPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Row(children: [
        for (final p in Priority.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _PriorityOption(priority: p, selected: p == value, onTap: () {
                HapticFeedback.selectionClick();
                onChanged(p);
              }),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(value.description,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    ]);
  }
}

class _PriorityOption extends StatelessWidget {
  final Priority priority;
  final bool selected;
  final VoidCallback onTap;
  const _PriorityOption({required this.priority, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = priority.color;
    return Material(
      color: selected ? c.withValues(alpha: 0.10) : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? c : theme.colorScheme.outlineVariant, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            PriorityIcon(priority, size: 22),
            const SizedBox(height: 4),
            Text(priority.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected && priority != Priority.none ? c : null,
                )),
          ]),
        ),
      ),
    );
  }
}

/// Pregunta a qué apariciones de una serie afecta un cambio.
Future<EditScope?> askScope(BuildContext context, {required String question}) {
  return showModalBottomSheet<EditScope>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(question, style: Theme.of(c).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.looks_one_outlined),
          title: const Text('Solo esta vez'),
          onTap: () => Navigator.pop(c, EditScope.single),
        ),
        ListTile(
          leading: const Icon(Icons.east_rounded),
          title: const Text('Esta y las siguientes'),
          onTap: () => Navigator.pop(c, EditScope.following),
        ),
        ListTile(
          leading: const Icon(Icons.all_inclusive_rounded),
          title: const Text('Todas'),
          onTap: () => Navigator.pop(c, EditScope.all),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Envoltorio para distinguir "no se repite" (value null) de "cancelado".
class RecurrenceChoice {
  final Recurrence? value;
  const RecurrenceChoice(this.value);
}

Future<RecurrenceChoice?> showRecurrencePicker(BuildContext context,
    {required Recurrence? current, required DateTime start}) {
  final options = <(String, Recurrence?)>[
    ('No se repite', null),
    ('Cada día', const Recurrence(frequency: Frequency.daily)),
    ('Cada semana', const Recurrence(frequency: Frequency.weekly)),
    ('Cada mes', const Recurrence(frequency: Frequency.monthly)),
    ('Cada año', const Recurrence(frequency: Frequency.yearly)),
  ];
  final isCustom = current != null && !current.isSimple;
  return showModalBottomSheet<RecurrenceChoice>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (label, r) in options)
          ListTile(
            title: Text(label),
            subtitle: r == null ? null : Text(describeRecurrence(r, start)),
            trailing: !isCustom && current == r ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(c, RecurrenceChoice(r)),
          ),
        ListTile(
          title: const Text('Personalizado…'),
          subtitle: isCustom ? Text(describeRecurrence(current, start)) : null,
          trailing: isCustom ? const Icon(Icons.check_rounded) : const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final r = await Navigator.of(c).push<Recurrence>(MaterialPageRoute(
              builder: (_) => CustomRecurrenceScreen(initial: current, start: start),
            ));
            if (r != null && c.mounted) Navigator.pop(c, RecurrenceChoice(r));
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Pantalla de repetición personalizada.
class CustomRecurrenceScreen extends StatefulWidget {
  final Recurrence? initial;
  final DateTime start;
  const CustomRecurrenceScreen({super.key, this.initial, required this.start});

  @override
  State<CustomRecurrenceScreen> createState() => _CustomRecurrenceScreenState();
}

enum _End { never, until, count }

class _CustomRecurrenceScreenState extends State<CustomRecurrenceScreen> {
  late Frequency freq;
  late int interval;
  late Set<int> weekdays;
  late MonthlyMode monthlyMode;
  late _End end;
  late DateTime until;
  late int count;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    freq = r?.frequency ?? Frequency.weekly;
    interval = r?.interval ?? 1;
    weekdays = {...?r?.weekdays};
    if (weekdays.isEmpty) weekdays = {widget.start.weekday};
    monthlyMode = r?.monthlyMode ?? MonthlyMode.dayOfMonth;
    end = r?.until != null ? _End.until : (r?.count != null ? _End.count : _End.never);
    until = dateOnly(r?.until ?? addDays(widget.start, 30));
    count = r?.count ?? 10;
  }

  Recurrence get result => Recurrence(
        frequency: freq,
        interval: interval,
        weekdays: freq == Frequency.weekly ? weekdays : const {},
        monthlyMode: freq == Frequency.monthly ? monthlyMode : MonthlyMode.dayOfMonth,
        until: end == _End.until ? until : null,
        count: end == _End.count ? count : null,
      );

  String _unit(Frequency f, int n) => switch (f) {
        Frequency.daily => n == 1 ? 'día' : 'días',
        Frequency.weekly => n == 1 ? 'semana' : 'semanas',
        Frequency.monthly => n == 1 ? 'mes' : 'meses',
        Frequency.yearly => n == 1 ? 'año' : 'años',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.start;
    final ord = ['1er', '2º', '3er', '4º', '5º'][Recurrence.nthOfMonth(s) - 1];
    final wd = weekdayNames[s.weekday - 1];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repetición personalizada'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: () => Navigator.pop(context, result), child: const Text('Listo')),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Text('Cada'),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: interval > 1 ? () => setState(() => interval--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 36,
                child: Text('$interval', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              ),
              IconButton.filledTonal(
                onPressed: interval < 99 ? () => setState(() => interval++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<Frequency>(
                  value: freq,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final f in Frequency.values)
                      DropdownMenuItem(value: f, child: Text(_unit(f, interval))),
                  ],
                  onChanged: (f) => setState(() => freq = f!),
                ),
              ),
            ]),
          ),
        ),
        if (freq == Frequency.weekly) ...[
          const SectionHeader('Qué días'),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var d = 1; d <= 7; d++)
              _DayToggle(
                label: weekdayShort[d - 1],
                selected: weekdays.contains(d),
                onTap: () => setState(() {
                  if (weekdays.contains(d)) {
                    if (weekdays.length > 1) weekdays.remove(d);
                  } else {
                    weekdays.add(d);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ActionChip(label: const Text('Laborables'), onPressed: () => setState(() => weekdays = {1, 2, 3, 4, 5})),
            ActionChip(label: const Text('Fin de semana'), onPressed: () => setState(() => weekdays = {6, 7})),
            ActionChip(label: const Text('Todos'), onPressed: () => setState(() => weekdays = {1, 2, 3, 4, 5, 6, 7})),
          ]),
        ],
        if (freq == Frequency.monthly) ...[
          const SectionHeader('Qué día del mes'),
          Card(
            child: RadioGroup<MonthlyMode>(
              groupValue: monthlyMode,
              onChanged: (v) => setState(() => monthlyMode = v!),
              child: Column(children: [
                RadioListTile(
                  value: MonthlyMode.dayOfMonth,
                  title: Text('El día ${s.day}'),
                  subtitle: s.day > 28 ? const Text('En meses más cortos, el último día') : null,
                ),
                RadioListTile(value: MonthlyMode.nthWeekday, title: Text('El $ord $wd')),
                if (Recurrence.isLastWeekdayOfMonth(s))
                  RadioListTile(value: MonthlyMode.lastWeekday, title: Text('El último $wd')),
              ]),
            ),
          ),
        ],
        const SectionHeader('Termina'),
        Card(
          child: RadioGroup<_End>(
            groupValue: end,
            onChanged: (v) => setState(() => end = v!),
            child: Column(children: [
              const RadioListTile(value: _End.never, title: Text('Nunca')),
              RadioListTile(
                value: _End.until,
                title: const Text('El día'),
                secondary: TextButton(
                  onPressed: end != _End.until
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: until.isBefore(dateOnly(s)) ? dateOnly(s) : until,
                            firstDate: dateOnly(s),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => until = d);
                        },
                  child: Text(fmtShortDate(until)),
                ),
              ),
              RadioListTile(
                value: _End.count,
                title: const Text('Después de'),
                secondary: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    onPressed: end == _End.count && count > 1 ? () => setState(() => count--) : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Text('$count veces'),
                  IconButton(
                    onPressed: end == _End.count ? () => setState(() => count++) : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Icon(Icons.repeat_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(describeRecurrence(result, s), style: theme.textTheme.bodyMedium)),
          ]),
        ),
      ]),
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : scheme.surface,
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w800, color: selected ? scheme.onPrimary : scheme.onSurface)),
      ),
    );
  }
}
