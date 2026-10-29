import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:mykids_family/call_screen.dart';

import 'remote_hangup_test.dart' as fixture;

class ReadyRoom extends fixture.ConnectedRoom {
  @override
  lk.ConnectionState get connectionState => lk.ConnectionState.connected;

  void mediaChanged() => notifyListeners();
}

class VideoFixture extends fixture.ConnectedFixture {
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
    'video': true,
  };
}

void main() {
  for (final testCase in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    final video = testCase.$1, locked = testCase.$2;
    testWidgets(
      video
          ? 'camera refusal keeps audio and explanation; locked=$locked'
          : 'receiver and LiveKit speaker controls; locked=$locked',
      (tester) async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <MethodCall>[];
        final routes = <List<bool>>[];
        final channels = [
          'FlutterWebRTC.Method',
          'livekit_client',
          'ru.mykids/calls',
          'flutter.baseflow.com/permissions/methods',
        ];
        for (final name in channels) {
          messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
            calls.add(call);
            if (call.method == 'requestPermissions') {
              return {for (final id in call.arguments as List) id as int: 1};
            }
            if (call.method == 'checkPermissionStatus') return 1;
            if (call.method == 'deviceLocked') return locked;
            if (video &&
                call.method == 'start' &&
                (call.arguments as Map)['video'] == true) {
              throw PlatformException(
                code: 'CALL_SERVICE',
                message: 'Camera blocked by phone',
              );
            }
            return null;
          });
        }
        final repo = video ? VideoFixture() : fixture.ConnectedFixture();
        final room = ReadyRoom();
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
                        testSpeakerRouting: (preferred, force) async =>
                            routes.add([preferred, force]),
                      ),
                    ),
                  ),
                  child: const Text('Открыть звонок'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть звонок'));
        await tester.pumpAndSettle();
        expect(find.byType(CallScreen), findsOneWidget);
        if (video) {
          expect(find.textContaining('Камера недоступна'), findsOneWidget);
          room.mediaChanged();
          await tester.pumpAndSettle();
          expect(find.textContaining('Камера недоступна'), findsOneWidget);
          expect(
            calls
                .where(
                  (call) =>
                      call.method == 'start' &&
                      (call.arguments as Map)['video'] == false,
                )
                .length,
            2,
          );
        } else {
          expect(routes, [
            [false, false],
          ]);
          await tester.tap(find.text('Ещё'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Динамик'));
          await tester.pumpAndSettle();
          expect(routes.last, [true, true]);
          await tester.tap(find.text('Ещё'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Динамик'));
          await tester.pumpAndSettle();
          expect(routes.last, [false, false]);
          expect(
            calls.any((call) => call.method == 'setSpeakerphoneOn'),
            isFalse,
          );
        }
        expect(tester.takeException(), isNull);
        if (locked) {
          expect(
            calls.where((call) => call.method == 'requestPermissions'),
            isEmpty,
            reason: 'An incoming call never launches a permission/PIN prompt over the lock screen',
          );
        }
        repo.endOnServer();
        await tester.pumpAndSettle();
        for (var i = 0; i < 20 && !room.fullyDisposed; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        expect(room.fullyDisposed, isTrue);
        for (final name in channels) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
        repo.client.close();
        repo.dispose();
      },
    );
  }
}
