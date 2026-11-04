import '../logic/dates.dart';

enum Frequency { daily, weekly, monthly, yearly }

/// Cómo se repite un evento mensual.
enum MonthlyMode {
  /// El mismo número de día (p. ej. el día 15). Si el mes no tiene ese día
  /// (31 en abril), se usa el último día del mes.
  dayOfMonth,

  /// El mismo "n-ésimo día de la semana" (p. ej. el 3er martes).
  nthWeekday,

  /// El último día de la semana del mes (p. ej. el último viernes).
  lastWeekday,
}

/// Regla de repetición. Se guarda como una cadena RRULE (RFC 5545), el
/// mismo formato que usan Google Calendar o Apple, para poder exportarla
/// en el futuro.
class Recurrence {
  final Frequency frequency;
  final int interval;

  /// Días de la semana (1 = lunes ... 7 = domingo). Solo para semanal.
  /// Vacío = el mismo día de la semana que la fecha de inicio.
  final Set<int> weekdays;
  final MonthlyMode monthlyMode;

  /// Último día (incluido) en el que puede ocurrir.
  final DateTime? until;

  /// Número total de veces.
  final int? count;

  const Recurrence({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const {},
    this.monthlyMode = MonthlyMode.dayOfMonth,
    this.until,
    this.count,
  });

  Recurrence copyWith({
    Frequency? frequency,
    int? interval,
    Set<int>? weekdays,
    MonthlyMode? monthlyMode,
    DateTime? until,
    bool clearUntil = false,
    int? count,
    bool clearCount = false,
  }) =>
      Recurrence(
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        monthlyMode: monthlyMode ?? this.monthlyMode,
        until: clearUntil ? null : (until ?? this.until),
        count: clearCount ? null : (count ?? this.count),
      );

  /// ¿Es una de las opciones simples (cada día/semana/mes/año sin extras)?
  bool get isSimple =>
      interval == 1 &&
      weekdays.isEmpty &&
      monthlyMode == MonthlyMode.dayOfMonth &&
      until == null &&
      count == null;

  // ---------------------------------------------------------------------------
  // RRULE
  // ---------------------------------------------------------------------------

  static const _dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// Convierte a RRULE. Para los modos mensuales "n-ésimo" se necesita la
  /// fecha de inicio para saber qué día de la semana es.
  String toRRule(DateTime start) {
    final parts = <String>['FREQ=${frequency.name.toUpperCase()}'];
    if (interval != 1) parts.add('INTERVAL=$interval');
    if (frequency == Frequency.weekly && weekdays.isNotEmpty) {
      final sorted = weekdays.toList()..sort();
      parts.add('BYDAY=${sorted.map((d) => _dayCodes[d - 1]).join(',')}');
    }
    if (frequency == Frequency.monthly) {
      final code = _dayCodes[start.weekday - 1];
      switch (monthlyMode) {
        case MonthlyMode.dayOfMonth:
          break;
        case MonthlyMode.nthWeekday:
          parts.add('BYDAY=${nthOfMonth(start)}$code');
        case MonthlyMode.lastWeekday:
          parts.add('BYDAY=-1$code');
      }
    }
    if (until != null) {
      parts.add('UNTIL=${dateKey(until!).replaceAll('-', '')}');
    }
    if (count != null) parts.add('COUNT=$count');
    return parts.join(';');
  }

  static Recurrence? fromRRule(String? rule) {
    if (rule == null || rule.trim().isEmpty) return null;
    final map = <String, String>{};
    for (final part in rule.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) map[part.substring(0, i).toUpperCase()] = part.substring(i + 1);
    }
    final freq = Frequency.values.firstWhere(
      (f) => f.name.toUpperCase() == map['FREQ'],
      orElse: () => Frequency.daily,
    );
    var weekdays = <int>{};
    var monthlyMode = MonthlyMode.dayOfMonth;
    final byDay = map['BYDAY'];
    if (byDay != null && byDay.isNotEmpty) {
      if (freq == Frequency.weekly) {
        weekdays = byDay
            .split(',')
            .map((c) => _dayCodes.indexOf(c.trim()) + 1)
            .where((d) => d > 0)
            .toSet();
      } else if (freq == Frequency.monthly) {
        monthlyMode = byDay.startsWith('-1')
            ? MonthlyMode.lastWeekday
            : MonthlyMode.nthWeekday;
      }
    }
    DateTime? until;
    final u = map['UNTIL'];
    if (u != null && u.length >= 8) {
      until = DateTime(
        int.parse(u.substring(0, 4)),
        int.parse(u.substring(4, 6)),
        int.parse(u.substring(6, 8)),
      );
    }
    return Recurrence(
      frequency: freq,
      interval: int.tryParse(map['INTERVAL'] ?? '') ?? 1,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      until: until,
      count: int.tryParse(map['COUNT'] ?? ''),
    );
  }

  /// En qué semana del mes cae [d] (1..5).
  static int nthOfMonth(DateTime d) => ((d.day - 1) ~/ 7) + 1;

  /// ¿Es [d] el último de su día de la semana en el mes?
  static bool isLastWeekdayOfMonth(DateTime d) =>
      d.day + 7 > daysInMonth(d.year, d.month);

  @override
  bool operator ==(Object other) =>
      other is Recurrence &&
      other.frequency == frequency &&
      other.interval == interval &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.monthlyMode == monthlyMode &&
      other.until == until &&
      other.count == count;

  @override
  int get hashCode => Object.hash(frequency, interval,
      Object.hashAllUnordered(weekdays), monthlyMode, until, count);
}
