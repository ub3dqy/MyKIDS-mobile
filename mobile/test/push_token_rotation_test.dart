import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/family_contacts.dart';
import 'package:mykids_family/repository.dart';

class DeviceRegistrationFixture extends FamilyRepository {
  final release = Completer<void>();
  final calls = <Map<String, dynamic>>[];
  DeviceRegistrationFixture() {
    token = 'synthetic-session';
    online = true;
    snapshot = {
      'user': {'id': 'synthetic-child', 'role': 'child'},
    };
  }
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    expect(path, '/v1/devices');
    calls.add(Map.of(body!));
    if (calls.length == 1) await release.future;
    return {'ok': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pending removal reserves its conference place until acknowledgement',
    () {
      expect(
        reservedCallParticipants({
          'participants': [
            {'user_id': 'joined', 'status': 'joined'},
            {'user_id': 'invited', 'status': 'invited'},
            {'user_id': 'pending', 'status': 'revoking'},
            {'user_id': 'former', 'status': 'left'},
          ],
        }),
        {'joined', 'invited', 'pending'},
      );
    },
  );
  test(
    'token refresh while registration waits is replayed without reopening app',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'notification_permission_asked': '1',
      });
      final repo = DeviceRegistrationFixture();
      var currentToken = 'synthetic-old-token';
      final background = BackgroundServices(
        repo,
        testTokenProvider: () async => currentToken,
      )..pushReady = true;
      final first = background.registerDevice();
      for (var i = 0; i < 20 && repo.calls.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.calls.single['token'], currentToken);
      currentToken = 'synthetic-new-token';
      await background.registerDevice(); // The real onTokenRefresh entry point.
      expect(repo.calls.length, 1);
      repo.release.complete();
      await first;
      for (
        var i = 0;
        i < 30 && (background.registering || repo.calls.length < 2);
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.calls.length, 2);
      expect(repo.calls.last['token'], currentToken);
      expect(repo.calls.last['previous_token'], 'synthetic-old-token');
      expect(background.registeredToken, currentToken);
      expect(await repo.storage.read(key: 'push_device_token'), currentToken);
      background.dispose();
      repo.client.close();
      repo.dispose();
    },
  );
}
