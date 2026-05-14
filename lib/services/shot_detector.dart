import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Streams PCM samples from the microphone and emits detection events
/// (timestamps in ms, read from the supplied [Stopwatch]) whenever a peak
/// exceeding the configured threshold is observed, subject to a minimum
/// inter-shot interval (echo filter) and an initial blanking window.
class ShotDetector {
  ShotDetector();

  static const int sampleRate = 44100;
  static const int _bytesPerSample = 2; // pcm16

  /// Approximate Android `AudioRecord` chunk delivery delay. Chunks arrive in
  /// our handler this many ms after their last sample was actually captured,
  /// so we subtract it when computing a shot's clock-relative timestamp.
  static const int _assumedDeliveryDelayMs = 100;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<int> _events = StreamController<int>.broadcast();
  StreamSubscription<Uint8List>? _sub;

  Stopwatch? _clock;
  int _blankingUntilMs = 0;
  int _echoFilterMs = 80;
  int _lastShotMs = -1 << 30;
  double _threshold = 0.5;
  double _lastPeak = 0;

  // Diagnostics: surfaced via getters to drive the mic-test screen.
  int _chunksReceived = 0;
  int _lastChunkBytes = 0;
  double _maxPeakEver = 0;
  String? _lastError;

  Stream<int> get events => _events.stream;

  /// Most recent normalized peak amplitude observed (0..1).
  /// Useful for driving a live VU-style level meter in the UI.
  double get lastPeak => _lastPeak;
  double get currentThreshold => _threshold;

  int get chunksReceived => _chunksReceived;
  int get lastChunkBytes => _lastChunkBytes;
  double get maxPeakEver => _maxPeakEver;
  String? get lastError => _lastError;

  bool get isRunning => _sub != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts the mic stream in "monitor only" mode: peaks are tracked into
  /// [lastPeak] but no events are emitted. Used by the mic test in Settings.
  Future<void> startMonitoring() async {
    if (!await _recorder.hasPermission()) {
      _lastError = 'permission denied';
      throw StateError('Microphone permission denied');
    }
    _threshold = double.infinity;
    _blankingUntilMs = 1 << 30;
    _lastPeak = 0;
    _chunksReceived = 0;
    _lastChunkBytes = 0;
    _maxPeakEver = 0;
    _lastError = null;
    _clock = Stopwatch()..start();
    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ));
      _sub = stream.listen(
        _onChunk,
        onError: (Object e, StackTrace st) {
          _lastError = 'stream error: $e';
        },
        onDone: () {
          _lastError = '${_lastError ?? ''} [stream done]';
        },
      );
    } catch (e) {
      _lastError = 'startStream threw: $e';
      rethrow;
    }
  }

  Future<void> start({
    required Stopwatch clock,
    required double threshold,
    required int echoFilterMs,
    int blankingMs = 0,
  }) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    _clock = clock;
    _threshold = threshold.clamp(0.0, 1.0);
    _echoFilterMs = echoFilterMs;
    _blankingUntilMs = clock.elapsedMilliseconds + blankingMs;
    _lastShotMs = -1 << 30;
    _lastPeak = 0;
    _chunksReceived = 0;
    _lastChunkBytes = 0;
    _maxPeakEver = 0;
    _lastError = null;

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ));
    _sub = stream.listen(_onChunk, onError: _events.addError);
  }

  void _onChunk(Uint8List bytes) {
    _chunksReceived++;
    _lastChunkBytes = bytes.lengthInBytes;
    final clock = _clock;
    if (clock == null) return;
    final chunkArrivalMs = clock.elapsedMilliseconds;

    final sampleCount = bytes.lengthInBytes ~/ _bytesPerSample;
    if (sampleCount == 0) return;
    // Copy into an aligned Int16List to avoid any byte-alignment issues that
    // can occur when the underlying buffer has a non-zero or odd offset.
    final samples = Int16List(sampleCount);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little);
    }

    var peak = 0;
    var peakIdx = 0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      final abs = v < 0 ? -v : v;
      if (abs > peak) {
        peak = abs;
        peakIdx = i;
      }
    }
    final normalized = peak / 32767.0;
    _lastPeak = normalized;
    if (normalized > _maxPeakEver) _maxPeakEver = normalized;

    if (chunkArrivalMs < _blankingUntilMs) return;
    if (normalized < _threshold) return;

    // Locate the peak in time: chunk last-sample-captured time is
    // chunkArrivalMs - delivery_delay; peak captured time is that minus
    // (samples after the peak) / sampleRate.
    final tailMs = ((sampleCount - peakIdx) * 1000) ~/ sampleRate;
    final shotMs = chunkArrivalMs - _assumedDeliveryDelayMs - tailMs;

    if (shotMs - _lastShotMs < _echoFilterMs) return;
    if (shotMs < _blankingUntilMs) return;

    _lastShotMs = shotMs;
    _events.add(shotMs);
  }

  /// Suppresses shot events until the clock reaches `now + additionalMs`.
  /// Call right before playing a beep so the beep itself (and a short echo
  /// tail) does not register as a detected shot.
  void extendBlankingForMs(int additionalMs) {
    final clock = _clock;
    if (clock == null) return;
    final until = clock.elapsedMilliseconds + additionalMs;
    if (until > _blankingUntilMs) _blankingUntilMs = until;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _clock = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _recorder.dispose();
  }
}
