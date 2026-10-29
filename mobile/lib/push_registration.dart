import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// Subscribe before registering: native registration can finish immediately.
Future<String> awaitPushRegistration({
  required Stream<String> registrations,
  required Future<void> Function() register,
  Duration timeout = const Duration(seconds: 35),
}) async {
  final target = Completer<String>();
  StreamSubscription<String> listen(Stream<String> events) => events.listen(
    (value) {
      if (!target.isCompleted && value.isNotEmpty) target.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!target.isCompleted) target.completeError(error, stack);
    },
    onDone: () {
      if (!target.isCompleted) {
        target.completeError(StateError('Push registration stream closed'));
      }
    },
  );
  final subscriptions = [
    listen(registrations),
  ];
  try {
    final values = await Future.wait<Object?>([
      target.future,
      Future<void>.sync(register),
    ], eagerError: true).timeout(timeout);
    return values.first! as String;
  } finally {
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }
}

/// Firebase Admin's token target accepts registered FIDs during migration.
/// Existing app versions continue to send their original registration tokens.
Future<String> requestFamilyPushTarget() {
  final messaging = FirebaseMessaging.instance;
  return awaitPushRegistration(
    registrations: messaging.onRegistered,
    register: messaging.register,
  );
}
