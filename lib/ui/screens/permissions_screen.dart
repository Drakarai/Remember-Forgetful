import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/priority.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';

/// Revisa y arregla los permisos que hacen falta para que los avisos
/// lleguen siempre y a tiempo.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  final service = NotificationService();
  PermissionStatusReport? report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Al volver de los ajustes del sistema, se vuelve a comprobar.
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final r = await service.checkPermissions();
    if (mounted) setState(() => report = r);
  }

  Future<void> _run(Future<void> Function() f) async {
    await f();
    await _check();
    if (mounted) await context.read<AppState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    return Scaffold(
      appBar: AppBar(title: const Text('Permisos')),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                'Necesarios para que los avisos lleguen a su hora con el móvil bloqueado.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _PermissionCard(
                ok: r.notifications,
                title: 'Notificaciones',
                description: 'Imprescindible.',
                action: 'Activar',
                onTap: () => _run(() async {
                  await service.requestNotifications();
                  final again = await service.checkPermissions();
                  // Si ya se denegó antes, Android no vuelve a preguntar.
                  if (!again.notifications) await service.openSystemSettings();
                }),
              ),
              _PermissionCard(
                ok: r.exactAlarms,
                title: 'Alarmas exactas',
                description: 'Sin esto, Android puede retrasar los avisos varios minutos.',
                action: 'Permitir',
                onTap: () => _run(service.requestExactAlarms),
              ),
              _PermissionCard(
                ok: r.batteryUnrestricted,
                title: 'Sin restricción de batería',
                description: 'Algunas marcas (Xiaomi, Samsung, Huawei…) cierran las apps en segundo plano.',
                action: 'Quitar restricción',
                onTap: () => _run(service.requestBatteryUnrestricted),
              ),
              _PermissionCard(
                ok: null,
                title: 'Pantalla completa',
                description: 'Los avisos críticos se muestran como un despertador.',
                action: 'Revisar',
                onTap: () => _run(service.requestFullScreen),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Probar', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('El aviso llega a los 5 segundos.', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(
                        onPressed: () => _sendTest(Priority.normal),
                        child: const Text('Normal'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Priority.critical.color),
                        onPressed: () => _sendTest(Priority.critical),
                        icon: const Icon(Icons.bolt_rounded),
                        label: const Text('Crítico'),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'En Xiaomi activa también "Inicio automático" para Lapsus en los ajustes del sistema.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
    );
  }

  Future<void> _sendTest(Priority p) async {
    await service.sendTest(p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviado')));
    }
  }
}

class _PermissionCard extends StatelessWidget {
  /// null = no se puede comprobar.
  final bool? ok;
  final String title;
  final String description;
  final String action;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.ok,
    required this.title,
    required this.description,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok == true
        ? const Color(0xFF30A46C)
        : (ok == false ? Priority.critical.color : theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(
              ok == true ? Icons.check_circle_rounded : (ok == false ? Icons.error_rounded : Icons.help_rounded),
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall),
              ]),
            ),
            if (ok != true) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: onTap, child: Text(action)),
            ],
          ]),
        ),
      ),
    );
  }
}
