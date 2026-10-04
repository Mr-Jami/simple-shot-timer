// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/utils/legal.dart';

/// The licenses page carries the app's legal notices. If NOTICE stops
/// shipping as an asset, that page shows nothing but the load error, and
/// release builds log nothing, so these tests guard it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const attribution = 'Based on Simple Shot Timer by Tareq Jami (Jami IT).';
  const originalUrl = 'https://jami-it.de/apps/simpleshottimer/';

  test('NOTICE ships as an asset with the attribution and its link', () async {
    final notice = await rootBundle.loadString('NOTICE');
    expect(notice, contains(attribution));
    expect(notice, contains(originalUrl));
  });

  test('the in-app copyright notice matches NOTICE', () async {
    final notice = await rootBundle.loadString('NOTICE');
    expect(
      notice,
      contains(kCopyrightNotice.replaceFirst('©', 'Copyright (C)')),
    );
  });

  test('registerAppLicenses adds the NOTICE terms to the app entry', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    registerAppLicenses();

    final entries = await LicenseRegistry.licenses
        .where((e) => e.packages.contains('simple_shot_timer'))
        .toList();
    final text =
        entries.expand((e) => e.paragraphs).map((p) => p.text).join('\n');
    expect(text, contains('ADDITIONAL TERMS UNDER SECTION 7'));
    expect(text, contains(originalUrl));
  });

  test('every source file points to the license and NOTICE', () {
    const header = [
      '// SPDX-License-Identifier: GPL-3.0-only',
      '// Copyright (C) 2026 Tareq Jami (Jami IT)',
      '// Additional terms under GPLv3 section 7 apply; see NOTICE.',
    ];
    const dirs = [
      'lib',
      'test',
      'android/app/src/main/kotlin',
      'ios/Runner',
      'ios/RunnerTests',
    ];
    final sources = [
      for (final dir in dirs)
        ...Directory(dir).listSync(recursive: true).whereType<File>(),
    ].where((f) => RegExp(r'\.(dart|kt|swift)$').hasMatch(f.path));

    final missing = [
      for (final f in sources)
        if (!listEquals(f.readAsLinesSync().take(3).toList(), header)) f.path,
    ];
    expect(sources, isNotEmpty);
    expect(missing, isEmpty, reason: 'files without the license header');
  });
}
