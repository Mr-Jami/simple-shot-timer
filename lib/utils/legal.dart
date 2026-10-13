// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The copyright notice shown in the app. Must match the copyright line in
/// NOTICE (`test/legal_test.dart` checks it); the year is the year of first
/// publication, so it stays fixed rather than following the clock.
const kCopyrightNotice = '© 2026 Tareq Jami (Jami IT)';

/// Where the GPL source code lives.
const kSourceUrl = 'https://github.com/Mr-Jami/simple-shot-timer';

/// The app privacy policy, which App Store guideline 5.1.1(i) requires to be
/// reachable from inside the app. German readers get the German version,
/// which is the legally binding one; every other language gets English.
const kPrivacyPolicyUrl = 'https://simpleshottimer.com/privacy/';
const kPrivacyPolicyUrlDe = 'https://simpleshottimer.com/de/datenschutz/';

Uri privacyPolicyUri(String languageCode) => Uri.parse(
      languageCode == 'de' ? kPrivacyPolicyUrlDe : kPrivacyPolicyUrl,
    );

/// Adds the section-7 additional terms in NOTICE to the app's entry on the
/// licenses page. Flutter already bundles the app's own LICENSE (the GPLv3
/// text) there.
///
/// No try/catch on purpose: if NOTICE can't load, the licenses page shows the
/// error instead of quietly dropping the terms.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['simple_shot_timer'],
      await rootBundle.loadString('NOTICE'),
    );
  });
}
