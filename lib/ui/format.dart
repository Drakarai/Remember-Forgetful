import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/dates.dart';
import '../models/recurrence.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String fmtTime(DateTime d) => DateFormat('HH:mm', 'es').format(d);
String fmtTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "Martes, 3 de noviembre"
String fmtLongDate(DateTime d) => _cap(DateFormat("EEEE, d 'de' MMMM", 'es').format(d));

/// "mar 3 nov"
String fmtShortDate(DateTime d) => DateFormat('EEE d MMM', 'es').format(d).replaceAll('.', '');

/// "Noviembre 2026"
String fmtMonthYear(DateTime d) => _cap(DateFormat('MMMM y', 'es').format(d));

/// "Hoy", "Mañana", "Ayer", "Jueves 5" o "Jue 5 nov".
String fmtRelativeDay(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = dayDiff(today, d);
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  if (diff == -1) return 'Ayer';
  if (diff > 1 && diff < 7) return _cap(DateFormat("EEEE d", 'es').format(d));
  return _cap(fmtShortDate(d));
}

String fmtAgo(DateTime d, {DateTime? now}) {
  final diff = dayDiff(d, now ?? DateTime.now());
  if (diff <= 0) return 'hoy';
  if (diff == 1) return 'ayer';
  return 'hace $diff días';
}

const weekdayShort = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const weekdayNames = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _ordinals = ['1er', '2º', '3er', '4º', '5º'];

/// Descripción en lenguaje natural de una repetición.
String describeRecurrence(Recurrence? r, DateTime start) {
  if (r == null) return 'No se repite';
  final n = r.interval;
  String base;
  switch (r.frequency) {
    case Frequency.daily:
      base = n == 1 ? 'Cada día' : 'Cada $n días';
    case Frequency.weekly:
      final days = (r.weekdays.isEmpty ? {start.weekday} : r.weekdays).toList()..sort();
      final every = n == 1 ? 'Cada semana' : 'Cada $n semanas';
      if (days.length == 7) {
        base = n == 1 ? 'Cada día' : every;
      } else if (days.length == 5 && days.every((d) => d <= 5)) {
        base = n == 1 ? 'Días laborables (L-V)' : '$every, de lunes a viernes';
      } else {
        final names = days.map((d) => weekdayNames[d - 1]).toList();
        final list = names.length == 1
            ? names.first
            : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
        base = '$every, el $list';
      }
    case Frequency.monthly:
      final every = n == 1 ? 'Cada mes' : 'Cada $n meses';
      switch (r.monthlyMode) {
        case MonthlyMode.dayOfMonth:
          base = '$every, el día ${start.day}';
        case MonthlyMode.nthWeekday:
          base = '$every, el ${_ordinals[Recurrence.nthOfMonth(start) - 1]} ${weekdayNames[start.weekday - 1]}';
        case MonthlyMode.lastWeekday:
          base = '$every, el último ${weekdayNames[start.weekday - 1]}';
      }
    case Frequency.yearly:
      final every = n == 1 ? 'Cada año' : 'Cada $n años';
      base = '$every, el ${DateFormat("d 'de' MMMM", 'es').format(start)}';
  }
  if (r.until != null) base += ' · hasta el ${DateFormat('d/M/y', 'es').format(r.until!)}';
  if (r.count != null) base += ' · ${r.count} veces';
  return base;
}
