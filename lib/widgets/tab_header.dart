import 'package:flutter/material.dart';

/// Heading row for a root tab: a large title on the page surface with the
/// tab's actions beside it, instead of an app bar. The bottom bar is the only
/// chrome on a tab; a bar with a back arrow is reserved for pushed detail
/// pages, where it means "back returns".
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
