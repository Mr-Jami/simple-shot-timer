// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

// /download: one link for QR codes, posts and the app's share text. Android
// goes to Google Play, iPhone and iPad to the App Store, everything else to
// the homepage. Same logic as jami-it.de/apps/simpleshottimer/.
(function () {
  var PLAY_URL = 'https://play.google.com/store/apps/details?id=cc.jami.simpleshottimer';
  var APP_STORE_URL = 'https://apps.apple.com/app/simple-shot-timer/id6819042653';
  // false sends iPhone and iPad to the homepage instead.
  var APP_STORE_ENABLED = true;

  var ua = navigator.userAgent || '';
  var isAndroid = /android/i.test(ua);
  var isIOS =
    /iPad|iPhone|iPod/.test(ua) ||
    // iPadOS 13+ reports as desktop Safari but exposes touch points.
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  if (isAndroid) location.replace(PLAY_URL);
  else if (isIOS && APP_STORE_ENABLED && APP_STORE_URL) location.replace(APP_STORE_URL);
  else location.replace('/');
})();
