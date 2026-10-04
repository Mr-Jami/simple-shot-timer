import 'package:flutter/material.dart';

import '../models/custom_drill.dart';
import '../models/drill_config.dart';

/// One saved drill as a list row: name, one-line summary and a check mark
/// when it is the drill the current settings match. Used by the Drills tab
/// (issue #24).
class DrillTile extends StatelessWidget {
  const DrillTile({
    super.key,
    required this.drill,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final CustomDrill drill;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        active ? Icons.check_circle : Icons.bookmark_border,
        color: active ? theme.colorScheme.primary : null,
      ),
      title: Text(
        drill.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(drill.config.summary(context)),
      selected: active,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
