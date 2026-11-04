/// Utilidades de fechas. Todo se maneja en hora local del dispositivo.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Clave estable de un día: `yyyy-MM-dd`.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Suma días respetando cambios de hora (horario de verano).
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

/// Diferencia en días naturales entre dos fechas (b - a).
int dayDiff(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// Lunes de la semana de [d].
DateTime startOfWeek(DateTime d) => dateOnly(addDays(d, -(d.weekday - 1)));
