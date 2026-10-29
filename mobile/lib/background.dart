import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

import 'repository.dart';
import 'calendar.dart';
import 'outbox_sync.dart';
import 'push_registration.dart';

final notifications = FlutterLocalNotificationsPlugin();
void Function(String?)? notificationTap;
const nativeCalls = MethodChannel('ru.mykids/calls');

@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, inputData) {
    // Durable work can wait for a slow connection beyond the short FCM window.
    final repository = FamilyRepository(
      requestTimeout: const Duration(seconds: 60),
    );
    return runBackgroundSync(repository);
  });
}

@visibleForTesting
Future<bool> runBackgroundSync(
  FamilyRepository repository, {
  Future<void> Function()? prepareNotifications,
  Future<void> Function()? updateReminders,
}) async {
  var completed = false;
  try {
    await repository.initialize();
    if (!repository.signedIn) {
      completed = true;
    } else {
      await (prepareNotifications ?? initializeNotifications)();
      await repository.sync();
      await (updateReminders ?? BackgroundServices(repository).reminders)();
      completed =
          !repository.signedIn ||
          (repository.online &&
              !(await repository.pending()).any(
                (row) => row['state'] == 'pending',
              ));
    }
  } on Exception {
    // A busy database or temporarily unavailable platform service must
    // retry. Throwing makes WorkManager fail every queued dependent refresh.
    completed = false;
  } finally {
    try {
      await repository.db?.close();
    } on Exception {
      completed = false;
    }
    repository.client.close();
    repository.dispose();
  }
  return completed;
}

@pragma('vm:entry-point')
Future<void> incomingPush(RemoteMessage message) async {
  // The native Firebase handlers present and cancel call notifications even
  // when Flutter is stopped. Never create a second notification for the call.
  if (['call', 'call_state'].contains(message.data['kind'])) return;
  await initializeNotifications();
  // A session is needed even for generic notifications.
  if (await const FlutterSecureStorage().read(key: 'session') == null) return;
  // Persist the refresh before doing any HTTP work. FCM grants only a short
  // callback window; a slow response must not prevent scheduling its own retry.
  try {
    await queuePushRefresh(urgent: message.data['kind'] != 'calendar');
  } finally {
    if (message.data['kind'] != 'calendar') await _showFamilyEvent(message);
  }
}

Future<void> queuePushRefresh({bool urgent = false}) async {
  var expedited = false;
  if (urgent) {
    try {
      final sdk = await const MethodChannel('ru.mykids/runtime')
          .invokeMethod<int>('androidSdkInt');
      // Android 12+ provides native expedited jobs. Older versions would need
      // a foreground-service implementation, so retain ordinary durable work.
      expedited = sdk != null && sdk >= 31;
    } on MissingPluginException {
      // Older runtime bridges and non-Android hosts retain durable work.
    } on PlatformException {
      // A missing SDK probe must not lose the refresh itself.
    }
  }
  await Workmanager().registerOneOffTask(
    // A deferred calendar refresh must not block a visible notification's
    // expedited work while Android restricts ordinary background networking.
    urgent ? 'mykids-push-urgent' : 'mykids-push-retry',
    'family-sync',
    existingWorkPolicy: ExistingWorkPolicy.append,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
    expedited: expedited,
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
  );
  if (!urgent) return;
  var dataRestricted = false;
  try {
    dataRestricted =
        await const MethodChannel('ru.mykids/runtime')
            .invokeMethod<bool>('backgroundDataRestricted') ??
        false;
  } on MissingPluginException {
    // The connected durable refresh above remains available on older builds.
  } on PlatformException {
    // An unavailable preference probe cannot discard the queued update.
  }
  if (!dataRestricted) return;
  // Android blocks the network constraint itself under Data Saver, including
  // expedited jobs. A visible data-sync service may use the network. Keep the
  // connected job as a durable fallback if Android declines foreground start.
  await Workmanager().registerOneOffTask(
    'mykids-push-metered',
    'family-sync',
    existingWorkPolicy: ExistingWorkPolicy.append,
    constraints: Constraints(networkType: NetworkType.notRequired),
    expedited: expedited,
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
    foregroundServiceConfig: ForegroundServiceConfig(
      notificationTitle: 'MyKIDS',
      notificationText: 'Обновляем семейные данные',
      notificationChannelId: 'family_sync',
      notificationChannelName: 'Обновление данных',
      notificationId: 41027,
      foregroundServiceType: ForegroundServiceType.dataSync,
    ),
  );
}

