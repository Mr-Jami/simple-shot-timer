import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../utils/slider_math.dart';
import '../utils/slider_units.dart';

/// Settings row with a labeled slider and a tap-to-type value readout.
/// Tapping the value opens a numeric edit dialog; typed values are parsed by
/// [unit], snapped to [step] and clamped to the range before [onChanged].
class SettingsIntSlider extends StatelessWidget {
  const SettingsIntSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    this.display,
    this.magnet,
    this.contentPadding,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final SliderUnit<int> unit;

  /// Optional row readout override (e.g. pluralized counts); dialog input
  /// still goes through [unit].
  final String Function(int)? display;

  /// Drags magnetically settle on multiples of this value; null disables.
  final int? magnet;
  final EdgeInsetsGeometry? contentPadding;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((max - min) / step).round();
    return _SliderRow(
      label: label,
      valueText: (display ?? unit.format)(value),
      onEditTap: () => _edit(context),
      contentPadding: contentPadding,
      slider: Slider(
        value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: divisions <= 0 ? null : divisions,
        onChanged: (v) {
          final m = magnet;
          onChanged(m == null
              ? clampToStep(v, min: min, max: max, step: step)
              : softSnap(v, min: min, max: max, step: step, magnet: m));
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context) => _showSliderEditDialog<int>(
        context: context,
        label: label,
        value: value,
        min: min,
        max: max,
        unit: unit,
        clampAndSnap: (raw) =>
            clampToStep(raw, min: min, max: max, step: step),
        onChanged: onChanged,
      );
}

/// Double-valued sibling of [SettingsIntSlider] (e.g. beep volume 0..1).
class SettingsDoubleSlider extends StatelessWidget {
  const SettingsDoubleSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final SliderUnit<double> unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SliderRow(
      label: label,
      valueText: unit.format(value),
      onEditTap: () => _edit(context),
      slider: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: ((max - min) / step).round(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _edit(BuildContext context) => _showSliderEditDialog<double>(
        context: context,
        label: label,
        value: value,
        min: min,
        max: max,
        unit: unit,
        clampAndSnap: (raw) =>
            clampToStepDouble(raw, min: min, max: max, step: step),
        onChanged: onChanged,
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.onEditTap,
    required this.slider,
    this.contentPadding,
  });

  final String label;
  final String valueText;
  final VoidCallback onEditTap;
  final Widget slider;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: contentPadding,
      title: Row(
        children: [
          Expanded(child: Text(label)),
          InkWell(
            onTap: onEditTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                valueText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      subtitle: slider,
    );
  }
}

/// Prefilled numeric entry dialog. Commits via [onChanged] only when the
/// input parses and differs from [value]; cancel or unparsable input is a
/// no-op (same convention as the review screen's add-shot dialog).
Future<void> _showSliderEditDialog<T extends num>({
  required BuildContext context,
  required String label,
  required T value,
  required T min,
  required T max,
  required SliderUnit<T> unit,
  required T Function(T raw) clampAndSnap,
  required ValueChanged<T> onChanged,
}) async {
  final initial = unit.editText(value);
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  T? submit(String text) {
    final parsed = unit.parse(text);
    return parsed == null ? null : clampAndSnap(parsed);
  }

  final result = await showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: unit.isDecimal),
        decoration: InputDecoration(
          suffixText: unit.suffix.trim(),
          helperText: ctx.tr(
            'settings.editRange',
            args: {'range': unit.rangeHint(min, max)},
          ),
        ),
        onSubmitted: (text) => Navigator.pop(ctx, submit(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, submit(controller.text)),
          child: Text(ctx.tr('common.ok')),
        ),
      ],
    ),
  );
  if (result != null && result != value) {
    onChanged(result);
  }
}
