import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../models/custom_drill.dart';
import 'drill_tile.dart';

/// Home-screen quick pick (issue #24): lists the saved drills; tapping one
/// applies it. Every action closes the sheet *before* running its callback,
/// so callbacks run on the caller's still-mounted context and any dialog or
/// snackbar they show is not hidden behind the sheet. The content is a
/// snapshot for the same reason: nothing can change while it is open.
class DrillPickerSheet extends StatelessWidget {
  const DrillPickerSheet({
    super.key,
    required this.drills,
    required this.activeId,
    required this.onApply,
    required this.onManage,
    required this.onSaveCurrent,
  });

  final List<CustomDrill> drills;
  final int? activeId;
  final ValueChanged<CustomDrill> onApply;
  final VoidCallback onManage;
  final VoidCallback onSaveCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void closeThen(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('drills.pickerTitle'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.tune),
                  label: Text(context.tr('drills.manage')),
                  onPressed: () => closeThen(onManage),
                ),
              ],
            ),
          ),
          if (drills.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                context.tr('drills.empty'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: drills.length,
                itemBuilder: (context, index) {
                  final d = drills[index];
                  return DrillTile(
                    drill: d,
                    active: d.id == activeId,
                    onTap: () => closeThen(() => onApply(d)),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: Text(context.tr('drills.saveCurrent')),
            onTap: () => closeThen(onSaveCurrent),
          ),
        ],
      ),
    );
  }
}
