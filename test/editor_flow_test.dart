import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lapsus/app.dart';
import 'package:lapsus/data/database.dart';
import 'package:lapsus/state/app_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _n = 0;

Future<AppState> _state() async {
  sqfliteFfiInit();
  final db = await LapsusDatabase.open(
      path: 'file:flow${_n++}?mode=memory&cache=shared', factory: databaseFactoryFfiNoIsolate);
  final s = AppState(db);
  await s.load();
  await s.updateSettings(s.settings.copyWith(onboardingDone: true));
  return s;
}

Future<AppState> _pumpApp(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  final state = (await t.runAsync(_state))!;
  await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const LapsusApp()));
  await t.pumpAndSettle();
  return state;
}

Future<void> _settle(WidgetTester t) async {
  // Deja que terminen las escrituras reales en la base de datos.
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
        appName: 'Lapsus', packageName: 'x', version: '1.0.0', buildNumber: '1', buildSignature: '');
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  testWidgets('crear un evento lo guarda y cierra el editor', (t) async {
    final state = await _pumpApp(t);
    await t.tap(find.byTooltip('Nuevo'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Dentista');
    await t.tap(find.text('Guardar'));
    await _settle(t);
    expect(find.text('Guardar'), findsNothing, reason: 'el editor debería cerrarse');
    expect(state.agenda.items.single.title, 'Dentista');
  });

  testWidgets('sin título no guarda y marca el campo en rojo', (t) async {
    final state = await _pumpApp(t);
    await t.tap(find.byTooltip('Nuevo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar'));
    await _settle(t);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Escribe un título'), findsOneWidget);
    expect(state.agenda.items, isEmpty);
    // Al escribir, el error desaparece.
    await t.enterText(find.byType(TextField).first, 'Algo');
    await t.pump();
    expect(find.text('Escribe un título'), findsNothing);
  });
}
