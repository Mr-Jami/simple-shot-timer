import 'package:flutter/material.dart';

/// Tracked uppercase section label used by every settings page.
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// One control style for every "pick one of a few" setting: a row of choice
/// chips. [labelOf] names each value; [current] is the selected one.
class EnumChoice<T> extends StatelessWidget {
  const EnumChoice({
    super.key,
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T current;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(labelOf(v)),
              selected: v == current,
              onSelected: (_) => onChanged(v),
            ),
        ],
      ),
    );
  }
}
