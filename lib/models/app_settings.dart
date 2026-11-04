import 'package:flutter/material.dart';

import '../logic/notification_planner.dart';

/// Ajustes de la app. Se guardan en la base de datos (tabla `settings`)
/// para que también los lean los botones de las notificaciones.
class AppSettings {
  final String themeId;
  final ThemeMode themeMode;
  final bool summaryEnabled;
  final TimeOfDay summaryTime;
  final TimeOfDay allDayTime;
  final int nagIntervalMinutes;
  final bool onboardingDone;
  final bool quietEnabled;
  final TimeOfDay quietStart;
  final TimeOfDay quietEnd;

  const AppSettings({
    this.themeId = 'tinta',
    this.themeMode = ThemeMode.system,
    this.summaryEnabled = true,
    this.summaryTime = const TimeOfDay(hour: 8, minute: 0),
    this.allDayTime = const TimeOfDay(hour: 9, minute: 0),
    this.nagIntervalMinutes = 5,
    this.onboardingDone = false,
    this.quietEnabled = false,
    this.quietStart = const TimeOfDay(hour: 23, minute: 0),
    this.quietEnd = const TimeOfDay(hour: 8, minute: 0),
  });

  PlannerSettings get planner => PlannerSettings(
        allDayHour: allDayTime.hour,
        allDayMinute: allDayTime.minute,
        nagIntervalMinutes: nagIntervalMinutes,
        summaryEnabled: summaryEnabled,
        summaryHour: summaryTime.hour,
        summaryMinute: summaryTime.minute,
        quietEnabled: quietEnabled,
        quietStart: quietStart.hour * 60 + quietStart.minute,
        quietEnd: quietEnd.hour * 60 + quietEnd.minute,
      );

  AppSettings copyWith({
    String? themeId,
    ThemeMode? themeMode,
    bool? summaryEnabled,
    TimeOfDay? summaryTime,
    TimeOfDay? allDayTime,
    int? nagIntervalMinutes,
    bool? onboardingDone,
    bool? quietEnabled,
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) =>
      AppSettings(
        themeId: themeId ?? this.themeId,
        themeMode: themeMode ?? this.themeMode,
        summaryEnabled: summaryEnabled ?? this.summaryEnabled,
        summaryTime: summaryTime ?? this.summaryTime,
        allDayTime: allDayTime ?? this.allDayTime,
        nagIntervalMinutes: nagIntervalMinutes ?? this.nagIntervalMinutes,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );

  static String _t(TimeOfDay t) => '${t.hour}:${t.minute}';
  static TimeOfDay? _p(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Map<String, String> toMap() => {
        'themeId': themeId,
        'themeMode': themeMode.name,
        'summaryEnabled': summaryEnabled.toString(),
        'summaryTime': _t(summaryTime),
        'allDayTime': _t(allDayTime),
        'nagIntervalMinutes': nagIntervalMinutes.toString(),
        'onboardingDone': onboardingDone.toString(),
        'quietEnabled': quietEnabled.toString(),
        'quietStart': _t(quietStart),
        'quietEnd': _t(quietEnd),
      };

  factory AppSettings.fromMap(Map<String, String> m) {
    const d = AppSettings();
    return AppSettings(
      themeId: m['themeId'] ?? d.themeId,
      themeMode: ThemeMode.values.firstWhere((e) => e.name == m['themeMode'], orElse: () => d.themeMode),
      summaryEnabled: m['summaryEnabled'] == null ? d.summaryEnabled : m['summaryEnabled'] == 'true',
      summaryTime: _p(m['summaryTime']) ?? d.summaryTime,
      allDayTime: _p(m['allDayTime']) ?? d.allDayTime,
      nagIntervalMinutes: int.tryParse(m['nagIntervalMinutes'] ?? '') ?? d.nagIntervalMinutes,
      onboardingDone: m['onboardingDone'] == 'true',
      quietEnabled: m['quietEnabled'] == 'true',
      quietStart: _p(m['quietStart']) ?? d.quietStart,
      quietEnd: _p(m['quietEnd']) ?? d.quietEnd,
    );
  }
}
