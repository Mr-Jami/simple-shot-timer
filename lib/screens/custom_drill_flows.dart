import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/custom_drill.dart';
import '../models/drill_config.dart';
import '../providers/custom_drills_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/drill_name_dialog.dart';

// User flows around custom drills (issue #24), shared by the settings
// section, the manage screen and the home quick pick so every entry point
// behaves identically. Each flow reads its notifiers before the first await,
// and a flow that uses the context after a dialog checks `mounted` first.

/// Prompts for a name and saves the current drill configuration under it.
/// A name that is already taken asks whether to overwrite that drill.
Future<void> saveCurrentDrill(BuildContext context, WidgetRef ref) async {
  final drills = ref.read(customDrillsProvider.notifier);
  final config = DrillConfig.fromSettings(ref.read(settingsProvider));
  final name = await showDrillNameDialog(
    context,
    title: context.tr('drills.saveTitle'),
    confirmLabel: context.tr('common.save'),
  );
  if (name == null || !context.mounted) return;

  final existing = drills.findByName(name);
  if (existing != null) {
    await _confirmAndOverwrite(
      context,
      ref,
      existing,
      config,
      body: context.tr('drills.overwriteBody', args: {'name': existing.name}),
    );
    return;
  }
  await drills.add(name, config);
  if (!context.mounted) return;
  _snack(context, context.tr('drills.savedSnack', args: {'name': name}));
}

/// Loads [drill] into the settings and says so. Only the drill fields
/// change; the timer picks them up at the next start.
Future<void> applyDrill(
  BuildContext context,
  WidgetRef ref,
  CustomDrill drill,
) async {
  await ref.read(settingsProvider.notifier).applyDrill(drill.config);
  if (!context.mounted) return;
  _snack(context, context.tr('drills.appliedSnack', args: {'name': drill.name}));
}

/// Prompts for a new name; a name another drill already uses is rejected
/// inline (a different spelling of the drill's own name is fine).
Future<void> renameDrill(
  BuildContext context,
  WidgetRef ref,
  CustomDrill drill,
) async {
  final drills = ref.read(customDrillsProvider.notifier);
  final taken = context.tr('drills.nameExists');
  final name = await showDrillNameDialog(
    context,
    title: context.tr('drills.renameTitle'),
    confirmLabel: context.tr('common.rename'),
    initial: drill.name,
    validate: (candidate) =>
        drills.findByName(candidate, excludeId: drill.id) == null
            ? null
            : taken,
  );
  if (name == null) return;
  await drills.rename(drill.id, name);
}

/// Replaces [drill]'s configuration with the current settings, after asking.
Future<void> overwriteDrill(
  BuildContext context,
  WidgetRef ref,
  CustomDrill drill,
) =>
    _confirmAndOverwrite(
      context,
      ref,
      drill,
      DrillConfig.fromSettings(ref.read(settingsProvider)),
      body: context.tr('drills.overwriteCurrentBody', args: {'name': drill.name}),
    );

/// Deletes [drill] after confirmation. Unlike history rows, drills are
/// user-authored and worth a confirmation step.
Future<void> deleteDrill(
  BuildContext context,
  WidgetRef ref,
  CustomDrill drill,
) async {
  final drills = ref.read(customDrillsProvider.notifier);
  final confirmed = await _confirm(
    context,
    title: context.tr('drills.deleteTitle'),
    body: context.tr('drills.deleteBody', args: {'name': drill.name}),
    confirmLabel: context.tr('common.delete'),
  );
  if (!confirmed) return;
  await drills.delete(drill.id);
}

Future<void> _confirmAndOverwrite(
  BuildContext context,
  WidgetRef ref,
  CustomDrill drill,
  DrillConfig config, {
  required String body,
}) async {
  final drills = ref.read(customDrillsProvider.notifier);
  final confirmed = await _confirm(
    context,
    title: context.tr('drills.overwriteTitle'),
    body: body,
    confirmLabel: context.tr('common.overwrite'),
  );
  if (!confirmed || !context.mounted) return;
  await drills.overwrite(drill.id, config);
  if (!context.mounted) return;
  _snack(
    context,
    context.tr('drills.overwrittenSnack', args: {'name': drill.name}),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
