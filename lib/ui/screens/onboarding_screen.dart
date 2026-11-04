import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/priority.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Pantalla inicial (solo la primera vez): explica lo básico y pide permisos.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool busy = false;

  Future<void> _start() async {
    setState(() => busy = true);
    final state = context.read<AppState>();
    final n = NotificationService();
    await n.requestNotifications();
    await n.requestBatteryUnrestricted();
    await state.updateSettings(state.settings.copyWith(onboardingDone: true));
    await state.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Wordmark(size: 44),
            const SizedBox(height: 10),
            Text('Agenda y recordatorios', style: theme.textTheme.titleMedium?.copyWith(color: muted)),
            const SizedBox(height: 40),
            Text('Cada cosa tiene una importancia, y eso decide cómo te avisa:',
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            for (final p in Priority.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  PriorityIcon(p, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${p.label}. ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: p.description, style: TextStyle(color: muted)),
                    ])),
                  ),
                ]),
              ),
            const Spacer(),
            Text('A continuación Android pedirá permiso para mostrar notificaciones '
                'y para funcionar sin restricciones de batería.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: busy ? null : _start,
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continuar'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
