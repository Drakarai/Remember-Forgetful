import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Priority;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln show Priority;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../logic/dates.dart';
import '../logic/notification_planner.dart';
import '../models/app_settings.dart';
import '../models/priority.dart';

const _actionDone = 'done';
const _actionSnooze10 = 'snooze10';
const _actionSnooze60 = 'snooze60';

/// Se ejecuta cuando se pulsa un botón de una notificación con la app
/// cerrada. Corre en un "isolate" aparte, así que abre su propia conexión a
/// la base de datos.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final db = await LapsusDatabase.open(shared: false);
  try {
    final service = NotificationService();
    await service.init();
    await service.handleAction(db, response);
  } finally {
    await db.close();
  }
}

/// Estado de los permisos necesarios para que los avisos lleguen siempre.
class PermissionStatusReport {
  final bool notifications;
  final bool exactAlarms;
  final bool batteryUnrestricted;

  const PermissionStatusReport({
    required this.notifications,
    required this.exactAlarms,
    required this.batteryUnrestricted,
  });

  bool get allGood => notifications && exactAlarms && batteryUnrestricted;
}

/// Programa los avisos en Android.
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void> _queue = Future.value();

  /// Se llama cuando el usuario pulsa una notificación o uno de sus botones
  /// con la app abierta (para refrescar la pantalla).
  VoidCallback? onChanged;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static const _channels = {
    Priority.critical: AndroidNotificationChannel(
      'critical_v1',
      'Críticos',
      description: 'Suenan como una alarma y se repiten hasta marcarlos',
      importance: Importance.max,
      sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ),
    Priority.important: AndroidNotificationChannel(
      'important_v1',
      'Importantes',
      description: 'Aviso previo y recordatorio',
      importance: Importance.high,
    ),
    Priority.normal: AndroidNotificationChannel(
      'normal_v1',
      'Normales',
      description: 'Un aviso a la hora indicada',
      importance: Importance.high,
    ),
  };

  static const _summaryChannel = AndroidNotificationChannel(
    'summary_v1',
    'Resumen diario',
    description: 'Lo pendiente de cada día',
    importance: Importance.defaultImportance,
  );

  Future<void> init({DidReceiveNotificationResponseCallback? onTap}) async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Madrid'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_lapsus'),
      ),
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    final android = _android;
    if (android != null) {
      for (final c in [..._channels.values, _summaryChannel]) {
        await android.createNotificationChannel(c);
      }
    }
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Permisos
  // ---------------------------------------------------------------------------

  Future<PermissionStatusReport> checkPermissions() async {
    final android = _android;
    if (android == null) {
      return const PermissionStatusReport(
          notifications: true, exactAlarms: true, batteryUnrestricted: true);
    }
    final notif = await android.areNotificationsEnabled() ?? false;
    final exact = await android.canScheduleExactNotifications() ?? false;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    return PermissionStatusReport(
      notifications: notif,
      exactAlarms: exact,
      batteryUnrestricted: battery,
    );
  }

  Future<void> requestNotifications() async {
    await _android?.requestNotificationsPermission();
  }

  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  Future<void> requestBatteryUnrestricted() async {
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> requestFullScreen() async {
    await _android?.requestFullScreenIntentPermission();
  }

  Future<void> openSystemSettings() async {
    await _android?.openAppNotificationSettings();
  }

  // ---------------------------------------------------------------------------
  // Programación
  // ---------------------------------------------------------------------------

  /// Días hacia delante que se programan. Se recalcula al abrir la app, al
  /// cambiar algo y cada 12 horas en segundo plano.
  static const windowDays = 30;

  /// Recalcula y vuelve a programar todos los avisos. Las llamadas se
  /// encadenan para que nunca se pisen dos a la vez.
  Future<void> reschedule(LapsusDatabase db) {
    final next = _queue.then((_) => _reschedule(db)).catchError((Object e, StackTrace s) {
      debugPrint('Error programando avisos: $e\n$s');
    });
    _queue = next;
    return next;
  }

  Future<void> _reschedule(LapsusDatabase db) async {
    final android = _android;
    if (android == null) return;
    final now = DateTime.now();
    await db.cleanupSnoozes(now);
    final agenda = await db.agenda();
    final settings = AppSettings.fromMap(await db.settings());
    final occurrences = agenda.between(addDays(now, -1), addDays(now, windowDays));
    final plans = planNotifications(
      occurrences: occurrences,
      now: now,
      settings: settings.planner,
      snoozes: await db.snoozes(),
    );

    final exact = await android.canScheduleExactNotifications() ?? false;
    // Solo se tocan los avisos que han cambiado: programar cientos de avisos
    // cada vez que se abre la app sería lento.
    final wanted = {for (final p in plans) _systemId(p, exact): p};
    final pending = {for (final r in await _plugin.pendingNotificationRequests()) r.id};
    for (final id in pending) {
      if (!wanted.containsKey(id) && !_testIds.contains(id)) await _plugin.cancel(id: id);
    }
    for (final entry in wanted.entries) {
      if (pending.contains(entry.key)) continue;
      try {
        await _schedule(entry.value, exact: exact, id: entry.key);
      } catch (e) {
        debugPrint('No se pudo programar ${entry.value.title}: $e');
      }
    }
  }

  /// Id del aviso en el sistema (cambia si cambia el modo exacto/inexacto).
  int _systemId(PlannedNotification p, bool exact) => stableId('${p.id}|${exact ? 'e' : 'i'}');

  static final _testIds = {for (final p in Priority.values) stableId('test|${p.name}')};

  static String payloadFor(String itemId, String dayKey) => jsonEncode({'item': itemId, 'day': dayKey});

  /// Quita de la barra de notificaciones los avisos ya mostrados de un
  /// elemento (de un día concreto o de todos).
  Future<void> cancelShownFor(String itemId, {String? dayKey}) async {
    final android = _android;
    if (android == null) return;
    try {
      for (final n in await android.getActiveNotifications()) {
        final data = parsePayload(n.payload);
        if (data == null || data.itemId != itemId) continue;
        if (dayKey != null && data.dayKey != dayKey) continue;
        if (n.id != null) await _plugin.cancel(id: n.id!, tag: n.tag);
      }
    } catch (e) {
      debugPrint('No se pudieron quitar avisos: $e');
    }
  }

  static ({String itemId, String dayKey})? parsePayload(String? payload) {
    if (payload == null) return null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final itemId = data['item'] as String?;
      final day = data['day'] as String?;
      if (itemId == null || day == null) return null;
      return (itemId: itemId, dayKey: day);
    } catch (_) {
      return null;
    }
  }

  /// Si la app se ha abierto tocando una notificación, cuál fue.
  Future<NotificationResponse?> launchResponse() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) return details!.notificationResponse;
    } catch (_) {}
    return null;
  }

  Future<void> _schedule(PlannedNotification p, {required bool exact, int? id}) async {
    final mode = !exact
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : (p.priority == Priority.critical && p.kind != PlanKind.dayBefore && p.kind != PlanKind.hourBefore)
            // "Modo despertador": el más fiable, no lo retrasa el ahorro de batería.
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle;
    await _plugin.zonedSchedule(
      id: id ?? p.id,
      title: p.title,
      body: p.body,
      scheduledDate: tz.TZDateTime.from(p.when, tz.local),
      notificationDetails: _details(p),
      androidScheduleMode: mode,
      payload: p.itemId == null ? null : payloadFor(p.itemId!, p.dayKey!),
    );
  }

  NotificationDetails _details(PlannedNotification p) {
    if (p.kind == PlanKind.summary) {
      return NotificationDetails(
        android: AndroidNotificationDetails(
          _summaryChannel.id,
          _summaryChannel.name,
          channelDescription: _summaryChannel.description,
          styleInformation: BigTextStyleInformation(p.body),
          category: AndroidNotificationCategory.reminder,
        ),
      );
    }
    final channel = _channels[p.priority] ?? _channels[Priority.normal]!;
    final critical = p.priority == Priority.critical;
    final mainAlert = critical && (p.kind == PlanKind.atTime || p.kind == PlanKind.snooze);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: critical ? fln.Priority.max : fln.Priority.high,
        color: p.priority.color,
        category: critical ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
        audioAttributesUsage: channel.audioAttributesUsage,
        fullScreenIntent: mainAlert,
        // FLAG_INSISTENT (4): el sonido se repite hasta que se toca.
        additionalFlags: p.insistent ? Int32List.fromList([4]) : null,
        styleInformation: BigTextStyleInformation(p.body),
        visibility: NotificationVisibility.public,
        actions: [
          AndroidNotificationAction(_actionDone, p.isTask ? 'Hecho' : 'Vale'),
          const AndroidNotificationAction(_actionSnooze10, '10 min'),
          const AndroidNotificationAction(_actionSnooze60, '1 hora'),
        ],
      ),
    );
  }

  /// Procesa un botón de notificación ("Hecho", "Posponer").
  Future<bool> handleAction(LapsusDatabase db, NotificationResponse response) async {
    final data = parsePayload(response.payload);
    if (data == null) return false;
    final itemId = data.itemId;
    final day = data.dayKey;
    switch (response.actionId) {
      case _actionDone:
        await db.setDone(itemId, day, true);
      case _actionSnooze10:
        await db.snooze(itemId, day, DateTime.now().add(const Duration(minutes: 10)));
      case _actionSnooze60:
        await db.snooze(itemId, day, DateTime.now().add(const Duration(hours: 1)));
      default:
        return false;
    }
    await cancelShownFor(itemId, dayKey: day);
    await reschedule(db);
    onChanged?.call();
    return true;
  }

  /// Aviso de prueba para comprobar que todo funciona.
  Future<void> sendTest(Priority priority) async {
    final p = PlannedNotification(
      id: stableId('test|${priority.name}'),
      when: DateTime.now().add(const Duration(seconds: 5)),
      title: priority == Priority.critical ? 'Prueba: aviso crítico' : 'Prueba: aviso normal',
      body: priority == Priority.critical
          ? 'Toca la notificación para pararla.'
          : 'Los avisos funcionan.',
      priority: priority,
      kind: PlanKind.atTime,
      insistent: priority == Priority.critical,
    );
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    await _schedule(p, exact: exact);
  }
}
