import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Shot detection needs the session in .measurement mode so Apple's voice
    // DSP (AGC, noise suppression) does not crush gunshot transients — the
    // iOS analogue of Android's AudioSource.unprocessed. The record plugin
    // cannot set the session mode, so the Dart side drives it through this
    // channel (lib/services/ios_audio_session.dart).
    let channel = FlutterMethodChannel(
      name: "cc.jami.simpleshottimer/audio_session",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "useMeasurementMode":
        AppDelegate.configureAudioSession(mode: .measurement, activate: true, result: result)
      case "useDefaultMode":
        // Restore path (detection stopped): only put the mode back. Leaving
        // activation untouched avoids re-asserting a session the app is done
        // with — audioplayers manages activation around beep playback itself.
        AppDelegate.configureAudioSession(mode: .default, activate: false, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Whether the beep can be heard at all (lib/services/volume_service.dart).
    // iOS has no public API to show the volume HUD, so that call reports
    // not-implemented and the Dart side treats it as a no-op.
    let volumeChannel = FlutterMethodChannel(
      name: "cc.jami.simpleshottimer/volume",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    volumeChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isMediaAudible":
        result(AVAudioSession.sharedInstance().outputVolume > 0)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Replicates the session setup the record plugin performs when it manages
  /// the AVAudioSession itself (we pass manageAudioSession: false on the Dart
  /// side), with the requested mode applied on top.
  private static func configureAudioSession(
    mode: AVAudioSession.Mode,
    activate: Bool,
    result: FlutterResult
  ) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: mode,
        options: [.defaultToSpeaker, .mixWithOthers]
      )
      try session.setPreferredSampleRate(44100)
      if #available(iOS 14.5, *) {
        try session.setPrefersNoInterruptionsFromSystemAlerts(true)
      }
      if activate {
        try session.setActive(true)
      }
      result(nil)
    } catch {
      result(FlutterError(
        code: "audio_session_error",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }
}
