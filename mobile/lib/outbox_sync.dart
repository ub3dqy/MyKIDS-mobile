import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

/// Persist a network-triggered upload independently of the open Flutter screen.
Future<void> queueOutboxSync() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  var expedited = false;
  try {
    final sdk = await const MethodChannel('ru.mykids/runtime')
        .invokeMethod<int>('androidSdkInt');
    expedited = sdk != null && sdk >= 31;
  } on MissingPluginException {
    // The connected job still works without expedited support.
  } on PlatformException {
    // The connected job still works without the optional SDK probe.
  }
  try {
    await Workmanager().registerOneOffTask(
      // APPEND maps to Android's APPEND_OR_REPLACE in the pinned plugin.
      // A new command must survive a currently running or previously failed job.
      'mykids-outbox',
      'family-sync',
      existingWorkPolicy: ExistingWorkPolicy.append,
      constraints: Constraints(networkType: NetworkType.connected),
      expedited: expedited,
      outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  } on MissingPluginException {
    // The persisted command remains available to startup/periodic recovery.
    debugPrint('MyKIDS: upload scheduling unavailable');
  } on PlatformException {
    // Never turn an already saved action into an error encouraging a duplicate.
    debugPrint('MyKIDS: upload scheduling temporarily unavailable');
  }
}
