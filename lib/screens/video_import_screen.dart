// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/timer_string.dart';
import '../providers/clip_editor_provider.dart';
import '../providers/video_import_provider.dart';
import '../services/video/clip_check.dart';
import '../services/video/clip_picker.dart';
import 'video_editor_screen.dart';
import 'video_flows.dart';

/// Hosts one import (see [VideoImportController]): opens the picker on its
/// first frame, shows the Analyzing view only when the work takes long
/// enough to notice, names a problem, and hands a ready clip to the editor.
class VideoImportScreen extends ConsumerStatefulWidget {
  const VideoImportScreen({super.key, required this.source, this.reopen});

  final ClipSource source;
  final TimerString? reopen;

  @override
  ConsumerState<VideoImportScreen> createState() => _VideoImportScreenState();
}

class _VideoImportScreenState extends ConsumerState<VideoImportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) return;
    ref.read(videoImportProvider.notifier).start(widget.source);
  }

  void _chooseAnother() {
    ref.invalidate(videoImportProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _open(ImportReady ready) async {
    final saved = widget.reopen;
    if (saved != null && !ready.clip.matches(saved)) {
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('review.differentVideoTitle')),
          content: Text(context.tr('review.differentVideoBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('review.openAnyway')),
            ),
          ],
        ),
      );
      if (open != true) {
        await ready.session.dispose();
        if (mounted) Navigator.of(context).pop();
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => VideoEditorScreen(
        args: ClipEditorArgs(
          clip: ready.clip,
          session: ready.session,
          importedAt: ready.importedAt,
          saved: saved,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(videoImportProvider, (_, next) {
      switch (next) {
        case ImportCancelled():
          Navigator.of(context).pop();
        case ImportReady():
          _open(next);
        default:
      }
    });
    final state = ref.watch(videoImportProvider);
    return PopScope(
      canPop: state is! ImportWorking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(videoImportProvider.notifier).cancel();
      },
      child: Scaffold(
        body: SafeArea(
          child: switch (state) {
            ImportWorking(visible: true, :final step, :final progress) =>
              _AnalyzingView(
                step: step,
                progress: progress,
                onCancel: ref.read(videoImportProvider.notifier).cancel,
              ),
            ImportProblem(:final problem) => _ProblemView(
                problem: problem,
                onChooseAnother: _chooseAnother,
              ),
            _ => const SizedBox.expand(),
          },
        ),
      ),
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView({
    required this.step,
    required this.progress,
    required this.onCancel,
  });

  final ImportStep step;
  final double? progress;
  final VoidCallback onCancel;

  static const _steps = [
    (ImportStep.reading, 'video.step.reading'),
    (ImportStep.decoding, 'video.step.decoding'),
    (ImportStep.analyzing, 'video.step.analyzing'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Text(
            context.tr('video.analyzing'),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          for (final (s, key) in _steps)
            _StepRow(
              label: context.tr(key),
              state: s.index < step.index
                  ? _StepState.done
                  : s == step
                      ? _StepState.current
                      : _StepState.upcoming,
              progress: s == step ? progress : null,
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  context.tr('video.privacy'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onCancel,
            child: Text(context.tr('common.cancel')),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state, this.progress});

  final String label;
  final _StepState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final faded = state == _StepState.upcoming;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: switch (state) {
                  _StepState.done =>
                    Icon(Icons.check_circle, color: scheme.onSurface),
                  _StepState.current => const Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  _StepState.upcoming =>
                    Icon(Icons.circle_outlined, color: scheme.onSurfaceVariant),
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: faded ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (state == _StepState.current && progress != null)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: LinearProgressIndicator(value: progress),
            ),
        ],
      ),
    );
  }
}

class _ProblemView extends StatelessWidget {
  const _ProblemView({required this.problem, required this.onChooseAnother});

  final ClipProblem problem;
  final VoidCallback onChooseAnother;

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
              Icons.videocam_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('video.problem.title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(clipProblemKey(problem)),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.video_library_outlined),
              label: Text(context.tr('video.chooseAnother')),
              onPressed: onChooseAnother,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('common.cancel')),
            ),
          ],
        ),
      ),
    );
  }
}
