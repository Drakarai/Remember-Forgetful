import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/database.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es';
  await initializeDateFormatting('es');

  final db = await LapsusDatabase.open();
  final notifications = NotificationService();
  final state = AppState(db, notifications: notifications);

  await notifications.init(onTap: (response) async {
    if (response.actionId != null) {
      // Botones "Hecho" / "Posponer" pulsados con la app abierta.
      await notifications.handleAction(db, response);
      await state.load();
      return;
    }
    // Toque en la notificación: abrir ese recordatorio.
    await state.load();
    final data = NotificationService.parsePayload(response.payload);
    if (data != null && state.settings.onboardingDone) openReminder(data.itemId, data.dayKey);
  });
  notifications.onChanged = state.load;

  await state.load();
  unawaited(notifications.reschedule(db));

  runApp(ChangeNotifierProvider.value(value: state, child: const LapsusApp()));

  // Si la app se ha abierto desde una notificación, mostrar ese recordatorio.
  final launch = await notifications.launchResponse();
  final data = NotificationService.parsePayload(launch?.payload);
  if (launch != null && launch.actionId == null && data != null && state.settings.onboardingDone) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openReminder(data.itemId, data.dayKey));
  }
}