Future<void> _showFamilyEvent(RemoteMessage message) async {
  await initializeNotifications();
  if (await const FlutterSecureStorage().read(key: 'session') == null) return;
  await notifications.show(
    id: message.messageId.hashCode.abs() % 1000000000,
    title: 'MyKIDS',
    body: 'Есть новые семейные события',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'family_events',
        'События семьи',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.private,
      ),
    ),
  );
}

Future<void> initializeNotifications({void Function(String?)? onTap}) async {
  if (onTap != null) notificationTap = onTap;
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('mykids_notification'),
    ),
    onDidReceiveNotificationResponse: (response) =>
        notificationTap?.call(response.payload),
  );
  tzdata.initializeTimeZones();
}

class BackgroundServices extends ChangeNotifier {
  final FamilyRepository repository;
  @visibleForTesting
  final Future<String?> Function()? testTokenProvider;
  bool pushReady = false;
  StreamSubscription<RemoteMessage>? subscription;
  StreamSubscription<String>? tokenSubscription;
  StreamSubscription<RemoteMessage>? openedSubscription;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  BackgroundServices(this.repository, {this.testTokenProvider});
  bool exactNotificationsReady = false;
  bool? callsNotificationsReady, callsFullScreenReady;
  bool? callsAlertsReady, callsLockScreenReady;
  bool? callsMicrophoneReady, callsCameraReady;
  String? phoneModel, androidVersion;
  String? nativeSession, nativeUser;
  void Function(String?)? openNotification;
  bool openingIncoming = false;
  bool checkingPermissions = false, disposed = false;
  bool get callsNeedSetup =>
      callsNotificationsReady == false ||
      callsFullScreenReady == false ||
      callsAlertsReady == false ||
      callsLockScreenReady == false ||
      callsMicrophoneReady == false;

  void identityChanged() {
    final identity = repository.signedIn ? repository.sessionTag : '';
    final user = repository.signedIn ? repository.userId : '';
    if (identity == nativeSession && user == nativeUser) return;
    nativeSession = identity;
    nativeUser = user;
    unawaited(
      nativeCalls
          .invokeMethod('identity', {'user': user, 'session': identity})
          .catchError((_) {}),
    );
  }

  Future<void> checkCallPermissions() async {
    if (checkingPermissions || disposed) return;
    checkingPermissions = true;
    final before = [
      callsNotificationsReady,
      callsFullScreenReady,
      callsAlertsReady,
      callsLockScreenReady,
      callsMicrophoneReady,
      callsCameraReady,
      phoneModel,
      androidVersion,
      exactNotificationsReady,
    ];
    try {
      final state = await nativeCalls.invokeMapMethod<String, dynamic>(
        'permissions',
      );
      callsNotificationsReady = state?['notifications'] as bool?;
      callsFullScreenReady = state?['fullScreen'] as bool?;
      callsAlertsReady = state?['callAlerts'] as bool?;
      callsLockScreenReady = state?['lockScreen'] as bool?;
      callsMicrophoneReady = state?['microphone'] as bool?;
      callsCameraReady = state?['camera'] as bool?;
      phoneModel = state?['phone'] as String?;
      androidVersion = state?['android'] as String?;
      exactNotificationsReady =
          await notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ??
          false;
    } catch (_) {
      /* Other platforms and test hosts do not expose Android settings. */
    } finally {
      checkingPermissions = false;
      final after = [
        callsNotificationsReady,
        callsFullScreenReady,
        callsAlertsReady,
        callsLockScreenReady,
        callsMicrophoneReady,
        callsCameraReady,
        phoneModel,
        androidVersion,
        exactNotificationsReady,
      ];
      if (!disposed && !listEquals(before, after)) notifyListeners();
    }
  }

  Future<void> configureCalls() async {
    if (callsNotificationsReady == false) {
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await checkCallPermissions();
      if (callsNotificationsReady == false) {
        await nativeCalls.invokeMethod('notificationSettings');
        return;
      }
    }
    if (callsMicrophoneReady == false && callsFullScreenReady != false) {
      await Permission.microphone.request();
      await checkCallPermissions();
      if (callsMicrophoneReady == false) {
        await openAppSettings();
        return;
      }
    }
    await nativeCalls.invokeMethod(
      callsFullScreenReady == false
          ? 'fullScreenSettings'
          : 'callNotificationSettings',
    );
  }

  Future<void> enableCallCamera() async {
    final result = await Permission.camera.request();
    if (result.isPermanentlyDenied) await openAppSettings();
    await checkCallPermissions();
  }

