import 'package:flutter/services.dart';

/// A native process nonce: shared by engines, replaced after process death.
Future<String?> familyProcessIdentity() async {
  try {
    return await const MethodChannel('ru.mykids/runtime')
        .invokeMethod<String>('processIdentity');
  } on MissingPluginException {
    // Non-Android hosts retain the time-limited lease behavior.
    return null;
  } on PlatformException {
    return null;
  }
}

/// Upload ownership ends with the engine, even if Android keeps its process.
Future<String?> familyOutboxOwner() async {
  try {
    return await const MethodChannel('ru.mykids/runtime')
        .invokeMethod<String>('outboxOwner');
  } on MissingPluginException {
    return familyProcessIdentity();
  } on PlatformException {
    return familyProcessIdentity();
  }
}

Future<bool?> familyOutboxOwnerAlive(String owner) async {
  try {
    final result = await const MethodChannel('ru.mykids/runtime')
        .invokeMethod<Object?>('outboxOwnerAlive', {'owner': owner});
    return result is bool ? result : null;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
