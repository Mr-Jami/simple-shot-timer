// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/background_service.dart';

const _res = 'android/app/src/main/res';

/// An XML file's text without its comments, so that a line commented out
/// does not count.
String _xml(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// The files a resource reference such as `@drawable/name` resolves to, over
/// every qualifier (`drawable`, `drawable-v24`, ...). A colour is a value,
/// not a file: for `@color/name` these are the values files that define it.
List<File> _resolve(String reference) {
  final match = RegExp(r'^@(\w+)/(\w+)$').firstMatch(reference);
  if (match == null) return const [];
  final type = match[1]!;
  final name = match[2]!;
  final found = <File>[];
  for (final dir in Directory(_res).listSync().whereType<Directory>()) {
    final folder = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final qualifiedType = folder.split('-').first;
    for (final file in dir.listSync().whereType<File>()) {
      final fileName = file.uri.pathSegments.last;
      if (qualifiedType == type &&
          RegExp('^$name\\.(xml|png|webp)\$').hasMatch(fileName)) {
        found.add(file);
      } else if (type == 'color' &&
          qualifiedType == 'values' &&
          fileName.endsWith('.xml') &&
          _xml(file.path).contains('<color name="$name">')) {
        found.add(file);
      }
    }
  }
  return found;
}

/// The value of [attribute] on the manifest's `<application>` element.
String? _applicationAttribute(String attribute) {
  final application = RegExp(r'<application\b[^>]*>')
      .firstMatch(_xml('android/app/src/main/AndroidManifest.xml'))?[0];
  if (application == null) fail('no <application> in the manifest');
  return RegExp('android:$attribute="([^"]*)"').firstMatch(application)?[1];
}

void main() {
  group('launcher icon', () {
    // Android 8 and later take mipmap-anydpi-v26/<icon>.xml, an adaptive
    // icon the launcher cuts to its own shape; older versions take the PNGs.
    // A layer that points at nothing fails the build, but a missing
    // monochrome layer or a missing adaptive file builds fine and only shows
    // on a phone: no themed icon, or the flat PNG where an adaptive icon
    // belongs.
    String iconName() => _applicationAttribute('icon')!.split('/').last;
    File adaptiveFile() => File('$_res/mipmap-anydpi-v26/${iconName()}.xml');

    Map<String, String> layers() => {
          for (final m in RegExp(
            r'<(background|foreground|monochrome)\b[^>]*'
            r'android:drawable="([^"]*)"',
          ).allMatches(_xml(adaptiveFile().path)))
            m[1]!: m[2]!,
        };

    test('the manifest names a mipmap, and it has an adaptive version', () {
      expect(_applicationAttribute('icon'), matches(r'^@mipmap/\w+$'));
      final file = adaptiveFile();
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      expect(_xml(file.path), contains('<adaptive-icon'));
    });

    test('a round icon, if the manifest names one, is adaptive too', () {
      // Launchers with round icons take android:roundIcon over android:icon.
      final round = _applicationAttribute('roundIcon');
      if (round == null) return;
      expect(round, matches(r'^@mipmap/\w+$'));
      final file = File('$_res/mipmap-anydpi-v26/${round.split('/').last}.xml');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
    });

    test('background, foreground and monochrome layers all exist', () {
      final found = layers();
      for (final layer in ['background', 'foreground', 'monochrome']) {
        expect(found, contains(layer),
            reason: 'the adaptive icon has no <$layer> with a drawable');
        expect(_resolve(found[layer]!), isNotEmpty,
            reason: '<$layer> points at ${found[layer]}, which does not '
                'exist in $_res');
      }
    });

    test('the monochrome layer is one opaque colour', () {
      // A themed icon keeps only the layer's alpha and tints it. Shapes in
      // several colours would merge into one blob, and a half-transparent
      // one would come out faded. The layer shares its drawable with the
      // foreground, so colouring the foreground would break it unnoticed.
      final files = _resolve(layers()['monochrome'] ?? '');
      expect(files, isNotEmpty);
      for (final file in files) {
        final xml = _xml(file.path);
        expect(xml, contains('<vector'), reason: file.path);
        final fills = {
          for (final m
              in RegExp(r'android:fillColor="([^"]*)"').allMatches(xml))
            m[1]!.toUpperCase(),
        };
        expect(fills, hasLength(1),
            reason: '${file.path} fills its paths with $fills');
        expect(fills.single, matches(r'^#(FF)?[0-9A-F]{6}$'),
            reason: 'not an opaque colour');
        for (final other in [
          'fillAlpha',
          'strokeColor',
          'alpha',
          '<gradient',
        ]) {
          expect(xml, isNot(contains(other)), reason: file.path);
        }
      }
    });

    test('the PNGs for Android 7 are still there', () {
      // minSdk is 24 (Flutter's default), below the adaptive icon's 26.
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final png = File('$_res/mipmap-$density/${iconName()}.png');
        expect(png.existsSync(), isTrue, reason: '${png.path} is missing');
      }
    });
  });

  group('run notification icon', () {
    // The foreground service plugin takes the launcher icon as the
    // notification's small icon unless it is given another. From Android 8
    // that is the adaptive icon, which crashes the System UI of Android 8.0
    // when it stands in a notification (issuetracker.google.com/68716460).
    // A name the manifest does not have gives the plugin icon 0, and a
    // notification without an icon stops the app when a run starts.
    test('the manifest has the icon BackgroundService asks for', () {
      final manifest = _xml('android/app/src/main/AndroidManifest.xml');
      final resource = RegExp(
        '<meta-data\\s+android:name="'
        '${RegExp.escape(BackgroundService.notificationIconMetaData)}"\\s+'
        'android:resource="([^"]*)"',
      ).firstMatch(manifest)?[1];
      expect(resource, isNotNull,
          reason: 'no <meta-data> named '
              '${BackgroundService.notificationIconMetaData} with a resource');
      expect(resource, startsWith('@drawable/'));

      final files = _resolve(resource!);
      expect(files, isNotEmpty, reason: '$resource does not exist in $_res');
      for (final file in files) {
        expect(_xml(file.path), contains('<vector'),
            reason: '${file.path} must be a plain shape, not an adaptive '
                'icon or a picture with a background');
      }
    });

    test('the service is started with that icon', () {
      final source =
          File('lib/services/background_service.dart').readAsStringSync();
      final start =
          RegExp(r'FlutterForegroundTask\.startService\((.*?)\);', dotAll: true)
              .firstMatch(source)?[1];
      expect(start, isNotNull, reason: 'startService call not found');
      expect(
        start!.replaceAll(RegExp(r'\s+'), ''),
        contains('notificationIcon:constNotificationIcon('
            'metaDataName:notificationIconMetaData)'),
      );
    });
  });
}
