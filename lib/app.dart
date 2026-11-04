import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'logic/dates.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/screens/calendar_screen.dart';
import 'ui/screens/editor_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/reminder_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/today_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Abre la pantalla de un recordatorio (al tocar su notificación).
void openReminder(String itemId, String dayKey) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute(builder: (_) => ReminderScreen(itemId: itemId, dayKey: dayKey)));
}

class LapsusApp extends StatelessWidget {
  const LapsusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final palette = AppPalette.byId(state.settings.themeId);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Lapsus',
      debugShowCheckedModeBanner: false,
      theme: palette.theme(Brightness.light),
      darkTheme: palette.theme(Brightness.dark),
      themeMode: state.settings.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: !state.loaded
          ? const Scaffold(body: SizedBox.shrink())
          : (state.settings.onboardingDone ? const HomeShell() : const OnboardingScreen()),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int index = 0;
  final selectedDay = ValueNotifier<DateTime>(dateOnly(DateTime.now()));
  PermissionStatusReport? permissions;
  DateTime _lastDay = dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    selectedDay.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      // Al volver a la app: refrescar datos, avisos y permisos.
      context.read<AppState>().refresh();
      _checkPermissions();
      final today = dateOnly(DateTime.now());
      if (today != _lastDay) {
        _lastDay = today;
        selectedDay.value = today;
      }
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final r = await NotificationService().checkPermissions();
      if (mounted) setState(() => permissions = r);
    } catch (_) {
      // Sin acceso al sistema (p. ej. en pruebas): no se muestra el aviso.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(permissions: permissions),
      CalendarScreen(selected: selectedDay),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: index == 2
          ? null
          : FloatingActionButton(
              tooltip: 'Nuevo',
              onPressed: () => openEditor(context, day: index == 1 ? selectedDay.value : null),
              child: const Icon(Icons.add_rounded, size: 28),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.view_agenda_outlined), label: 'Hoy'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), label: 'Calendario'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
        ],
      ),
    );
  }
}
