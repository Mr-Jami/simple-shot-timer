import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simple_shot_timer/services/ios_audio_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cc.jami.simpleshottimer/audio_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];

  void installHandler({Object? Function(MethodCall call)? onCall}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return onCall?.call(call);
    });
  }

  group('IosAudioSession', () {
    setUp(() {
      calls.clear();
      IosAudioSession.lastError = null;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('useMeasurementMode invokes the channel method on iOS', () async {
      installHandler();
      await IosAudioSession.useMeasurementMode();
      expect(calls, ['useMeasurementMode']);
      expect(IosAudioSession.lastError, isNull);
    });

    test('useDefaultMode invokes the channel method on iOS', () async {
      installHandler();
      await IosAudioSession.useDefaultMode();
      expect(calls, ['useDefaultMode']);
      expect(IosAudioSession.lastError, isNull);
    });

    test('is a no-op on non-iOS platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      installHandler();
      await IosAudioSession.useMeasurementMode();
      await IosAudioSession.useDefaultMode();
      expect(calls, isEmpty);
      expect(IosAudioSession.lastError, isNull);
    });

    test('PlatformException is swallowed and recorded in lastError', () async {
      installHandler(onCall: (_) {
        throw PlatformException(
          code: 'audio_session_error',
          message: 'setCategory failed',
        );
      });
      await expectLater(IosAudioSession.useMeasurementMode(), completes);
      expect(
        IosAudioSession.lastError,
        'useMeasurementMode: setCategory failed',
      );
    });

    test('missing channel handler is swallowed and recorded', () async {
      // No handler installed — invokeMethod throws MissingPluginException.
      await expectLater(IosAudioSession.useDefaultMode(), completes);
      expect(
        IosAudioSession.lastError,
        'useDefaultMode: channel not registered',
      );
    });

    test('a later success clears lastError', () async {
      installHandler(onCall: (_) {
        throw PlatformException(code: 'audio_session_error', message: 'boom');
      });
      await IosAudioSession.useMeasurementMode();
      expect(IosAudioSession.lastError, isNotNull);

      installHandler();
      await IosAudioSession.useMeasurementMode();
      expect(IosAudioSession.lastError, isNull);
    });
  });
}
