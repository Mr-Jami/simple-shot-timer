// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

/// Synthetic range recordings for the clip analyzer tests, built in code so
/// no binary fixtures are needed.

const int clipSampleRate = 48000;

/// Shot times of the reference's synthetic clip, in seconds.
const List<double> referenceShotTimes = [2.2, 2.62, 2.95, 3.3, 4.1];

/// The reference's seeded noise source (video-shot-timer/scripts/
/// make-test-clip.mjs), in doubles so it rounds the way JavaScript does.
double Function() referenceNoise() {
  var seed = 12345.0;
  return () {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648 * 2 - 1;
  };
}

/// Adds one synthetic shot at [at] seconds: a sharp noise blast, a low boom
/// and a reverb tail, as the reference's test clip does. [gain] scales it.
/// A longer [attackSeconds] smears the onset the way re-encoding and a
/// camera's gain control do; a longer [blastSeconds] keeps it loud, like a
/// shot in a reverberant range.
void addShot(
  Float32List x,
  double at,
  double Function() rand, {
  double gain = 1,
  double attackSeconds = 0.0005,
  double blastSeconds = 0.015,
}) {
  final s0 = (at * clipSampleRate).round();
  for (var i = 0; i < 0.4 * clipSampleRate && s0 + i < x.length; i++) {
    final t = i / clipSampleRate;
    final attack = math.min(1.0, t / attackSeconds);
    final blast = 0.9 * math.exp(-t / blastSeconds) * rand();
    final boom = 0.4 * math.exp(-t / 0.03) * math.sin(2 * math.pi * 120 * t);
    final tail = 0.08 * math.exp(-t / 0.08) * rand();
    x[s0 + i] += gain * attack * (blast + boom + tail);
  }
}

/// Gun handling as a camera on the shooter records it (a magazine seated,
/// the slide, metal on concrete): a crack of treble-heavy noise and a short
/// metallic ring at [ringHz], without a shot's boom. [gain] scales it.
void addClick(
  Float32List x,
  double at,
  double Function() rand, {
  double gain = 1,
  double ringHz = 4000,
}) {
  final s0 = (at * clipSampleRate).round();
  var previous = 0.0;
  for (var i = 0; i < 0.15 * clipSampleRate && s0 + i < x.length; i++) {
    final t = i / clipSampleRate;
    final noise = rand();
    // The difference of successive samples tilts the noise to the treble.
    final crack = 0.9 * math.exp(-t / 0.004) * (noise - previous) / 2;
    previous = noise;
    final ring =
        0.3 * math.exp(-t / 0.03) * math.sin(2 * math.pi * ringHz * t);
    x[s0 + i] += gain * (crack + ring);
  }
}

/// Clips to ±1 and quantizes to 16 bits the way the reference writes its WAV
/// (JavaScript Math.round of v·32767).
Int16List toPcm(Float32List x) {
  final out = Int16List(x.length);
  for (var i = 0; i < x.length; i++) {
    final clipped = math.max(-1.0, math.min(1.0, x[i]));
    out[i] = (clipped * 32767 + 0.5).floor();
  }
  return out;
}

/// A shot as a phone camera with automatic gain control records it: the noise
/// rises over [riseSeconds] and then holds its level for [holdSeconds]
/// instead of decaying like a crack.
void addHeldBurst(
  Float32List x,
  double at,
  double Function() rand, {
  double gain = 0.6,
  double riseSeconds = 0.01,
  double holdSeconds = 0.1,
}) {
  final s0 = (at * clipSampleRate).round();
  final n = ((riseSeconds + holdSeconds + 0.03) * clipSampleRate).round();
  for (var i = 0; i < n && s0 + i < x.length; i++) {
    final t = i / clipSampleRate;
    final envelope = t < riseSeconds
        ? t / riseSeconds
        : t < riseSeconds + holdSeconds
            ? 1.0
            : math.exp(-(t - riseSeconds - holdSeconds) / 0.01);
    x[s0 + i] += gain * envelope * rand();
  }
}

/// The reference's `test/synthetic.wav`: noise, a 500 ms 2900 Hz beep at
/// 1.0 s and five shots.
Int16List referenceClip() {
  final rand = referenceNoise();
  final x = Float32List(clipSampleRate * 6);
  for (var i = 0; i < x.length; i++) {
    x[i] = 0.003 * rand();
  }
  const beepAt = 1.0, beepLength = 0.5;
  final b0 = (beepAt * clipSampleRate).round();
  for (var i = 0; i < beepLength * clipSampleRate; i++) {
    final t = i / clipSampleRate;
    final fade = [1.0, t / 0.005, (beepLength - t) / 0.005].reduce(math.min);
    x[b0 + i] += 0.3 * fade * math.sin(2 * math.pi * 2900 * t);
  }
  for (final at in referenceShotTimes) {
    addShot(x, at, rand);
  }
  return toPcm(x);
}

/// A beep the way AudioService generates it: a sine with an 8 ms raised-cosine
/// attack and a 20 ms release, at 90 % of full scale times [gain].
void addBeep(
  Float32List x,
  double at,
  int durationMs, {
  double frequencyHz = 2325,
  double gain = 1,
}) {
  final total = (clipSampleRate * durationMs / 1000).round();
  const attack = clipSampleRate * 8 ~/ 1000;
  const release = clipSampleRate * 20 ~/ 1000;
  final s0 = (at * clipSampleRate).round();
  for (var i = 0; i < total && s0 + i < x.length; i++) {
    var envelope = 1.0;
    if (i < attack) {
      envelope = 0.5 - 0.5 * math.cos(math.pi * i / attack);
    } else if (i > total - release) {
      envelope = 0.5 - 0.5 * math.cos(math.pi * (total - i) / release);
    }
    x[s0 + i] += 0.9 *
        gain *
        envelope *
        math.sin(2 * math.pi * frequencyHz * i / clipSampleRate);
  }
}

/// A noise floor plus [shots], with whatever [extra] adds (beeps, tones,
/// other sounds), quantized to 16-bit PCM. [shot] adds each shot; the
/// default is the reference's.
Int16List syntheticClip({
  double seconds = 7,
  List<double> shots = referenceShotTimes,
  void Function(Float32List x)? extra,
  void Function(Float32List x, double at, double Function() rand)? shot,
}) {
  final rand = referenceNoise();
  final x = Float32List((clipSampleRate * seconds).round());
  for (var i = 0; i < x.length; i++) {
    x[i] = 0.003 * rand();
  }
  extra?.call(x);
  for (final at in shots) {
    (shot ?? addShot)(x, at, rand);
  }
  return toPcm(x);
}
