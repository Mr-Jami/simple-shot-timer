// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Runner target compiles every Swift file in ios/Runner', () {
    // The project lists its files one by one. A Swift file left out builds
    // fine until something calls it, and CI builds iOS only on deploys: the
    // video channels would be missing at run time.
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final runnerPhases = RegExp(
          r'/\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?'
          r'buildPhases = \(([^)]*)\)',
          dotAll: true,
        ).firstMatch(project)?.group(1) ??
        '';
    final sourcesPhase =
        RegExp(r'(\w{24}) /\* Sources \*/').firstMatch(runnerPhases)?[1];
    expect(sourcesPhase, isNotNull, reason: 'Runner has no Sources phase');
    final sources = RegExp(
          '$sourcesPhase /\\* Sources \\*/ = \\{[^}]*?files = \\(([^)]*)\\)',
        ).firstMatch(project)?.group(1) ??
        '';
    final compiled = {
      for (final m in RegExp(r'(\w{24}) /\*').allMatches(sources))
        RegExp(
          '${m[1]} /\\*[^*]*\\*/ = \\{isa = PBXBuildFile; '
          'fileRef = \\w{24} /\\* ([^*]+?) \\*/',
        ).firstMatch(project)?[1],
    };

    final swift = [
      for (final f in Directory('ios/Runner').listSync())
        if (f is File && f.path.endsWith('.swift')) f.uri.pathSegments.last,
    ];
    expect(swift, contains('ClipExportChannel.swift'));
    for (final name in swift) {
      expect(compiled, contains(name),
          reason: '$name is not in the Runner target\'s Compile Sources');
    }
  });
}
