import 'dart:math' as math;
import 'dart:typed_data';

/// Detects the **onset** of the start/par beep in the mic PCM stream so the run
/// clock can anchor `t=0` to the moment the beep is actually *audible* — not the
/// (earlier) moment playback was requested. The gap between the two is the audio
/// output latency (decode + buffering + DAC + speaker, plus any Bluetooth route
/// delay), empirically ~0.35s on a phone speaker, which otherwise inflates every
/// shot time. See issue #18.
///
/// The beep is a sustained sine tone at a single known frequency, so a Goertzel
/// filter — a single-bin DFT, far cheaper than a full FFT — is the natural tool.
/// Two properties make it robust against the gunshots it runs alongside:
///
///  * **Frequency selectivity:** it only sums energy at the beep frequency, so
///    broadband room noise barely registers.
///  * **A sustain requirement:** the onset only fires after [sustainBlocks]
///    consecutive blocks stay above threshold (~12 ms). The beep lasts 300 ms so
///    it sails through; an impulsive gunshot (~2 ms) deposits energy in at most a
///    block or two and is rejected, even though its broadband transient does
///    touch the beep frequency.
///
/// This is intentionally a small, pure, allocation-free unit: it owns no clock
/// and no stream. [ShotDetector] feeds it raw PCM (before the beep notch) and
/// converts the returned in-chunk sample index into a clock timestamp.
class BeepOnsetDetector {
  BeepOnsetDetector({
    required double sampleRate,
    required double frequencyHz,
    this.blockSize = 256,
    this.sustainBlocks = 2,
    this.absoluteThreshold = 0.0004,
    this.relativeFactor = 8.0,
    this.floorAttack = 0.1,
  }) : _coeff = 2 * math.cos(2 * math.pi * frequencyHz / sampleRate);

  /// Samples per Goertzel block. ~5.8 ms at 44.1 kHz — fine enough to localise
  /// the onset to well within the latency we're correcting for.
  final int blockSize;

  /// Consecutive above-threshold blocks required before declaring an onset.
  /// This is what distinguishes the sustained beep from an impulsive shot.
  final int sustainBlocks;

  /// Absolute normalized-power floor. Guards against latching onto silence or
  /// faint tonal noise when the adaptive floor is still near zero.
  final double absoluteThreshold;

  /// A block must exceed this multiple of the adaptive noise floor to count.
  final double relativeFactor;

  /// EMA weight for adapting the noise floor on non-signal blocks.
  final double floorAttack;

  final double _coeff;

  double _floor = 0;
  int _runCount = 0;
  int _runStartInChunk = 0;
  bool _triggered = false;

  /// Re-arms the detector for a fresh beep. Call right before each beep fires.
  void reset() {
    _floor = 0;
    _runCount = 0;
    _runStartInChunk = 0;
    _triggered = false;
  }

  /// Feeds one PCM chunk. Returns the in-chunk sample index of the detected
  /// onset, or -1 if no onset was confirmed in (or carried into) this chunk.
  /// Once it returns an onset it stays latched until [reset].
  int process(Int16List samples) {
    if (_triggered) return -1;

    // A run already in progress from the previous chunk is, for the purpose of
    // this chunk's index math, treated as starting at the chunk boundary. Runs
    // almost never span chunks (a chunk holds far more than [sustainBlocks]
    // blocks), so the worst-case error is a few ms early — negligible against
    // the hundreds of ms of latency being measured.
    if (_runCount > 0) _runStartInChunk = 0;

    for (var start = 0; start + blockSize <= samples.length;
        start += blockSize) {
      final power = _blockPower(samples, start);
      final crosses =
          power > absoluteThreshold && power > _floor * relativeFactor;
      if (crosses) {
        if (_runCount == 0) _runStartInChunk = start;
        _runCount++;
        if (_runCount >= sustainBlocks) {
          _triggered = true;
          return _runStartInChunk;
        }
      } else {
        _runCount = 0;
        // Adapt the noise floor only on blocks that aren't part of a candidate
        // onset, so the beep itself can't drag the floor up to meet it.
        _floor = _floor == 0 ? power : _floor + floorAttack * (power - _floor);
      }
    }
    return -1;
  }

  /// Length-normalized Goertzel power at the configured frequency for the block
  /// starting at [start]. Dividing by `blockSize²` makes the value
  /// scale-stable (≈ A²/4 for a full-scale bin sinusoid of amplitude A),
  /// independent of block length, so the thresholds above are meaningful.
  double _blockPower(Int16List samples, int start) {
    var s1 = 0.0;
    var s2 = 0.0;
    for (var i = 0; i < blockSize; i++) {
      final x = samples[start + i] / 32768.0;
      final s0 = x + _coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final mag = s1 * s1 + s2 * s2 - _coeff * s1 * s2;
    return mag / (blockSize * blockSize);
  }
}
