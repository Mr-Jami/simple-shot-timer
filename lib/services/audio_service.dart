import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Generates and plays a sine-wave start/par beep entirely from memory.
class AudioService {
  AudioService() {
    _player.setReleaseMode(ReleaseMode.stop);
    // Important: play the beep WITHOUT requesting audio focus so the active
    // mic stream (AudioRecord) is not paused/muted while we beep. We also
    // route the beep through the media stream and mark the content as
    // sonification so it plays alongside other audio cleanly.
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        // Route through the media stream so the user's media-volume slider
        // controls beep loudness; using sonification/assistance routes can
        // play silently on some devices.
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        // Do NOT request audio focus — that's what paused the AudioRecord
        // stream on the previous build.
        audioFocus: AndroidAudioFocus.none,
        audioMode: AndroidAudioMode.normal,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.defaultToSpeaker,
        },
      ),
    ));
  }

  final AudioPlayer _player = AudioPlayer();
  final Map<String, Uint8List> _cache = {};

  // Fixed beep specs — a piezo-style tone in the ~2.3 kHz range used by most
  // club shot timers. Start beep is short; the par (end) beep is longer so
  // shooters can clearly distinguish it without watching the screen.
  // Public so ShotDetector can centre its notch filter on the same frequency.
  static const int beepFrequencyHz = 2325;
  static const int startBeepDurationMs = 300;
  static const int parBeepDurationMs = 700;

  Future<void> playStartBeep({required double volume}) =>
      _play(beepFrequencyHz, startBeepDurationMs, volume);

  Future<void> playParBeep({required double volume}) =>
      _play(beepFrequencyHz, parBeepDurationMs, volume);

  Future<void> _play(int frequencyHz, int durationMs, double volume) async {
    final key = '$frequencyHz:$durationMs';
    final wav = _cache.putIfAbsent(key, () => _generateWav(frequencyHz, durationMs));
    await _player.setVolume(volume.clamp(0.0, 1.0));
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
    _cache.clear();
  }

  static Uint8List _generateWav(int frequencyHz, int durationMs) {
    const sampleRate = 44100;
    const bitsPerSample = 16;
    const channels = 1;
    final totalSamples = (sampleRate * durationMs / 1000).round();
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = totalSamples * blockAlign;
    final fileSize = 36 + dataSize;

    final bytes = BytesBuilder(copy: false);
    void writeStr(String s) => bytes.add(s.codeUnits);
    void writeU32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      bytes.add(b.buffer.asUint8List());
    }
    void writeU16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      bytes.add(b.buffer.asUint8List());
    }

    writeStr('RIFF');
    writeU32(fileSize);
    writeStr('WAVE');
    writeStr('fmt ');
    writeU32(16);
    writeU16(1); // PCM
    writeU16(channels);
    writeU32(sampleRate);
    writeU32(byteRate);
    writeU16(blockAlign);
    writeU16(bitsPerSample);
    writeStr('data');
    writeU32(dataSize);

    // Raised-cosine (half-Hann) attack/release. A linear ramp has a
    // discontinuity in its derivative at both ends, which the ear (and our
    // shot detector) reads as a broadband click. The cosine taper is C1
    // smooth, so the onset/offset add only narrow-band energy near the
    // carrier — which the detector's notch filter already removes.
    const attackMs = 8;
    const releaseMs = 20;
    const attackSamples = sampleRate * attackMs ~/ 1000;
    const releaseSamples = sampleRate * releaseMs ~/ 1000;
    final samples = ByteData(dataSize);
    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double envelope = 1.0;
      if (i < attackSamples) {
        final x = i / attackSamples;
        envelope = 0.5 - 0.5 * math.cos(math.pi * x);
      } else if (i > totalSamples - releaseSamples) {
        final x = (totalSamples - i) / releaseSamples;
        envelope = 0.5 - 0.5 * math.cos(math.pi * x);
      }
      final value = math.sin(2 * math.pi * frequencyHz * t) * envelope;
      final scaled = (value * 32767 * 0.9).round();
      samples.setInt16(i * 2, scaled, Endian.little);
    }
    bytes.add(samples.buffer.asUint8List());

    return bytes.toBytes();
  }
}
