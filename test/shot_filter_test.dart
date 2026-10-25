// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_shot_finder.dart';
import 'package:simple_shot_timer/services/video/shot_filter.dart';
import 'package:simple_shot_timer/services/video/spectrogram.dart';

import 'clip_fixtures.dart';

/// Two magazines of four, 0.3 s apart.
const _shots = [3.0, 3.3, 3.6, 3.9, 6.0, 6.3, 6.6, 6.9];

/// The reload between them (magazine out, on the floor, new one in, slide)
/// and holstering after, each with its own ring.
const _handling = [
  (4.4, 3000.0),
  (4.8, 4500.0),
  (5.2, 6000.0),
  (5.6, 2500.0),
  (7.6, 5200.0),
  (8.2, 3600.0),
];

/// Metal on concrete, a flat crack gone within milliseconds: a shot's
/// spectrum without its decay.
void _crack(Float32List x, double at, double Function() rand) {
  final s0 = (at * clipSampleRate).round();
  for (var i = 0; i < 0.05 * clipSampleRate && s0 + i < x.length; i++) {
    x[s0 + i] += 0.9 * math.exp(-i / clipSampleRate / 0.002) * rand();
  }
}

/// A shot the camera hears from further off: quieter, and its crack (no
/// boom here, so only its sound can keep it).
void _distantShot(Float32List x, double at, double Function() rand) {
  final s0 = (at * clipSampleRate).round();
  for (var i = 0; i < 0.4 * clipSampleRate && s0 + i < x.length; i++) {
    final t = i / clipSampleRate;
    final blast = 0.9 * math.exp(-t / 0.015) * rand();
    final tail = 0.08 * math.exp(-t / 0.08) * rand();
    x[s0 + i] += 0.4 * math.min(1.0, t / 0.0005) * (blast + tail);
  }
}

/// A shot from further off or turned away: the walls take the crack's
/// treble, the boom stays. [gain] 0.6 and a slower rise make it the echo of
/// a shot off the far wall.
void _muffledShot(
  Float32List x,
  double at,
  double Function() rand, {
  double gain = 1,
  double riseSeconds = 0.0005,
}) {
  final s0 = (at * clipSampleRate).round();
  var smooth = 0.0;
  for (var i = 0; i < 0.4 * clipSampleRate && s0 + i < x.length; i++) {
    final t = i / clipSampleRate;
    smooth += (rand() - smooth) * 0.15;
    final blast = 2.5 * math.exp(-t / 0.02) * smooth;
    final boom = 0.5 * math.exp(-t / 0.04) * math.sin(2 * math.pi * 120 * t);
    x[s0 + i] += gain * math.min(1.0, t / riseSeconds) * (blast + boom);
  }
}

Int16List _clip({
  List<double> shots = _shots,
  List<(double, double)> handling = _handling,
  List<double> muffled = const [],
  List<double> cracks = const [],
  List<double> ringing = const [],
  List<double> quiet = const [],
  List<double> echoes = const [],
  bool beep = false,
}) =>
    syntheticClip(
      seconds: 9,
      shots: shots,
      extra: (x) {
        final rand = referenceNoise();
        if (beep) addBeep(x, 1.0, 300);
        for (final (at, hz) in handling) {
          addClick(x, at, rand, ringHz: hz);
        }
        for (final at in muffled) {
          _muffledShot(x, at, rand);
        }
        for (final at in cracks) {
          _crack(x, at, rand);
        }
        for (final at in ringing) {
          addShot(x, at, rand, blastSeconds: 0.02);
        }
        for (final at in quiet) {
          _distantShot(x, at, rand);
        }
        for (final at in echoes) {
          _muffledShot(x, at, rand, gain: 0.6, riseSeconds: 0.002);
        }
      },
    );

List<double> _seconds(Spectrogram s, List<ShotHit> hits) =>
    [for (final h in hits) s.secondsAt(h.frame)];

Matcher _near(List<double> times) =>
    pairwiseCompare(times, (double a, double b) => (a - b).abs() <= 0.01,
        'within 10 ms of');

