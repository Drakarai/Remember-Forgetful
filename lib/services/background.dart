import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../data/database.dart';
import 'notification_service.dart';

const _refreshTask = 'lapsus-refresh';

/// Tarea periódica en segundo plano: vuelve a programar los avisos de los
/// próximos días aunque no se abra la app durante semanas.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      DartPluginRegistrant.ensureInitialized();
      final db = await LapsusDatabase.open(shared: false);
      try {
        final notifications = NotificationService();
        await notifications.init();
        await notifications.reschedule(db);
      } finally {
        await db.close();
      }
    } catch (e) {
      debugPrint('Error en la tarea de fondo: $e');
    }
    return true;
  });
}

Future<void> registerBackgroundRefresh() async {
  try {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      _refreshTask,
      _refreshTask,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (e) {
    debugPrint('No se pudo registrar la tarea de fondo: $e');
  }
}
