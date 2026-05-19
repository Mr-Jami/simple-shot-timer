import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../models/calibration_shot.dart';
import '../utils/fft.dart';
import 'audio_service.dart';
import 'biquad.dart';

/// Streams PCM samples from the microphone and emits detection events
/// (timestamps in ms, read from the supplied [Stopwatch]) whenever a peak
/// exceeding the configured threshold is observed, subject to a minimum
/// inter-shot interval (echo filter) and an initial blanking window.
///
/// A narrow notch filter at [AudioService.beepFrequencyHz] is applied to the
/// PCM stream before peak detection, so the start/par beep itself does not
/// register as a shot and — more importantly — a shot fired during the beep
/// still does.
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
  final StreamController<CalibrationShot> _calibrationEvents =
      StreamController<CalibrationShot>.broadcast();
  StreamSubscription<Uint8List>? _sub;

  /// Stream of shots captured while in calibration mode. Empty during live
  /// runs and mic monitoring.
  Stream<CalibrationShot> get calibrationEvents => _calibrationEvents.stream;

  bool _calibrationMode = false;
  double _calibrationThreshold = 0.10;
  int _lastCalibrationShotMs = -1 << 30;
  static const int _calibrationEchoMs = 300;
  static const int _calibrationFftWindow = 2048;
  // Cascade a notch at the fundamental + 2nd/3rd harmonics. Phone speakers
  // distort loud tones into harmonic content (4.65 kHz, 6.97 kHz) that would
  // otherwise sail past a single notch at 2.3 kHz and register as shots.
  // Q≈8 gives each notch ~290 Hz bandwidth — wide enough to absorb the
  // beep's envelope sidelobes and a few-Hz speaker drift, narrow enough that
  // a broadband gunshot loses only ~2% of its band-summed energy.
  final List<Biquad> _beepNotches = List<Biquad>.unmodifiable([
    for (final mult in const [1, 2, 3])
      Biquad.notch(
        sampleRate: sampleRate.toDouble(),
        frequencyHz: (AudioService.beepFrequencyHz * mult).toDouble(),
        q: 8,
      ),
  ]);

  // Bandpass cascade (HPF + LPF) configured per-run from settings. Null
  // when the user disables the frequency-band filter.
  Biquad? _highpass;
  Biquad? _lowpass;

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

  // Rolling buffer + FFT scratch for dominant-frequency analysis. Only filled
  // in monitoring mode; the live detection path skips this work.
  static const int _fftSize = 4096;
  final Float64List _fftBuffer = Float64List(_fftSize);
  int _fftWritePos = 0;
  bool _fftBufferFull = false;
  bool _measureFrequency = false;
  double? _lastDominantFreqHz;
  double _lastDominantFreqStrength = 0;

  Stream<int> get events => _events.stream;

  /// Most recent normalized peak amplitude observed (0..1).
  /// Useful for driving a live VU-style level meter in the UI.
  double get lastPeak => _lastPeak;
  double get currentThreshold => _threshold;

  int get chunksReceived => _chunksReceived;
  int get lastChunkBytes => _lastChunkBytes;
  double get maxPeakEver => _maxPeakEver;
  String? get lastError => _lastError;

  /// Dominant mic frequency in Hz observed during monitoring, or null if the
  /// signal is currently too quiet to estimate. Always null during a live run.
  double? get lastDominantFreqHz => _lastDominantFreqHz;

  /// Normalized strength of the FFT peak (0..1). Useful for the UI to grey
  /// out the frequency readout when the mic is quiet.
  double get lastDominantFreqStrength => _lastDominantFreqStrength;

  bool get isRunning => _sub != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts the mic stream in calibration mode: bypass the notch + bandpass,
  /// use a permissive [minPeak] threshold, and emit one [CalibrationShot] per
  /// captured impulse on [calibrationEvents]. Each event carries the impulse's
  /// peak amplitude and its 10–90% spectral band, computed via FFT on a
  /// window centred on the peak.
  Future<void> startCalibration({double minPeak = 0.10}) async {
    if (!await _recorder.hasPermission()) {
      _lastError = 'permission denied';
      throw StateError('Microphone permission denied');
    }
    _calibrationMode = true;
    _calibrationThreshold = minPeak.clamp(0.0, 1.0);
    _lastCalibrationShotMs = -1 << 30;
    _blankingUntilMs = 1 << 30; // calibration never emits live shot events
    _lastPeak = 0;
    _chunksReceived = 0;
    _lastChunkBytes = 0;
    _maxPeakEver = 0;
    _lastError = null;
    _fftWritePos = 0;
    _fftBufferFull = false;
    _lastDominantFreqHz = null;
    _lastDominantFreqStrength = 0;
    _measureFrequency = false;
    _configureBandpass(enabled: false, lowHz: 0, highHz: 0);
    _clock = Stopwatch()..start();
    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.unprocessed,
        ),
      ));
      _sub = stream.listen(
        _onChunk,
        onError: (Object e, StackTrace st) {
          _lastError = 'stream error: $e';
        },
      );
    } catch (e) {
      _lastError = 'startStream threw: $e';
      rethrow;
    }
  }

  void _configureBandpass({
    required bool enabled,
    required int lowHz,
    required int highHz,
  }) {
    if (!enabled || highHz <= lowHz) {
      _highpass = null;
      _lowpass = null;
      return;
    }
    _highpass = Biquad.highpass(
      sampleRate: sampleRate.toDouble(),
      cutoffHz: lowHz.toDouble(),
    );
    _lowpass = Biquad.lowpass(
      sampleRate: sampleRate.toDouble(),
      cutoffHz: highHz.toDouble(),
    );
  }

  /// Starts the mic stream in "monitor only" mode: peaks are tracked into
  /// [lastPeak] but no events are emitted. Used by the mic test in Settings.
  Future<void> startMonitoring({
    bool bandFilterEnabled = false,
    int bandLowHz = 0,
    int bandHighHz = 0,
  }) async {
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
    for (final n in _beepNotches) {
      n.reset();
    }
    _configureBandpass(
      enabled: bandFilterEnabled,
      lowHz: bandLowHz,
      highHz: bandHighHz,
    );
    _measureFrequency = true;
    _calibrationMode = false;
    _fftWritePos = 0;
    _fftBufferFull = false;
    _lastDominantFreqHz = null;
    _lastDominantFreqStrength = 0;
    _clock = Stopwatch()..start();
    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // Bypass OEM voice DSP (AGC, noise suppression). Default audio source
        // ducks loud transients like gunshots well below threshold.
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.unprocessed,
        ),
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
    bool bandFilterEnabled = false,
    int bandLowHz = 0,
    int bandHighHz = 0,
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
    for (final n in _beepNotches) {
      n.reset();
    }
    _configureBandpass(
      enabled: bandFilterEnabled,
      lowHz: bandLowHz,
      highHz: bandHighHz,
    );
    _measureFrequency = false;
    _calibrationMode = false;

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      // Bypass OEM voice DSP for the same reason as monitoring above: AGC
      // and noise suppression destroy impulsive gunshot transients.
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.unprocessed,
      ),
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
    if (_calibrationMode) {
      _processCalibrationChunk(samples, chunkArrivalMs);
      return;
    }
    if (_measureFrequency) _updateDominantFrequency(samples);
    for (final n in _beepNotches) {
      n.processInt16InPlace(samples);
    }
    _highpass?.processInt16InPlace(samples);
    _lowpass?.processInt16InPlace(samples);

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

  void _updateDominantFrequency(Int16List samples) {
    // Append into the rolling buffer; when it wraps once we have enough data
    // for an FFT and can start emitting readings.
    for (var i = 0; i < samples.length; i++) {
      _fftBuffer[_fftWritePos] = samples[i] / 32768.0;
      _fftWritePos++;
      if (_fftWritePos >= _fftSize) {
        _fftWritePos = 0;
        _fftBufferFull = true;
      }
    }
    if (!_fftBufferFull) return;

    // Linearize the ring buffer into a fresh chronologically-ordered view —
    // the FFT windowing in peakFrequencyHz assumes samples[0] is the oldest.
    final linear = Float64List(_fftSize);
    final tail = _fftSize - _fftWritePos;
    linear.setRange(0, tail, _fftBuffer, _fftWritePos);
    linear.setRange(tail, _fftSize, _fftBuffer, 0);

    // Don't bother running the FFT when the room is silent — protects the
    // peak picker from latching onto noise floor fluctuations.
    var sumSq = 0.0;
    for (var i = 0; i < _fftSize; i++) {
      sumSq += linear[i] * linear[i];
    }
    final rms = sumSq > 0 ? (sumSq / _fftSize) : 0.0;
    if (rms < 1e-5) {
      _lastDominantFreqStrength = 0;
      return;
    }
    _lastDominantFreqStrength = rms.clamp(0.0, 1.0);
    _lastDominantFreqHz = peakFrequencyHz(
      samples: linear,
      sampleRate: sampleRate.toDouble(),
    );
  }

  void _processCalibrationChunk(Int16List samples, int chunkArrivalMs) {
    // Always fill the ring buffer first so the spectral window has up-to-date
    // context regardless of whether this chunk crosses the threshold.
    for (var i = 0; i < samples.length; i++) {
      _fftBuffer[_fftWritePos] = samples[i] / 32768.0;
      _fftWritePos++;
      if (_fftWritePos >= _fftSize) {
        _fftWritePos = 0;
        _fftBufferFull = true;
      }
    }

    // Find this chunk's peak.
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

    if (normalized < _calibrationThreshold) return;
    if (!_fftBufferFull) return;

    // Calibration-specific echo filter, in chunk-arrival time (the absolute
    // timestamps don't matter for the user-facing flow).
    if (chunkArrivalMs - _lastCalibrationShotMs < _calibrationEchoMs) return;
    _lastCalibrationShotMs = chunkArrivalMs;

    // Linearise the ring buffer into chronological order.
    final linear = Float64List(_fftSize);
    final tail = _fftSize - _fftWritePos;
    linear.setRange(0, tail, _fftBuffer, _fftWritePos);
    linear.setRange(tail, _fftSize, _fftBuffer, 0);

    // Position the peak in the linearised buffer: the chunk we just wrote
    // occupies the last `samples.length` slots, so the peak lives at offset
    // (_fftSize - samples.length + peakIdx).
    final peakLogical = _fftSize - samples.length + peakIdx;
    final windowStart = peakLogical - _calibrationFftWindow ~/ 2;

    final window = Float64List(_calibrationFftWindow);
    for (var i = 0; i < _calibrationFftWindow; i++) {
      final src = windowStart + i;
      window[i] = (src < 0 || src >= _fftSize) ? 0.0 : linear[src];
    }

    final band = spectralBand(
      samples: window,
      sampleRate: sampleRate.toDouble(),
    );
    if (band == null) return;
    _calibrationEvents.add(CalibrationShot(
      peakAmplitude: normalized,
      lowEdgeHz: band.lowEdgeHz,
      highEdgeHz: band.highEdgeHz,
      dominantHz: band.dominantHz,
    ));
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
    _calibrationMode = false;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _calibrationEvents.close();
    await _recorder.dispose();
  }
}
