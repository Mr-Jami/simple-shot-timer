import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/custom_drill.dart';
import '../providers/custom_drills_provider.dart';
import '../widgets/drill_tile.dart';
import 'custom_drill_flows.dart';

enum _DrillAction { apply, rename, overwrite, delete }

/// Manage saved custom drills (issue #24): apply, rename, overwrite with the
/// current settings, delete. Reached from Settings and the home quick pick.
class CustomDrillsScreen extends ConsumerWidget {
  const CustomDrillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drills = ref.watch(customDrillsProvider);
    final activeId = ref.watch(activeDrillProvider.select((d) => d?.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('drills.manageTitle')),
        actions: [
          IconButton(
            tooltip: context.tr('drills.saveCurrent'),
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => saveCurrentDrill(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: drills.isEmpty
            ? _EmptyState(onSave: () => saveCurrentDrill(context, ref))
            : ListView.separated(
                itemCount: drills.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final d = drills[index];
                  return DrillTile(
                    drill: d,
                    active: d.id == activeId,
                    onTap: () => applyDrill(context, ref, d),
                    trailing: PopupMenuButton<_DrillAction>(
                      onSelected: (action) => _run(context, ref, d, action),
                      itemBuilder: (_) => _menuItems(context),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  CustomDrill drill,
  _DrillAction action,
) =>
    switch (action) {
      _DrillAction.apply => applyDrill(context, ref, drill),
      _DrillAction.rename => renameDrill(context, ref, drill),
      _DrillAction.overwrite => overwriteDrill(context, ref, drill),
      _DrillAction.delete => deleteDrill(context, ref, drill),
    };

List<PopupMenuEntry<_DrillAction>> _menuItems(BuildContext context) => [
      PopupMenuItem(
        value: _DrillAction.apply,
        child: Text(context.tr('common.apply')),
      ),
      PopupMenuItem(
        value: _DrillAction.rename,
        child: Text(context.tr('common.rename')),
      ),
      PopupMenuItem(
        value: _DrillAction.overwrite,
        child: Text(context.tr('drills.overwriteCurrent')),
      ),
      PopupMenuItem(
        value: _DrillAction.delete,
        child: Text(
          context.tr('common.delete'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ];

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmarks_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('drills.empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(context.tr('drills.saveCurrent')),
              onPressed: onSave,
            ),
          ],
        ),
      ),
    );
  }
}
