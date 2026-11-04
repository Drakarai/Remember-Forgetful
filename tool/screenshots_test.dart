// Genera capturas de las pantallas con datos de ejemplo:
//   flutter test tool/screenshots_test.dart --update-goldens
// Las imágenes quedan en tool/goldens/ (no se suben al repositorio).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lapsus/app.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lapsus/data/database.dart';
import 'package:lapsus/logic/dates.dart';
import 'package:lapsus/models/item.dart';
import 'package:lapsus/models/priority.dart';
import 'package:lapsus/models/recurrence.dart';
import 'package:lapsus/state/app_state.dart';
import 'package:lapsus/ui/screens/categories_screen.dart';
import 'package:lapsus/ui/screens/editor_screen.dart';
import 'package:lapsus/ui/screens/reminder_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _loadFonts() async {
  final manrope = FontLoader('Manrope');
  for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) {
    manrope.addFont(rootBundle.load('assets/fonts/Manrope_$w.ttf'));
  }
  await manrope.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/root/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await loader.load();
  }
}

var _n = 0;

Future<AppState> _seed(String theme, ThemeMode mode, {bool onboarding = true}) async {
  sqfliteFfiInit();
  final db = await LapsusDatabase.open(
      path: 'file:shot${_n++}?mode=memory&cache=shared', factory: databaseFactoryFfiNoIsolate);
  final s = AppState(db);
  await s.load();
  final today = dateOnly(DateTime.now());
  Item it(String title, String cat, Priority p, DateTime start,
          {ItemKind kind = ItemKind.event, bool allDay = false, Recurrence? r}) =>
      Item(
        id: newId(),
        title: title,
        categoryId: cat,
        priority: p,
        kind: kind,
        allDay: allDay,
        start: start,
        recurrence: r,
        createdAt: DateTime.now(),
      );
  final items = [
    it('Tomar la pastilla', 'health', Priority.critical, DateTime(today.year, today.month, today.day, 9),
        kind: ItemKind.task, r: const Recurrence(frequency: Frequency.daily)),
    it('Dentista', 'health', Priority.important, DateTime(today.year, today.month, today.day, 17, 30)),
    it('Pagar el recibo de la luz', 'payments', Priority.important, addDays(today, -2),
        kind: ItemKind.task, allDay: true),
    it('Sacar la basura', 'home', Priority.normal, DateTime(today.year, today.month, today.day, 21),
        kind: ItemKind.task, r: const Recurrence(frequency: Frequency.weekly, weekdays: {1, 3, 5})),
    it('Cumpleaños de Laura', 'birthday', Priority.important, addDays(today, 2),
        allDay: true, r: const Recurrence(frequency: Frequency.yearly)),
    it('Cena con amigos', 'social', Priority.normal, DateTime(today.year, today.month, today.day + 3, 21)),
    it('Entregar el trabajo', 'work', Priority.critical, DateTime(today.year, today.month, today.day + 5, 10),
        kind: ItemKind.task),
    it('Mirar ofertas de vuelos', 'other', Priority.none, DateTime(today.year, today.month, today.day + 4, 19),
        kind: ItemKind.task),
  ];
  for (final i in items) {
    await s.saveItem(i);
  }
  await s.toggleDone(s.onDay(today).firstWhere((o) => o.item.title == 'Tomar la pastilla'));
  await s.updateSettings(s.settings.copyWith(themeId: theme, themeMode: mode, onboardingDone: onboarding));
  return s;
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
        appName: 'Lapsus', packageName: 'com.lapsusapp.lapsus', version: '1.0.1', buildNumber: '1', buildSignature: '');
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
    await _loadFonts();
  });

  Future<void> shoot(WidgetTester tester, String name, String theme, ThemeMode mode,
      {Future<void> Function(WidgetTester t)? then, bool onboarding = true}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final state = await tester.runAsync(() => _seed(theme, mode, onboarding: onboarding));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state!, child: const LapsusApp()));
    await tester.pumpAndSettle();
    if (then != null) await then(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('hoy - tinta claro', (t) => shoot(t, '1_hoy_tinta', 'tinta', ThemeMode.light));
  testWidgets('hoy - ciruela oscuro', (t) => shoot(t, '2_hoy_ciruela_oscuro', 'ciruela', ThemeMode.dark));
  testWidgets('calendario - bosque', (t) => shoot(t, '3_calendario_bosque', 'bosque', ThemeMode.light, then: (t) async {
        await t.tap(find.text('Calendario'));
        await t.pumpAndSettle();
      }));
  testWidgets('ajustes - papel', (t) => shoot(t, '4_ajustes_papel', 'papel', ThemeMode.light, then: (t) async {
        await t.tap(find.text('Ajustes'));
        await t.pumpAndSettle();
      }));
  testWidgets('editor - grafito oscuro', (t) => shoot(t, '5_editor_grafito', 'grafito', ThemeMode.dark, then: (t) async {
        await t.tap(find.byTooltip('Nuevo'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'Llamar al seguro del coche');
        await t.pumpAndSettle();
      }));
  testWidgets('categorías - medianoche oscuro', (t) => shoot(t, '6_categorias', 'tinta', ThemeMode.dark, then: (t) async {
        final ctx = t.element(find.byType(HomeShell));
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const CategoriesScreen()));
        await t.pumpAndSettle();
      }));
  testWidgets('repetición personalizada', (t) => shoot(t, '7_repeticion', 'papel', ThemeMode.light, then: (t) async {
        final ctx = t.element(find.byType(HomeShell));
        Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => CustomRecurrenceScreen(
                initial: const Recurrence(frequency: Frequency.weekly, interval: 2, weekdays: {1, 4}),
                start: DateTime.now())));
        await t.pumpAndSettle();
      }));
  testWidgets('bienvenida', (t) => shoot(t, '8_bienvenida', 'tinta', ThemeMode.light, onboarding: false));
  testWidgets('editor con error', (t) => shoot(t, '9_editor_error', 'tinta', ThemeMode.light, then: (t) async {
        await t.tap(find.byTooltip('Nuevo'));
        await t.pumpAndSettle();
        await t.tap(find.text('Guardar'));
        await t.pumpAndSettle();
      }));
  testWidgets('recordatorio', (t) => shoot(t, '10_recordatorio', 'tinta', ThemeMode.dark, then: (t) async {
        final ctx = t.element(find.byType(HomeShell));
        final state = Provider.of<AppState>(ctx, listen: false);
        final o = state.onDay(DateTime.now()).firstWhere((o) => o.item.title == 'Dentista');
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ReminderScreen(itemId: o.item.id, dayKey: dateKey(o.start))));
        await t.pumpAndSettle();
      }));
  testWidgets('editor de categoría', (t) => shoot(t, '11_editar_categoria', 'bosque', ThemeMode.light, then: (t) async {
        final ctx = t.element(find.byType(HomeShell));
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const CategoriesScreen()));
        await t.pumpAndSettle();
        await t.tap(find.text('Casa'));
        await t.pumpAndSettle();
      }));
  testWidgets('semana', (t) => shoot(t, '12_semana', 'papel', ThemeMode.dark, then: (t) async {
        await t.tap(find.text('Calendario'));
        await t.pumpAndSettle();
        await t.tap(find.text('Semana'));
        await t.pumpAndSettle();
      }));
  testWidgets('editar serie', (t) => shoot(t, '13_editar_serie', 'tinta', ThemeMode.light, then: (t) async {
        await t.tap(find.text('Sacar la basura').first);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'Sacar la basura y el reciclaje');
        await t.tap(find.text('Guardar'));
        await t.pumpAndSettle();
      }));
}
