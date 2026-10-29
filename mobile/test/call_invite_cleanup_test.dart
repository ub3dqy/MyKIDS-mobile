import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mykids_family/call_screen.dart';
import 'package:mykids_family/repository.dart';

class InviteRepository extends FamilyRepository {
  InviteRepository() {
    token = 'synthetic-call';
    snapshot = {
      'user': {'id': 'child', 'role': 'child'},
      'members': [
        {
          'id': 'parent',
          'name': 'Проверочный взрослый',
          'role': 'parent',
          'active': 1,
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
  }) async => {'ok': true};
  void revoke() {
    token = null;
    notifyListeners();
  }
}

class InviteTestRoom extends Room {
  bool disposed = false;
  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> dispose() async {
    final result = await super.dispose();
    disposed = true;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final painted in [false, true]) {
    testWidgets(
      'revoking access closes the invitation sheet and the call underneath it: painted=$painted',
      (tester) async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channels = [
          'FlutterWebRTC.Method',
          'livekit_client',
          'ru.mykids/calls',
          'flutter.baseflow.com/permissions/methods',
        ];
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(
            MethodChannel(channel),
            (call) async => call.method == 'requestPermissions'
                ? {for (final value in call.arguments as List) value as int: 0}
                : null,
          );
        }
        addTearDown(() {
          for (final channel in channels) {
            messenger.setMockMethodCallHandler(MethodChannel(channel), null);
          }
        });
        final repo = InviteRepository();
        final room = InviteTestRoom();
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
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(CallScreen)) as dynamic;
        state.inviteParticipant();
        if (painted) {
          await tester.pumpAndSettle();
          expect(find.text('Проверочный взрослый'), findsOneWidget);
        }
        repo.revoke();
        await tester.pumpAndSettle();
        expect(find.byType(CallScreen), findsNothing);
        expect(find.text('Проверочный взрослый'), findsNothing);
        for (var attempt = 0; attempt < 20 && !room.disposed; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        expect(room.disposed, true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        repo.client.close();
        repo.dispose();
      },
    );
  }
}
