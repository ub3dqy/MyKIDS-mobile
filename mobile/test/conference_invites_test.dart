import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/call_screen.dart';

import 'call_invite_cleanup_test.dart' show InviteRepository, InviteTestRoom;

class ConferenceRepository extends InviteRepository {
  ConferenceRepository() {
    snapshot!['user'] = {'id': 'papa', 'role': 'parent'};
    snapshot!['members'] = [
      {'id': 'papa', 'name': 'Папа', 'role': 'parent', 'active': 1},
      {'id': 'mama', 'name': 'Мама', 'role': 'parent', 'active': 1},
      {'id': 'stepa', 'name': 'Стёпа', 'role': 'child', 'active': 1},
      {'id': 'grandma', 'name': 'Бабушка 1', 'role': 'relative', 'active': 1},
      {'id': 'grandpa', 'name': 'Дедушка 1', 'role': 'relative', 'active': 1},
    ];
    reserve(['papa', 'mama']);
  }
  void reserve(List<String> ids) {
    snapshot!['calls'] = [
      {
        'id': 'fixture',
        'room_id': 'private',
        'caller_id': 'papa',
        'status': 'active',
        'member_status': 'joined',
        'participants': [
          for (final id in ids)
            {'user_id': id, 'status': id == 'grandma' ? 'invited' : 'joined'},
        ],
      },
    ];
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'conference picker includes the child and updates reserved places before the fourth joins',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final repo = ConferenceRepository();
      final room = InviteTestRoom();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Builder(
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
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(CallScreen)) as dynamic;
      state.inviteParticipant();
      await tester.pumpAndSettle();
      expect(find.text('Стёпа'), findsOneWidget);
      expect(find.text('Участники: 2 из 4'), findsOneWidget);
      expect(find.text('Мама'), findsNothing);
      repo.reserve(['papa', 'mama', 'stepa', 'grandma']);
      await tester.pumpAndSettle();
      expect(find.text('Участники: 4 из 4'), findsOneWidget);
      expect(find.text('В конференции уже четыре участника'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
      expect(tester.takeException(), isNull);
      repo.revoke();
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      for (var attempt = 0; attempt < 20 && !room.disposed; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(room.disposed, true);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );
}