  Future<void> pendingIncoming() async {
    if (openingIncoming) return;
    openingIncoming = true;
    var hasIncoming = false, forwarded = false;
    Map<String, dynamic>? incomingScope;
    try {
      final incoming = await nativeCalls.invokeMapMethod<String, dynamic>(
        'pendingIncoming',
      );
      if (incoming == null) return;
      incomingScope = incoming;
      hasIncoming = true;
      final id = incoming['id'] as String;
      final identity = repository.sessionTag;
      await repository.sync();
      if (!repository.signedIn ||
          !repository.online ||
          repository.sessionTag != identity) {
        return;
      }
      final call = repository
          .rows('calls')
          .where((call) => call['id'] == id)
          .firstOrNull;
      if (call == null ||
          call['status'] == 'ended' ||
          call['member_status'] != 'invited') {
        return;
      }
      if (incoming['action'] == 'decline') {
        await nativeCalls.invokeMethod('dismissIncoming', {'id': id});
        await repository.mutate('/v1/calls/$id/actions', {'action': 'decline'});
      } else {
        openNotification?.call(
          incoming['action'] == 'answer' ? 'answer-call:$id' : id,
        );
        forwarded = true;
      }
    } catch (_) {
      // The final block hides any unfinished incoming screen on failure.
    } finally {
      if (hasIncoming && !forwarded) {
        try {
          await nativeCalls.invokeMethod('finishIncoming', incomingScope);
        } catch (_) {
          // Non-Android hosts do not expose the native incoming screen.
        }
      }
      openingIncoming = false;
    }
  }

