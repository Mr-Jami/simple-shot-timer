// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
import { initDemo } from './demo.js';
import { intro, initMotion, reduceMotion } from './motion.js';

intro();
initDemo({
  phone: document.getElementById('demo-phone'),
  hint: document.getElementById('demo-hint'),
  reduceMotion,
});
initMotion();
