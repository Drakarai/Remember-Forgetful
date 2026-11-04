import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../logic/dates.dart';
import '../../models/app_settings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'categories_screen.dart';
import 'permissions_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final theme = Theme.of(context);

    Future<void> update(AppSettings n, {bool reschedule = false}) =>
        state.updateSettings(n, reschedule: reschedule);

    Future<TimeOfDay?> pickTime(TimeOfDay initial) => showTimePicker(
          context: context,
          initialTime: initial,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
        Text('Ajustes', style: theme.textTheme.headlineMedium),

        const SectionHeader('Tema'),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AppPalette.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final p = AppPalette.all[i];
              return _ThemeSwatch(
                palette: p,
                selected: p.id == AppPalette.byId(s.themeId).id,
                onTap: () => update(s.copyWith(themeId: p.id)),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Automático')),
            ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro')),
          ],
          showSelectedIcon: false,
          selected: {s.themeMode},
          onSelectionChanged: (v) => update(s.copyWith(themeMode: v.first)),
        ),

        const SectionHeader('Avisos'),
        Card(
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Resumen diario'),
              subtitle: Text(s.summaryEnabled ? 'Lo pendiente del día, cada mañana' : 'Desactivado'),
              value: s.summaryEnabled,
              onChanged: (v) => update(s.copyWith(summaryEnabled: v), reschedule: true),
            ),
            if (s.summaryEnabled)
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('Hora del resumen'),
                trailing: Text(fmtTimeOfDay(s.summaryTime), style: theme.textTheme.titleMedium),
                onTap: () async {
                  final t = await pickTime(s.summaryTime);
                  if (t != null) await update(s.copyWith(summaryTime: t), reschedule: true);
                },
              ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Hora de aviso (todo el día)'),
              subtitle: const Text('Para lo que no tiene hora'),
              trailing: Text(fmtTimeOfDay(s.allDayTime), style: theme.textTheme.titleMedium),
              onTap: () async {
                final t = await pickTime(s.allDayTime);
                if (t != null) await update(s.copyWith(allDayTime: t), reschedule: true);
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('Repetir avisos críticos'),
              subtitle: const Text('Hasta 6 veces, mientras no esté marcado'),
              trailing: DropdownButton<int>(
                value: s.nagIntervalMinutes,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 min')),
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 10, child: Text('10 min')),
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                ],
                onChanged: (v) => update(s.copyWith(nagIntervalMinutes: v), reschedule: true),
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            SwitchListTile(
              secondary: const Icon(Icons.bedtime_outlined),
              title: const Text('Horas de silencio'),
              subtitle: Text(s.quietEnabled
                  ? 'De ${fmtTimeOfDay(s.quietStart)} a ${fmtTimeOfDay(s.quietEnd)}. Lo crítico suena igual.'
                  : 'Los avisos no críticos esperan a la mañana'),
              value: s.quietEnabled,
              onChanged: (v) => update(s.copyWith(quietEnabled: v), reschedule: true),
            ),
            if (s.quietEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await pickTime(s.quietStart);
                        if (t != null) await update(s.copyWith(quietStart: t), reschedule: true);
                      },
                      child: Text('Desde ${fmtTimeOfDay(s.quietStart)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await pickTime(s.quietEnd);
                        if (t != null) await update(s.copyWith(quietEnd: t), reschedule: true);
                      },
                      child: Text('Hasta ${fmtTimeOfDay(s.quietEnd)}'),
                    ),
                  ),
                ]),
              ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Permisos y prueba de avisos'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsScreen())),
            ),
          ]),
        ),

        const SectionHeader('Organización'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.label_outline_rounded),
            title: const Text('Categorías'),
            subtitle: const Text('Crear, editar e importancia por defecto'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ),

        const SectionHeader('Datos'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('Exportar'),
              subtitle: const Text('Guarda todos los datos en un archivo'),
              onTap: () => _export(context),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Importar'),
              subtitle: const Text('Reemplaza los datos actuales por los de un archivo'),
              onTap: () => _import(context),
            ),
          ]),
        ),

        const SizedBox(height: 32),
        Center(
          child: Column(children: [
            const Wordmark(size: 22),
            const SizedBox(height: 6),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, snap) => Text(
                snap.hasData ? 'v${snap.data!.version}' : '',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _export(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await state.exportBackup();
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Exportar datos',
        fileName: 'lapsus-${dateKey(DateTime.now())}.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (uri != null) messenger.showSnackBar(const SnackBar(content: Text('Datos exportados')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final files = await FilePicker.pickFiles(dialogTitle: 'Elegir archivo');
    if (files.isEmpty || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Importar datos?'),
        content: const Text('Se borrará lo que hay ahora en la app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.importBackup(await files.first.readAsBytes());
      messenger.showSnackBar(const SnackBar(content: Text('Datos importados')));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo importar: $e')));
    }
  }
}

class _ThemeSwatch extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    final bg = dark ? palette.darkBackground : palette.lightBackground;
    final surface = dark ? palette.darkSurface : palette.lightSurface;
    final ink = dark ? Colors.white : Colors.black87;
    final line = ink.withValues(alpha: 0.12);
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 76,
          height: 92,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accentFor(b) : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          // Miniatura de la pantalla con los colores del tema.
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 22, height: 4, color: palette.accentFor(b)),
            const SizedBox(height: 4),
            Container(width: 40, height: 7, color: ink.withValues(alpha: 0.8)),
            const Spacer(),
            for (var i = 0; i < 2; i++)
              Container(
                height: 16,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(children: [
                  Container(width: 2, margin: const EdgeInsets.fromLTRB(4, 3, 4, 3), color: i == 0 ? palette.accentFor(b) : line),
                  Container(width: 26, height: 3, color: ink.withValues(alpha: 0.4)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(palette.name,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
            )),
      ]),
    );
  }
}
