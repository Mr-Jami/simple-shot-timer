// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_shot_finder.dart';
import 'package:simple_shot_timer/services/video/marker_doc.dart';
import 'package:simple_shot_timer/services/video/spectrogram.dart';
import 'package:simple_shot_timer/services/video/tone_finder.dart';

import 'clip_fixtures.dart';

MarkerDoc doc(
        {int? start = 1000, List<int> shots = const [2200, 2620, 2950]}) =>
    MarkerDoc.detected(durationMs: 10000, startMs: start, shotMs: shots);

List<int> active(MarkerDoc d) => [for (final s in d.activeShots) s.ms];

void main() {
  group('a detected document', () {
    test('saves its shots as times from START, none manual', () {
      final shots = doc().toShots();
      expect(shots.map((s) => s.timeMs), [1200, 1620, 1950]);
      expect(shots.map((s) => s.index), [0, 1, 2]);
      expect(shots.any((s) => s.manual), isFalse);
    });

    test('without a beep has markers but nothing to save', () {
      final d = doc(start: null);
      expect(d.shots, hasLength(3));
      expect(d.activeShots, isEmpty);
      expect(d.isComplete, isFalse);
      expect(d.setStart(2000).toShots().map((s) => s.timeMs), [200, 620, 950]);
    });
  });

  group('START', () {
    test('moved later hides earlier shots without deleting them', () {
      final later = doc().setStart(2400);
      expect(active(later), [2620, 2950]);
      expect(later.shots, hasLength(3));
      expect(active(later.setStart(1000)), [2200, 2620, 2950]);
    });

    test('is clamped to the clip', () {
      expect(doc().setStart(-50).startMs, 0);
      expect(doc().setStart(20000).startMs, 10000);
    });
  });

  group('editing shots', () {
    test('an added shot is manual and gets the next id', () {
      final d = doc();
      final added = d.addShot(3300);
      expect(added.shotById(d.nextId)!.origin, ShotOrigin.added);
      expect(added.toShots().last.manual, isTrue);
      expect(active(added), [2200, 2620, 2950, 3300]);
    });

    test('a moved shot keeps where it was detected', () {
      final d = doc();
      final moved = d.moveShot(d.shots[1].id, 2640);
      final shot = moved.shotById(d.shots[1].id)!;
      expect(shot.origin, ShotOrigin.moved);
      expect(shot.detectedMs, 2620);
      expect(moved.toShots()[1].manual, isTrue);
    });

    test('Last shot ends the string; a later added shot extends it', () {
      final d = doc();
      final cut = d.setLastShot(d.shots[1].id);
      expect(active(cut), [2200, 2620]);
      expect(active(cut.addShot(3100)), [2200, 2620, 2950, 3100]);
    });

    test('deleting the last shot leaves nothing to save', () {
      var d = doc(shots: [2200]);
      d = d.deleteShot(d.shots.single.id);
      expect(d.isComplete, isFalse);
    });
  });

  group('a new sensitivity', () {
    test('replaces untouched detected shots', () {
      final d =
          doc().reconcile(startMs: 1000, shotMs: [2200, 2620, 2950, 3300]);
      expect(active(d), [2200, 2620, 2950, 3300]);
    });

    test('never brings back a deleted shot', () {
      var d = doc();
      d = d.deleteShot(d.shots[1].id);
      d = d.reconcile(startMs: 1000, shotMs: [2200, 2621, 2950]);
      expect(active(d), [2200, 2950]);
    });

    test('keeps a moved shot and does not duplicate it', () {
      var d = doc();
      d = d.moveShot(d.shots[1].id, 2700);
      d = d.reconcile(startMs: 1000, shotMs: [2200, 2620, 2950]);
      expect(active(d), [2200, 2700, 2950]);
    });

    test('keeps added shots and drops detections right on them', () {
      var d = doc().addShot(3300);
      d = d.reconcile(startMs: 1000, shotMs: [2200, 3320]);
      expect(active(d), [2200, 3300]);
    });

    test('moves START along unless the user placed it', () {
      expect(doc().reconcile(startMs: 1100, shotMs: [2200]).startMs, 1100);
      expect(
          doc().setStart(900).reconcile(startMs: 1100, shotMs: [2200]).startMs,
          900);
      expect(doc().reconcile(startMs: null, shotMs: [2200]).startMs, 1000);
    });

    test('flipping back and forth is stable', () {
      var d = doc().addShot(3300);
      d = d.deleteShot(d.shots.first.id);
      final once = d.reconcile(startMs: 1000, shotMs: [2200, 2620, 2950]);
      final twice = once
          .reconcile(startMs: 1000, shotMs: [2200, 2620]).reconcile(
              startMs: 1000, shotMs: [2200, 2620, 2950]);
      expect(active(twice), active(once));
    });
  });

  test('a saved string reopens with its markers and manual flags', () {
    final saved = TimerString(
      createdAt: DateTime(2026, 10, 23),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [
        Shot(index: 0, timeMs: 1720),
        Shot(index: 1, timeMs: 2060, manual: true),
      ],
      source: StringSource.video,
      videoStartMs: 4788,
    );
    final d = MarkerDoc.fromSaved(saved, durationMs: 24634);
    expect(d.startMs, 4788);
    expect(d.startEdited, isTrue);
    expect(d.toShots().map((s) => (s.timeMs, s.manual)),
        [(1720, false), (2060, true)]);
  });

  group('an analysed clip', () {
    test('turns analyzer seconds into clip time', () {
      final analysis = analyzePcm(
        syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
        clipSampleRate,
      );
      final clip = AnalyzedClip(
        info: const ClipInfo(hasAudio: true, durationMs: 7250),
        analysis: analysis,
        audioOriginMs: 250,
      );
      expect(clip.startMs, closeTo(1250, 5));
      final d = clip.toDoc();
      expect(d.toShots().map((s) => s.timeMs / 1000),
          [for (final t in referenceShotTimes) closeTo(t - 1.0, 0.005)]);
    });

    test('leaves out the start beep\'s attack and stop click', () {
      final spectrogram =
          Spectrogram.compute(Int16List(clipSampleRate * 7), clipSampleRate);
      final rate = spectrogram.framesPerSecond;
      final beep = ToneRun(
        startFrame: (1.505 * rate).round(),
        endFrame: (1.934 * rate).round() - 1,
        frequencyHz: 3000,
        onsetSeconds: 1.505,
        framesPerSecond: rate,
      );
      final clip = AnalyzedClip(
        info: const ClipInfo(hasAudio: true, durationMs: 7000),
        analysis: ClipAnalysis(
          spectrogram: spectrogram,
          tones: [beep],
          scan: ShotScan(shots: [
            // A shot well before the beep, the beep's attack, its stop
            // click, then a real shot.
            for (final t in [0.3, 1.52, 1.963, 2.251])
              ShotHit((t * rate).round()),
          ], gate: 0),
          sensitivity: ShotSensitivity.normal,
        ),
        audioOriginMs: 0,
      );
      expect(clip.startMs, 1505);
      expect(clip.shotMs, [closeTo(300, 3), closeTo(2251, 3)]);
    });
  });
}
