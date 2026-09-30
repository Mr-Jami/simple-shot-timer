import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_localizations.dart';
import '../models/custom_drill.dart';

/// Prompts for a drill name. Resolves to the normalized name, or null when
/// cancelled. [validate] receives the normalized candidate and returns an
/// error to show inline (which also disables confirm), or null if it's fine.
Future<String?> showDrillNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? Function(String normalized)? validate,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _DrillNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initial: initial,
        validate: validate,
      ),
    );

/// Stateful so the confirm button can follow the text live, and so the
/// controller is disposed with the dialog's own lifecycle (after the close
/// animation) rather than by the caller.
class _DrillNameDialog extends StatefulWidget {
  const _DrillNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.validate,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? Function(String normalized)? validate;

  @override
  State<_DrillNameDialog> createState() => _DrillNameDialogState();
}

class _DrillNameDialogState extends State<_DrillNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      )
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String get _normalized => CustomDrill.normalizeName(_controller.text);

  String? get _error =>
      _normalized.isEmpty ? null : widget.validate?.call(_normalized);

  bool get _canConfirm => _normalized.isNotEmpty && _error == null;

  void _confirm() {
    if (_canConfirm) Navigator.pop(context, _normalized);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          LengthLimitingTextInputFormatter(CustomDrill.maxNameLength),
        ],
        decoration: InputDecoration(
          labelText: context.tr('drills.nameLabel'),
          errorText: _error,
        ),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: _canConfirm ? _confirm : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
