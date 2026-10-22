// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../beep_constants.dart';
import 'clip_shot_finder.dart';
import 'spectrogram.dart';
import 'start_finder.dart';
import 'tone_finder.dart';

/// Offline beep and shot detection for a recorded clip (the video feature).
///
/// Everything here is pure Dart so it runs in a background isolate:
/// [analyzePcmFile] reads the decoder's PCM file and analyses it in one, so
/// the samples never cross isolates.

/// How eagerly shots are taken. Scales the adaptive loudness gate, so it can
/// change after analysis without the audio (see [ClipAnalysis.withSensitivity]).
enum ShotSensitivity {
  fewer(1.05),
  normal(1.0),
  more(0.93);

  const ShotSensitivity(this.gateScale);

  /// Multiplier on the loudness gate; lower takes quieter shots.
  final double gateScale;
}

/// What the analyzer found in one clip. Times are seconds from the start of
/// the clip's audio.
class ClipAnalysis {
  const ClipAnalysis({
    required this.spectrogram,
    required this.tones,
    required this.scan,
    required this.sensitivity,
    required this.start,
  });

  /// Kept so [withSensitivity] needs no audio.
  final Spectrogram spectrogram;

  /// Every steady tone, with its onset refined on the waveform.
  final List<ToneRun> tones;

  /// Every shot in the clip, including any before START.
  final ShotScan scan;
  final ShotSensitivity sensitivity;

  /// The start beep, or null when no tone is convincing. The editor then
  /// asks for START instead of guessing.
  final ToneRun? start;

  double? get startSeconds => start?.onsetSeconds;

  List<double> get shotSeconds =>
      [for (final s in scan.shots) spectrogram.secondsAt(s.frame)];

  /// The string's shots: those after START, past the shortest possible draw.
  /// A piezo beep that stops abruptly clicks, and that click right at the
  /// beep's end is not a shot.
  List<double> get stringShotSeconds {
    final beep = start;
    if (beep == null) return const [];
    final t0 = beep.onsetSeconds;
    final stopClickFrom = beep.endSeconds - 0.01;
    final stopClickTo = beep.endSeconds + 0.05;
    return [
      for (final t in shotSeconds)
        if (t > t0 + _minDraw && (t < stopClickFrom || t > stopClickTo)) t,
    ];
  }

  /// The same clip analysed at another [sensitivity]. Only the shot test and
  /// the START choice run again.
  ClipAnalysis withSensitivity(ShotSensitivity sensitivity) =>
      _decide(spectrogram, tones, sensitivity);
}

const double _minDraw = 0.1;

/// Analyses mono 16-bit [pcm] at [sampleRate].
ClipAnalysis analyzePcm(
  Int16List pcm,
  int sampleRate, {
  ShotSensitivity sensitivity = ShotSensitivity.normal,
}) {
  final spectrogram = Spectrogram.compute(pcm, sampleRate);
  final tones = [
    for (final t in findTones(spectrogram))
      t.withOnset(refineToneOnset(
        pcm,
        sampleRate,
        _isOwnBeep(t, spectrogram.binHz)
            ? Beeps.frequencyHz.toDouble()
            : t.frequencyHz,
        t.startSeconds,
      )),
  ];
  return _decide(spectrogram, tones, sensitivity);
}

/// Reads the raw little-endian 16-bit mono PCM at [path] (what the platform
/// decoder writes) and analyses it in a background isolate.
Future<ClipAnalysis> analyzePcmFile(
  String path,
  int sampleRate, {
  ShotSensitivity sensitivity = ShotSensitivity.normal,
}) =>
    Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      final pcm = bytes.buffer.asInt16List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 2,
      );
      return analyzePcm(pcm, sampleRate, sensitivity: sensitivity);
    });

ClipAnalysis _decide(
  Spectrogram spectrogram,
  List<ToneRun> tones,
  ShotSensitivity sensitivity,
) {
  final scan = findShots(spectrogram, gateScale: sensitivity.gateScale);
  final shotSeconds = [
    for (final s in scan.shots) spectrogram.secondsAt(s.frame),
  ];
  return ClipAnalysis(
    spectrogram: spectrogram,
    tones: tones,
    scan: scan,
    sensitivity: sensitivity,
    start: chooseStart(tones, shotSeconds, minDraw: _minDraw),
  );
}

/// This app's own beep, measured to within a bin and a half of its pitch.
bool _isOwnBeep(ToneRun tone, double binHz) =>
    (tone.frequencyHz - Beeps.frequencyHz).abs() <= 1.5 * binHz;
