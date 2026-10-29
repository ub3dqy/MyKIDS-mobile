import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/incoming_calls.dart';
import 'package:mykids_family/repository.dart';

class CallFixture extends FamilyRepository {
  bool failDecline = false;
  final actions = <String>[];
  CallFixture() {
    token = 'synthetic-session';
    variant = 'parent';
    online = true;
    snapshot = {
      'user': {'id': 'parent', 'role': 'parent'},
      'members': [
        {'id': 'child', 'name': 'Проверочный ребёнок'},
      ],
      'calls': <Map<String, dynamic>>[],
    };
  }
  void invite({
    bool video = false,
    String status = 'ringing',
    String member = 'invited',
  }) {
    snapshot!['calls'] = [
      {
        'id': 'fixture-call',
        'caller_id': 'child',
        'video': video ? 1 : 0,
        'status': status,
        'member_status': member,
      },
    ];
    notifyListeners();
  }

  @override
  Future<void> sync() async {}
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    actions.add(body['action'] as String);
    if (failDecline) throw ApiFailure(503, 'Проверочная ошибка связи');
    snapshot!['calls'][0]['member_status'] = 'declined';
    notifyListeners();
    return {'ok': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CallFixture repo;
  late GlobalKey<NavigatorState> key;
  late FamilyCallNavigation navigation;
  final native = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    repo = CallFixture();
    key = GlobalKey<NavigatorState>();
    navigation = FamilyCallNavigation();
    native.clear();
    messenger.setMockMethodCallHandler(const MethodChannel('ru.mykids/calls'), (
      call,
    ) async {
      native.add(call.method);
      return null;
    });
  });
  tearDown(() {
    repo.client.close();
    repo.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.mykids/calls'),
      null,
    );
  });
  Future<void> app(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [navigation],
        builder: (_, child) => IncomingCallHost(
          repository: repo,
          navigatorKey: key,
          navigation: navigation,
          callBuilder: (id) {
            repo.snapshot!['calls'][0]['member_status'] = 'joined';
            return Scaffold(body: Text('Принят $id'));
          },
          child: child!,
        ),
        home: const Scaffold(body: Text('Сегодня')),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  for (final video in [false, true]) {
    testWidgets(
      'incoming ${video ? 'video' : 'audio'} appears over chat without notification permission and only answers on click',
      (tester) async {
        await app(tester);
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Открытый чат')),
          ),
        );
        await tester.pumpAndSettle();
        repo.invite(video: video);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text(video ? 'Входящий видеозвонок' : 'Входящий аудиозвонок'),
          findsOneWidget,
        );
        expect(find.text('Проверочный ребёнок'), findsOneWidget);
        expect(repo.actions, isEmpty);
        expect(native.where((m) => m == 'ring').length, 1);
        repo.invite(video: video);
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Ответить'));
        await tester.pumpAndSettle();
        expect(find.text('Принят fixture-call'), findsOneWidget);
        expect(native, contains('stopRinging'));
        expect(navigation.inCall, true);
        key.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('Открытый чат'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        await close(tester);
      },
    );
  }
  testWidgets('decline error is visible and retry closes the invitation', (
    tester,
  ) async {
    await app(tester);
    repo.invite();
    repo.failDecline = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Отклонить'));
    await tester.pump();
    expect(find.text('Проверочная ошибка связи'), findsOneWidget);
    repo.failDecline = false;
    await tester.tap(find.text('Отклонить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.actions, ['decline', 'decline']);
    await close(tester);
  });
  testWidgets(
    'offline, caller and ended invitations do not ring; fresh invitation disappears when caller cancels',
    (tester) async {
      repo.online = false;
      repo.invite();
      await app(tester);
      expect(find.byType(AlertDialog), findsNothing);
      repo.online = true;
      repo.invite(member: 'joined');
      await tester.pump();
      repo.invite(status: 'ended');
      await tester.pump();
      expect(native, isEmpty);
      repo.invite();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      repo.invite(status: 'ended');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Сегодня'), findsOneWidget);
      await close(tester);
    },
  );
}
