import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Wraps `flutter_foreground_task` for our single use-case: keeping the OS
/// from suspending the app while a string is in progress. The mic stream and
/// beep playback continue in the main isolate — the foreground service exists
/// solely to satisfy the platform requirement that long-running background
/// audio work runs under a typed foreground service.
class BackgroundService {
  BackgroundService._();

  static bool _initialized = false;

  /// Call once at app startup (before the first [start]) so the plugin's
  /// notification channel + task options are registered.
  static void init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'simple_shot_timer_run',
        channelName: 'Run in progress',
        channelDescription:
            'Keeps the timer alive while the app is in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // We never want the notification itself to beep — the beep is fired
        // by AudioService, and the notification is purely status indication.
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        showWhen: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // No background isolate work — the plugin keeps the main process
        // alive and that's all we need. `nothing` means the task handler
        // (registered via the entrypoint below) won't be repeatedly ticked.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  /// Start the foreground service. Safe to call when already running — the
  /// plugin's startService throws `ServiceAlreadyStartedException` which we
  /// catch via the ServiceRequestResult and ignore.
  static Future<void> start() async {
    init();
    // Android 13+ requires the user to grant POST_NOTIFICATIONS before any
    // notification (including the foreground service's) appears. Without it
    // the service starts but Android kills it within seconds for not posting
    // the required notification.
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    // Notification text is intentionally English-only: TimerNotifier has no
    // BuildContext and plumbing AppLocalizations into it for one notification
    // is a lot of churn for very little user value.
    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'Shot Timer',
      notificationText: 'Run in progress',
      callback: _emptyTaskCallback,
    );
  }

  /// Stop the foreground service. Safe to call when it isn't running.
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}

/// Top-level entrypoint required by the plugin. We don't run any background
/// isolate work — the service just needs *some* registered handler. Annotated
/// so Flutter's tree-shaker keeps it reachable from the native side.
@pragma('vm:entry-point')
void _emptyTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopTaskHandler());
}

class _NoopTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
