// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:integration_test/integration_test_driver.dart';

/// Runs integration_test/ on a device with `flutter drive` and writes the
/// tests' report to build/integration_response_data.json.
Future<void> main() => integrationDriver();
