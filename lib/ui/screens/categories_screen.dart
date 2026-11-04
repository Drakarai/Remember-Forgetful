import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/priority.dart';
import '../../state/app_state.dart';
import '../category_icons.dart';
import '../widgets/common.dart';

/// Gestiona las categorías y su importancia por defecto.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'restore') {
                await state.restoreDefaultPriorities();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Importancias originales restauradas')));
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'restore', child: Text('Restaurar importancias originales')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nueva categoría',
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add_rounded),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        Text(
          'La importancia por defecto se aplica al crear algo nuevo en esa categoría. '
          'Lo que ya está apuntado no cambia.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < state.categories.length; i++) ...[
              if (i > 0) const Divider(indent: 56),
              _CategoryRow(category: state.categories[i], onTap: () => _edit(context, state.categories[i])),
            ],
          ]),
        ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, Category? c) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppState>(),
        child: _CategoryEditor(category: c),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;
  const _CategoryRow({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(categoryIcon(category.icon), color: Color(category.color)),
      title: Text(category.name),
      subtitle: Align(alignment: Alignment.centerLeft, child: PriorityLabel(category.defaultPriority)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  final Category? category;
  const _CategoryEditor({this.category});

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String icon = widget.category?.icon ?? 'star';
  late int color = widget.category?.color ?? _colors.first;
  late Priority priority = widget.category?.defaultPriority ?? Priority.normal;

  static const _colors = [
    0xFF3E63DD, 0xFF8E4EC6, 0xFFE93D82, 0xFFE5484D, 0xFFF76B15, 0xFFF2A516,
    0xFF30A46C, 0xFF12A594, 0xFF0090FF, 0xFF8B8D98,
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final state = context.read<AppState>();
    final c = widget.category;
    await state.saveCategory(c == null
        ? Category(
            id: newId(),
            name: name,
            icon: icon,
            color: color,
            defaultPriority: priority,
            sortOrder: state.nextCategoryOrder,
          )
        : c.copyWith(name: name, icon: icon, color: color, defaultPriority: priority));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final c = widget.category!;
    final n = await state.countItemsInCategory(c.id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('¿Borrar "${c.name}"?'),
        content: Text(n == 0
            ? 'No tiene nada apuntado.'
            : (n == 1 ? '1 elemento pasará a "Otros".' : '$n elementos pasarán a "Otros".')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await state.deleteCategory(c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.category;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c == null ? 'Nueva categoría' : 'Editar categoría', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(categoryIcon(icon), color: Color(color), size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: c == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Nombre'),
                ),
              ),
            ]),
            const SectionHeader('Icono'),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final e in categoryIcons.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => icon = e.key),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.key == icon ? Color(color).withValues(alpha: 0.15) : null,
                      border: e.key == icon ? Border.all(color: Color(color)) : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(e.value, size: 22, color: e.key == icon ? Color(color) : theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ]),
            const SectionHeader('Color'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final col in _colors)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => color = col),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(col),
                      shape: BoxShape.circle,
                    ),
                    child: col == color ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
            const SectionHeader('Importancia por defecto'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in Priority.values)
                ChoiceChip(
                  avatar: PriorityIcon(p, size: 18),
                  label: Text(p.label),
                  selected: p == priority,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => priority = p),
                ),
            ]),
            const SizedBox(height: 8),
            Text(priority.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            Row(children: [
              if (c != null && c.isDeletable)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Borrar'),
                  style: TextButton.styleFrom(foregroundColor: Priority.critical.color),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Guardar')),
            ]),
          ]),
        ),
      ),
    );
  }
}
