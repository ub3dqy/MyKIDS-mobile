import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mykids_family/call_screen.dart';
import 'package:mykids_family/repository.dart';

class ConnectedFixture extends FamilyRepository {
  int leaves = 0;
  ConnectedFixture() {
    token = 'synthetic-session';
    snapshot = {
      'user': {'id': 'child', 'role': 'child'},
      'members': [
        {'id': 'parent', 'name': 'Мама', 'role': 'parent', 'active': 1},
      ],
      'calls': [
        {
          'id': 'fixture',
          'caller_id': 'parent',
          'status': 'active',
          'member_status': 'joined',
          'participants': [
            {'user_id': 'child', 'status': 'joined'},
            {'user_id': 'parent', 'status': 'joined'},
          ],
        },
      ],
    };
  }
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (body['action'] == 'leave') leaves++;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async => {
    'url': 'wss://synthetic.invalid',
    'token': 'synthetic',
    'video': false,
  };
  void endOnServer() {
    snapshot!['calls'][0]['status'] = 'ended';
    notifyListeners();
  }
}

class ConnectedRoom extends Room {
  bool fullyDisposed = false;
  @override
  LocalParticipant? get localParticipant => null;
  @override
  Future<void> connect(
    String url,
    String token, {
    ConnectOptions? connectOptions,
    RoomOptions? roomOptions,
    FastConnectOptions? fastConnectOptions,
  }) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> dispose() async {
    final result = await super.dispose();
    fullyDisposed = true;
    return result;
  }
}

void main() {
  for (final source in ['server', 'transport']) {
    testWidgets(
      'remote $source hang-up closes screen and stops native call service',
      (tester) async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final native = <String>[];
        for (final name in [
          'FlutterWebRTC.Method',
          'livekit_client',
          'ru.mykids/calls',
          'flutter.baseflow.com/permissions/methods',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
            if (name == 'ru.mykids/calls') native.add(call.method);
            if (call.method == 'requestPermissions') {
              return {
                for (final value in call.arguments as List) value as int: 1,
              };
            }
            return null;
          });
        }
        final repo = ConnectedFixture();
        final room = ConnectedRoom();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CallScreen(
                        repository: repo,
                        callId: 'fixture',
                        testRoom: room,
                      ),
                    ),
                  ),
                  child: const Text('Позвонить'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Позвонить'));
        await tester.pumpAndSettle();
        final callState = tester.state(find.byType(CallScreen)) as dynamic;
        expect(
          callState.connected,
          isTrue,
          reason: '${callState.status}; native=$native',
        );
        await tester.tap(find.text('Ещё'));
        await tester.pumpAndSettle();
        expect(find.text('Динамик'), findsOneWidget);
        if (source == 'server') {
          repo.endOnServer();
        } else {
          // The synthetic transport must inject the SDK event without a socket.
          // ignore: invalid_use_of_internal_member
          room.events.emit(RoomDisconnectedEvent());
        }
        await tester.pumpAndSettle();
        expect(find.byType(CallScreen), findsNothing);
        expect(find.text('Динамик'), findsNothing);
        expect(native, contains('stop'));
        expect(repo.leaves, 0);
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 20 && !room.fullyDisposed; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        expect(room.fullyDisposed, isTrue);
        for (final name in [
          'FlutterWebRTC.Method',
          'livekit_client',
          'ru.mykids/calls',
          'flutter.baseflow.com/permissions/methods',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
        repo.client.close();
        repo.dispose();
      },
    );
  }
}