void main() {
  test('drops the gun handling around the shots and keeps every shot', () {
    final s = Spectrogram.compute(_clip(), clipSampleRate);
    final hits = findShots(s).shots;
    // The shot test alone takes the handling for shots.
    expect(_seconds(s, hits),
        _near([..._shots, for (final h in _handling) h.$1]..sort()));
    expect(_seconds(s, keepShotLike(s, hits)), _near(_shots));
  });

  test('keeps shots that sound different but have the boom', () {
    const muffled = [7.6, 8.3];
    final s = Spectrogram.compute(
      _clip(handling: _handling.take(4).toList(), muffled: muffled),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(_seconds(s, hits), hasLength(_shots.length + 4 + muffled.length));
    expect(_seconds(s, keepShotLike(s, hits)),
        _near([..._shots, ...muffled]..sort()));
  });

  test('drops the echo off the far wall after the last shot of a magazine',
      () {
    // 0.2 s after the shot, quieter, the treble gone: still a boom.
    const echoes = [4.1, 7.1];
    final s = Spectrogram.compute(
      _clip(handling: const [], echoes: echoes),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(_seconds(s, hits), hasLength(_shots.length + echoes.length));
    expect(_seconds(s, keepShotLike(s, hits)), _near(_shots));
  });

  test('keeps a fast follow-up that rings longer but is about as loud', () {
    // 0.26 s after the shot, 2 units quieter: no echo.
    const followUp = [4.16];
    final s = Spectrogram.compute(
      syntheticClip(
        seconds: 9,
        extra: (x) => addShot(x, followUp.single, referenceNoise(),
            gain: 0.9, blastSeconds: 0.03),
        shots: _shots,
      ),
      clipSampleRate,
    );
    expect(_seconds(s, keepShotLike(s, findShots(s).shots)),
        _near([..._shots, ...followUp]..sort()));
  });

  test("drops a crack with a shot's spectrum but not its decay", () {
    const cracks = [4.6, 7.6];
    final s = Spectrogram.compute(
      _clip(handling: const [], cracks: cracks),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(_seconds(s, hits), hasLength(_shots.length + cracks.length));
    expect(_seconds(s, keepShotLike(s, hits)), _near(_shots));
  });

  test('keeps shots that ring a little longer than near-identical others',
      () {
    const ringing = [4.6, 7.6];
    final s = Spectrogram.compute(
      _clip(handling: const [], ringing: ringing),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(_seconds(s, keepShotLike(s, hits)),
        _near([..._shots, ...ringing]..sort()));
  });

  test('finds the shots when the handling outnumbers them', () {
    // A camera on the chest: loading, two reloads and holstering around
    // two magazines of two.
    const shots = [3.0, 3.3, 6.0, 6.3];
    final s = Spectrogram.compute(_clip(shots: shots), clipSampleRate);
    final hits = findShots(s).shots;
    expect(hits, hasLength(shots.length + _handling.length));
    expect(_seconds(s, keepShotLike(s, hits)), _near(shots));
  });

  test('keeps a quieter shot: the level does not count', () {
    const quiet = [7.6];
    final s = Spectrogram.compute(
      _clip(handling: const [], quiet: quiet),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(_seconds(s, keepShotLike(s, hits)),
        _near([..._shots, ...quiet]..sort()));
  });

  test('three shots are enough to tell a click after them', () {
    const shots = [3.0, 3.3, 3.6];
    final s = Spectrogram.compute(
      _clip(shots: shots, handling: [_handling.last]),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(hits, hasLength(4));
    expect(_seconds(s, keepShotLike(s, hits)), _near(shots));
  });

  test('two hits have nothing to compare: both stay', () {
    final s = Spectrogram.compute(
      _clip(shots: const [3.0], handling: [_handling.first]),
      clipSampleRate,
    );
    final hits = findShots(s).shots;
    expect(hits, hasLength(2));
    expect(keepShotLike(s, hits), hits);
  });

  test('Normal and Fewer drop the handling, More keeps it', () {
    final normal = analyzePcm(_clip(beep: true), clipSampleRate);
    expect(normal.startSeconds, closeTo(1.0, 0.01));
    expect(normal.stringShotSeconds, _near(_shots));
    expect(normal.withSensitivity(ShotSensitivity.fewer).stringShotSeconds,
        _near(_shots));
    expect(normal.withSensitivity(ShotSensitivity.more).stringShotSeconds,
        _near([..._shots, for (final h in _handling) h.$1]..sort()));
  });
}
