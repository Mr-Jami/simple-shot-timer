// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/throttled_seeker.dart';

void main() {
  test('scrubbing seeks one at a time, spaced, to the latest position', () {
    fakeAsync((async) {
      final seeks = <int>[];
      var inFlight = 0;
      var mostInFlight = 0;
      final seeker = ThrottledSeeker((d) async {
        inFlight++;
        if (inFlight > mostInFlight) mostInFlight = inFlight;
        seeks.add(d.inMilliseconds);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        inFlight--;
      });
      // A drag: a new position every 10 ms for one second.
      for (var t = 0; t <= 1000; t += 10) {
        seeker.scrub(Duration(milliseconds: t * 10));
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(mostInFlight, 1);
      expect(seeks.length, inInclusiveRange(5, 7));
      for (var i = 1; i < seeks.length; i++) {
        expect(seeks[i], greaterThan(seeks[i - 1]));
      }
    });
  });

  test('release lands exactly where the finger stopped, without the gap', () {
    fakeAsync((async) {
      final seeks = <int>[];
      final seeker = ThrottledSeeker((d) async {
        seeks.add(d.inMilliseconds);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      seeker.scrub(const Duration(milliseconds: 1000));
      async.elapse(const Duration(milliseconds: 20));
      seeker.scrub(const Duration(milliseconds: 2000));
      var done = false;
      seeker
          .release(const Duration(milliseconds: 2345))
          .then((_) => done = true);
      // The first seek finishes at 40 ms; the release follows at once.
      async.elapse(const Duration(milliseconds: 85));
      expect(seeks, [1000, 2345]);
      expect(done, isTrue);
    });
  });
}
