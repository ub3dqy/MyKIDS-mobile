import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mykids_family/call_screen.dart';
import 'package:mykids_family/repository.dart';

class FailingDisconnectRoom extends Room {
  int disconnects = 0;
  bool disposed = false;
  @override
  Future<void> disconnect() async {
    disconnects++;
    throw StateError('simulated disconnection timeout');
  }

  @override
  Future<bool> dispose() async {
    final result = await super.dispose();
    disposed = true;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'disconnect failure still stops Android service and closes the call',
    (tester) async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('livekit_client'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'requestPermissions') {
            return {
              for (final value in call.arguments as List) value as int: 1,
            };
          }
          return 1;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('ru.mykids/calls'),
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      final room = FailingDisconnectRoom();
      final repo = FamilyRepository();
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
                      callId: 'synthetic-call',
                      testRoom: room,
                    ),
                  ),
                ),
                child: const Text('Открыть тестовый звонок'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть тестовый звонок'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Не удалось подключиться к семейному звонку'),
        findsOneWidget,
      );
      expect(calls, contains('stop'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Завершить'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 20 && !room.disposed; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.byType(CallScreen), findsNothing);
      expect(room.disposed, true);
      expect(room.disconnects, greaterThanOrEqualTo(2));
      expect(
        calls.where((method) => method == 'stop').length,
        greaterThanOrEqualTo(2),
      );
      expect(tester.takeException(), isNull);
      repo.client.close();
      repo.dispose();
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('ru.mykids/calls'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('livekit_client'),
        null,
      );
    },
  );
}
