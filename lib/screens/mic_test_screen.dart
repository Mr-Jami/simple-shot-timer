import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../widgets/mic_level_meter.dart';

/// Live microphone meter used to dial in sensitivity without running a string.
/// Make noise at the source you intend to detect (clap, gunshot at the range)
/// and adjust the sensitivity slider until the red line sits just below the
/// expected peak.
class MicTestScreen extends ConsumerStatefulWidget {
  const MicTestScreen({super.key});

  @override
  ConsumerState<MicTestScreen> createState() => _MicTestScreenState();
}

class _MicTestScreenState extends ConsumerState<MicTestScreen> {
  Timer? _ticker;
  double _level = 0;
  double _peakHold = 0;
  DateTime _peakAt = DateTime.fromMillisecondsSinceEpoch(0);
  double? _dominantFreqHz;
  double _dominantFreqStrength = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final detector = ref.read(shotDetectorProvider);
    try {
      await detector.startMonitoring();
    } catch (e) {
      setState(() => _error = '$e');
      return;
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final lvl = detector.lastPeak;
      setState(() {
        _level = lvl;
        _dominantFreqHz = detector.lastDominantFreqHz;
        _dominantFreqStrength = detector.lastDominantFreqStrength;
        if (lvl > _peakHold ||
            DateTime.now().difference(_peakAt) >
                const Duration(milliseconds: 1500)) {
          _peakHold = lvl;
          _peakAt = DateTime.now();
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    ref.read(shotDetectorProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final threshold = settings.detectionThreshold;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('micTest.title'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Text(context.tr('micTest.instruction')),
            const SizedBox(height: 24),
            MicLevelMeter(level: _level, threshold: threshold, height: 22),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('micTest.peakHold',
                        args: {'percent': (_peakHold * 100).round()}),
                  ),
                ),
                Expanded(
                  child: Text(
                    context.tr('micTest.threshold',
                        args: {'percent': (threshold * 100).round()}),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FrequencyReadout(
              freqHz: _dominantFreqHz,
              strength: _dominantFreqStrength,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final audio = ref.read(audioServiceProvider);
                  final volume = ref.read(settingsProvider).beepVolume;
                  audio.playStartBeep(volume: volume);
                },
                icon: const Icon(Icons.graphic_eq),
                label: Text(context.tr('micTest.playTestBeep')),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Text(context.tr('micTest.sensitivity')),
                Expanded(
                  child: Slider(
                    value: settings.sensitivityPercent.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${settings.sensitivityPercent}%',
                    onChanged: (v) => notifier.update(
                      (c) => c.copyWith(sensitivityPercent: v.round()),
                    ),
                  ),
                ),
                Text('${settings.sensitivityPercent}%'),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('micTest.tip'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FrequencyReadout extends StatelessWidget {
  const _FrequencyReadout({required this.freqHz, required this.strength});

  final double? freqHz;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = strength < 0.001 || freqHz == null;
    final color = faded
        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
        : theme.colorScheme.onSurface;
    final text = freqHz == null
        ? context.tr('micTest.freqIdle')
        : context.tr(
            'micTest.freqReading',
            args: {'hz': freqHz!.toStringAsFixed(0)},
          );
    return Row(
      children: [
        Icon(Icons.equalizer, size: 18, color: color),
        const SizedBox(width: 8),
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
      ],
    );
  }
}
