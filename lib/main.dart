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
    // Botones "Hecho" / "Posponer" pulsados con la app abierta.
    if (response.actionId != null) {
      await notifications.handleAction(db, response);
    }
    await state.load();
  });
  notifications.onChanged = state.load;

  await state.load();
  unawaited(notifications.reschedule(db));

  runApp(ChangeNotifierProvider.value(value: state, child: const LapsusApp()));
}
