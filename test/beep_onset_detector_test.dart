import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/beep_onset_detector.dart';

const int _sampleRate = 44100;
const double _beepHz = 2325.0;

Int16List _silence(int n) => Int16List(n);

/// A sine tone at the beep frequency, optionally with the same ~8 ms
/// raised-cosine attack the real beep WAV uses.
Int16List _tone(int n, {double amplitude = 0.3, bool attack = true}) {
  final out = Int16List(n);
  const attackSamples = _sampleRate * 8 ~/ 1000;
  for (var i = 0; i < n; i++) {
    var env = 1.0;
    if (attack && i < attackSamples) {
      env = 0.5 - 0.5 * math.cos(math.pi * i / attackSamples);
    }
    final v = math.sin(2 * math.pi * _beepHz * i / _sampleRate) * amplitude * env;
    out[i] = (v * 32767).round();
  }
  return out;
}

Int16List _concat(List<Int16List> parts) {
  final total = parts.fold<int>(0, (a, p) => a + p.length);
  final out = Int16List(total);
  var pos = 0;
  for (final p in parts) {
    out.setRange(pos, pos + p.length, p);
    pos += p.length;
  }
  return out;
}

/// Feeds [samples] to [d] in [chunkSize]-sample chunks (mimicking the mic
/// stream); returns the global sample index of the first reported onset, or
/// null if none was detected.
int? _findOnset(BeepOnsetDetector d, Int16List samples, int chunkSize) {
  for (var start = 0; start < samples.length; start += chunkSize) {
    final end = math.min(start + chunkSize, samples.length);
    final idx = d.process(samples.sublist(start, end));
    if (idx >= 0) return start + idx;
  }
  return null;
}

BeepOnsetDetector _make() => BeepOnsetDetector(
      sampleRate: _sampleRate.toDouble(),
      frequencyHz: _beepHz,
    );

void main() {
  group('BeepOnsetDetector', () {
    test('detects the beep onset right at the silence→beep boundary', () {
      final signal = _concat([_silence(2048), _tone(4000)]);
      final onset = _findOnset(_make(), signal, 1024);
      expect(onset, isNotNull);
      // Never inside the silence, and within a block or two of the edge.
      expect(onset, inInclusiveRange(2048 - 256, 2048 + 600));
    });

    test('pure silence never triggers', () {
      expect(_findOnset(_make(), _silence(20000), 1024), isNull);
    });

    test('a sub-sustain tone burst (impulse) does not trigger', () {
      // ~4.5 ms of tone — shorter than the two-block sustain window — framed by
      // silence, standing in for an impulsive transient like a gunshot.
      final signal = _concat([
        _silence(1024),
        _tone(200, amplitude: 0.8, attack: false),
        _silence(8000),
      ]);
      expect(_findOnset(_make(), signal, 4096), isNull);
    });

    test('a clearly louder beep still triggers over a noisy floor', () {
      final rng = math.Random(7);
      final noise = Int16List(8192);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = ((rng.nextDouble() * 2 - 1) * 0.02 * 32767).round();
      }
      final signal = _concat([noise, _tone(4000, amplitude: 0.4)]);
      final onset = _findOnset(_make(), signal, 1024);
      expect(onset, isNotNull);
      expect(onset, inInclusiveRange(8192 - 256, 8192 + 600));
    });

    test('reset re-arms a latched detector for the next beep', () {
      final d = _make();
      final first = _findOnset(d, _concat([_silence(1024), _tone(3000)]), 1024);
      expect(first, isNotNull);
      // Without reset it stays latched.
      expect(_findOnset(d, _tone(3000), 1024), isNull);
      d.reset();
      expect(_findOnset(d, _concat([_silence(1024), _tone(3000)]), 1024),
          isNotNull);
    });
  });
}
