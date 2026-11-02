// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../providers/video_export_provider.dart';

/// Runs [job] and shows how it goes: a progress ring with the time left,
/// and a line asking to keep the app open (the screen stays on). Then the
/// result, with Share; or what went wrong, with any detail to copy for a bug
/// report (a check mark once copied). Back cancels while it runs; once
/// the video goes to Photos it can no longer be cancelled.
Future<void> showExportDialog(BuildContext context, ExportJob job) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportDialog(job: job),
    );

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog({required this.job});

  final ExportJob job;

  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  static var _exports = 0;
  final _id = _exports++;

  /// The failure's detail is on the clipboard: Copy shows a check mark.
  var _copied = false;

  VideoExportController get _export =>
      ref.read(videoExportProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _export.start(widget.job);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(videoExportProvider(_id), (_, next) {
      if (next is ExportCancelled) Navigator.of(context).pop();
    });
    final state = ref.watch(videoExportProvider(_id));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void close() => Navigator.of(context).pop();

    Widget result(IconData icon, String text, {String? detail}) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurface),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                detail,
                textAlign: TextAlign.center,
                maxLines: 4,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        );
    final shareButton = TextButton.icon(
      icon: const Icon(Icons.share_outlined),
      label: Text(context.tr('export.share')),
      onPressed: () => _export.deliver(ExportTarget.share),
    );
    final doneButton = FilledButton(
      onPressed: close,
      child: Text(context.tr('export.done')),
    );

    final (content, actions) = switch (state) {
      ExportRunning(:final progress, :final remaining) => (
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    Center(
                      child: Text(
                        '${(progress * 100).floor()}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(context.tr('export.working'),
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                _remaining(context, remaining),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('export.keepOpen'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          [
            TextButton(
              onPressed: _export.cancel,
              child: Text(context.tr('common.cancel')),
            ),
          ],
        ),
      ExportSaving() => (
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 96,
                child: CircularProgressIndicator(strokeWidth: 6),
              ),
              const SizedBox(height: 16),
              Text(context.tr('export.saving'),
                  style: theme.textTheme.titleMedium),
            ],
          ),
          const <Widget>[],
        ),
      ExportDone(:final saved, :final shareFailed) => (
          shareFailed
              ? result(Icons.error_outline, context.tr('export.shareFailed'))
              : result(Icons.check_circle_outline,
                  context.tr(saved ? 'export.saved' : 'export.ready')),
          [shareButton, doneButton],
        ),
      ExportNotSaved(:final denied) => (
          result(
            denied ? Icons.no_photography_outlined : Icons.error_outline,
            context.tr(denied ? 'export.noAccess' : 'export.saveFailed'),
          ),
          [shareButton, doneButton],
        ),
      // A full storage says what to do; any other failure shows its detail
      // to copy into a bug report.
      ExportFailed(noSpace: true) => (
          result(Icons.error_outline, context.tr('export.noSpace')),
          [doneButton],
        ),
      ExportFailed(:final detail) => (
          result(Icons.error_outline, context.tr('export.failed'),
              detail: detail),
          [
            if (detail != null)
              TextButton.icon(
                icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                label: Text(context.tr('export.copy')),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: detail));
                  if (mounted) setState(() => _copied = true);
                },
              ),
            doneButton,
          ],
        ),
      ExportCancelled() => (const SizedBox.shrink(), const <Widget>[]),
    };

    return PopScope(
      canPop: state is! ExportRunning && state is! ExportSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _export.cancel();
      },
      child: AlertDialog(
        content: SizedBox(width: 280, child: content),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: actions,
      ),
    );
  }

  /// "About 20 s left", or minutes from 90 s on; blank until known.
  String _remaining(BuildContext context, Duration? remaining) {
    if (remaining == null) return '';
    final seconds = remaining.inSeconds;
    return seconds >= 90
        ? context.tr('export.remainingMinutes',
            args: {'minutes': (seconds / 60).round()})
        : context.tr('export.remainingSeconds',
            args: {'seconds': (seconds / 5).ceil() * 5});
  }
}
