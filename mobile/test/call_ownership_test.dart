import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/call_screen.dart';

import 'remote_hangup_test.dart' as fixture;

class DelayedDisconnectRoom extends fixture.ConnectedRoom {
  final release = Completer<void>();
  @override
  Future<void> disconnect() => release.future;
}

void main() {
  testWidgets(
    'late cleanup removes only its route and keeps reopened call ownership',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final native = <MethodCall>[];
      String? active;
      final channels = [
        'FlutterWebRTC.Method',
        'livekit_client',
        'ru.mykids/calls',
        'flutter.baseflow.com/permissions/methods',
      ];
      for (final name in channels) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          if (call.method == 'requestPermissions') {
            return {for (final id in call.arguments as List) id as int: 1};
          }
          if (call.method == 'deviceLocked') return false;
          if (name == 'ru.mykids/calls') {
            native.add(call);
            final owner = (call.arguments as Map?)?['owner'] as String?;
            if (call.method == 'claimCall') active = owner;
            if (call.method == 'stop' && active == owner) active = null;
          }
          return null;
        });
      }
      final repo = fixture.ConnectedFixture();
      final firstRoom = DelayedDisconnectRoom();
      final secondRoom = fixture.ConnectedRoom();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Домой')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            repository: repo,
            callId: 'fixture',
            testRoom: firstRoom,
            testSpeakerRouting: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final firstState = tester.state(find.byType(CallScreen)) as dynamic;
      final closing = firstState.close(remote: true) as Future<void>;
      await tester.pump();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            repository: repo,
            callId: 'fixture',
            testRoom: secondRoom,
            testSpeakerRouting: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final leases = native
          .where((c) => c.method == 'claimCall')
          .map((c) => (c.arguments as Map)['owner'])
          .toList();
      expect(leases.length, 2);
      expect(leases[0], isNot(leases[1]));
      firstRoom.release.complete();
      await tester.pumpAndSettle();
      await closing;
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsOneWidget);
      expect(
        (tester.state(find.byType(CallScreen)) as dynamic).connected,
        isTrue,
      );
      expect(active, leases[1]);
      expect(
        native
            .where((c) => c.method == 'stop')
            .every((c) => (c.arguments as Map)['owner'] == leases[0]),
        isTrue,
      );
      await tester.tap(find.text('Завершить'));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      expect(active, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      for (
        var i = 0;
        i < 20 && (!firstRoom.fullyDisposed || !secondRoom.fullyDisposed);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(firstRoom.fullyDisposed && secondRoom.fullyDisposed, isTrue);
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
      for (final name in channels) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    },
  );
}