  Future<void> initialize(void Function(String?) onTap) async {
    openNotification = onTap;
    repository.addListener(identityChanged);
    identityChanged();
    nativeCalls.setMethodCallHandler((call) async {
      if (call.method == 'incoming') await pendingIncoming();
      if (call.method == 'callChanged') await repository.sync();
    });
    await initializeNotifications(onTap: onTap);
    watchConnectivity();
    await checkCallPermissions();
    await pendingIncoming();
    final launch = await notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onTap(launch?.notificationResponse?.payload);
    }
    await Workmanager().initialize(backgroundSync);
    await Workmanager().registerPeriodicTask(
      'mykids-sync',
      'family-sync',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
    if (repository.signedIn &&
        (await repository.pending()).any((row) => row['state'] == 'pending')) {
      // Also recover an enqueue interrupted between the two durable databases.
      await queueOutboxSync();
    }
    // The owner supplies native per-flavor Firebase configuration before release.
    try {
      await Firebase.initializeApp();
    } on FirebaseException {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(incomingPush);
    subscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(handleForegroundMessage(message).catchError((_) {}));
    });
    openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => onTap(message.data['entity_id']),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) onTap(initial.data['entity_id']);
    void registeredTarget(String target) {
      pushTarget = target;
      if (repository.signedIn) {
        unawaited(registerDevice().catchError((_) {}));
      }
    }

    tokenSubscription = FirebaseMessaging.instance.onRegistered.listen(
      registeredTarget,
    );
    pushReady = true;
    await registerDevice();
  }

  void watchConnectivity({Stream<List<ConnectivityResult>>? changes}) {
    if (disposed || connectivitySubscription != null) return;
    connectivitySubscription = (changes ?? Connectivity().onConnectivityChanged)
        .listen(
          (results) {
            unawaited(handleConnectivity(results).catchError((_) {}));
          },
          onError: (Object _) {
            // The regular foreground poll and resume refresh remain available
            // on hosts without a working connectivity notification channel.
          },
        );
  }

  Future<void> handleConnectivity(List<ConnectivityResult> results) async {
    if (disposed || !repository.signedIn) return;
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      repository.connectionLost();
      return;
    }
    final identity = repository.sessionTag, epoch = repository.generation;
    // A radio connection does not prove Internet access. Only the successful
    // authenticated refresh is allowed to mark the repository online.
    await repository.reconnect();
    if (disposed ||
        !repository.signedIn ||
        repository.sessionTag != identity ||
        repository.generation != epoch ||
        !repository.online) {
      return;
    }
    await registerDevice();
    await reminders();
  }

  Future<void> handleForegroundMessage(RemoteMessage message) async {
    if (disposed || !repository.signedIn) return;
    final identity = repository.sessionTag, epoch = repository.generation;
    // Update the repository observed by the open screens. A separate
    // background repository only updates disk and cannot repaint this app.
    await repository.refreshAfterChange();
    if (disposed ||
        !repository.signedIn ||
        identity != repository.sessionTag ||
        epoch != repository.generation) {
      return;
    }
    if (message.data['kind'] == 'calendar') {
      await reminders();
    } else if (!['call', 'call_state'].contains(message.data['kind'])) {
      // The observed foreground repository was refreshed above; only the
      // background entry point needs to open another database connection.
      await _showFamilyEvent(message);
    }
  }

  bool registering = false;
  bool registrationPending = false;
  String? registeredSession, registeredToken;
  String? pushTarget;
  Future<void> registerDevice() async {
    if (!pushReady || disposed || !repository.signedIn || !repository.online) {
      return;
    }
    if (registering) {
      registrationPending = true;
      return;
    }
    registrationPending = false;
    registering = true;
    final identity = repository.sessionTag;
    try {
      final token = await (testTokenProvider?.call() ?? obtainPushTarget());
      if (token == null ||
          !repository.signedIn ||
          identity != repository.sessionTag) {
        return;
      }
      if (registeredSession == identity && registeredToken == token) return;
      final previous = await repository.storage.read(key: 'push_device_token');
      if (!repository.signedIn || identity != repository.sessionTag) return;
      await repository.request(
        '/v1/devices',
        method: 'POST',
        body: {
          'token': token,
          'previous_token': ?previous,
          'call_notifications_version': 1,
        },
      );
      if (repository.signedIn &&
          identity == repository.sessionTag &&
          await repository.storage.read(key: 'notification_permission_asked') !=
              '1') {
        await repository.storage.write(
          key: 'notification_permission_asked',
          value: '1',
        );
        await notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        await checkCallPermissions();
      }
      if (repository.signedIn && identity == repository.sessionTag) {
        registeredSession = identity;
        registeredToken = token;
        await repository.storage.write(key: 'push_device_token', value: token);
      }
    } finally {
      registering = false;
      if (registrationPending && !disposed) {
        registrationPending = false;
        unawaited(registerDevice().catchError((_) {}));
      }
    }
  }

  Future<String> obtainPushTarget() async {
    return pushTarget ??= await requestFamilyPushTarget();
  }

  Future<void> enableNotifications() async {
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
    await checkCallPermissions();
    if (pushReady) {
      await FirebaseMessaging.instance.requestPermission();
      if (repository.signedIn) {
        await registerDevice();
      }
    }
  }

  bool scheduling = false;
  Future<void> reminders() async {
    if (scheduling) return;
    scheduling = true;
    try {
      await repository.guardDeviceUpdate(applyReminders);
    } finally {
      scheduling = false;
    }
  }

  Future<void> applyReminders() async {
    if (!repository.signedIn) {
      await notifications.cancelAll();
      return;
    }
    final snapshot = repository.snapshot;
    if (snapshot == null) return;
    final identity = repository.sessionTag;
    final plan = calendarReminders(snapshot, DateTime.now());
    exactNotificationsReady =
        await notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    final desired = {for (final item in plan) item.id: item};
    final pending = await notifications.pendingNotificationRequests();
    final existing = {for (final item in pending) item.id: item};
    // Payload contains the complete plan fingerprint so restarts and background
    // sync do not keep postponing already registered Android alarms.
    for (final item in pending) {
      if (item.id >= 1000000000 &&
          (!desired.containsKey(item.id) ||
              item.payload !=
                  '${desired[item.id]!.payload}|${desired[item.id]!.fingerprint}|alarm:${exactNotificationsReady ? 'exact' : 'inexact'}')) {
        await notifications.cancel(id: item.id);
      }
    }
    for (final item in plan) {
      if (!repository.signedIn || repository.sessionTag != identity) return;
      final payload =
          '${item.payload}|${item.fingerprint}|alarm:${exactNotificationsReady ? 'exact' : 'inexact'}';
      if (existing[item.id]?.payload == payload) continue;
      await notifications.zonedSchedule(
        id: item.id,
        title: 'MyKIDS',
        body: item.body,
        scheduledDate: item.at,
        payload: payload,
        androidScheduleMode: exactNotificationsReady
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Расписание и задания',
            visibility: NotificationVisibility.private,
          ),
        ),
      );
      if (!repository.signedIn || repository.sessionTag != identity) {
        await notifications.cancel(id: item.id);
        return;
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    repository.removeListener(identityChanged);
    nativeCalls.setMethodCallHandler(null);
    subscription?.cancel();
    tokenSubscription?.cancel();
    openedSubscription?.cancel();
    connectivitySubscription?.cancel();
    super.dispose();
  }
}
