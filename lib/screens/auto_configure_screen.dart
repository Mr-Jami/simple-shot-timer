import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/calibration_shot.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../services/auto_configure.dart';

/// Listens to a series of shots fired by the user, then proposes a sensitivity
/// + frequency band tuned to that environment / ammunition.
class AutoConfigureScreen extends ConsumerStatefulWidget {
  const AutoConfigureScreen({super.key});

  @override
  ConsumerState<AutoConfigureScreen> createState() =>
      _AutoConfigureScreenState();
}

class _AutoConfigureScreenState extends ConsumerState<AutoConfigureScreen> {
  final List<CalibrationShot> _shots = [];
  StreamSubscription<CalibrationShot>? _sub;
  bool _running = false;
  String? _error;
  CalibrationSuggestion? _suggestion;

  Future<void> _start() async {
    final detector = ref.read(shotDetectorProvider);
    setState(() {
      _shots.clear();
      _suggestion = null;
      _error = null;
    });
    try {
      await detector.startCalibration();
    } catch (e) {
      setState(() => _error = '$e');
      return;
    }
    _sub = detector.calibrationEvents.listen((shot) {
      setState(() => _shots.add(shot));
    });
    setState(() => _running = true);
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await ref.read(shotDetectorProvider).stop();
    setState(() {
      _running = false;
      _suggestion = suggestFromShots(_shots);
    });
  }

  Future<void> _apply() async {
    final s = _suggestion;
    if (s == null) return;
    await ref.read(settingsProvider.notifier).update((c) => c.copyWith(
          sensitivityPercent: s.sensitivityPercent,
          bandFilterEnabled: true,
          bandLowHz: s.bandLowHz,
          bandHighHz: s.bandHighHz,
        ));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_running) {
      ref.read(shotDetectorProvider).stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('autoConfig.title'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('autoConfig.instruction')),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _running ? _stop : _start,
                    icon: Icon(_running ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(_running
                        ? context.tr('autoConfig.stop')
                        : context.tr('autoConfig.start')),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  context.tr('autoConfig.shotCount',
                      args: {'count': _shots.length}),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _shots.isEmpty
                  ? Center(
                      child: Text(
                        _running
                            ? context.tr('autoConfig.listening')
                            : context.tr('autoConfig.empty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _ShotList(shots: _shots),
            ),
            if (_suggestion != null)
              _SuggestionCard(
                suggestion: _suggestion!,
                onApply: _apply,
                onDiscard: () => setState(() => _suggestion = null),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShotList extends StatelessWidget {
  const _ShotList({required this.shots});

  final List<CalibrationShot> shots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: shots.length,
      itemBuilder: (context, i) {
        final s = shots[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '#${i + 1}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  context.tr('autoConfig.shotPeak',
                      args: {'percent': (s.peakAmplitude * 100).round()}),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  context.tr('autoConfig.shotBand', args: {
                    'low': s.lowEdgeHz.round(),
                    'high': s.highEdgeHz.round(),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onApply,
    required this.onDiscard,
  });

  final CalibrationSuggestion suggestion;
  final VoidCallback onApply;
  final VoidCallback onDiscard;

  String _formatHz(int hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('autoConfig.suggestionTitle'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SuggestionRow(
              label: context.tr('autoConfig.suggestSensitivity'),
              value: '${suggestion.sensitivityPercent}%',
            ),
            _SuggestionRow(
              label: context.tr('autoConfig.suggestBand'),
              value:
                  '${_formatHz(suggestion.bandLowHz)} – ${_formatHz(suggestion.bandHighHz)}',
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDiscard,
                  child: Text(context.tr('common.discard')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onApply,
                  child: Text(context.tr('autoConfig.apply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
