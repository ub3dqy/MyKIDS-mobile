import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/role_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

class WaitingLogin extends FamilyRepository {
  final responses = <Completer<void>>[];
  final credentials = <Map<String, String?>>[];

  @override
  Future<void> selectRole(String role) async {
    variant = role;
    notifyListeners();
  }

  @override
  Future<void> login(
    String server,
    String username,
    String password, {
    String? invite,
    String? name,
  }) {
    final response = Completer<void>();
    responses.add(response);
    credentials.add({
      'username': username,
      'password': password,
      'invite': invite,
      'name': name,
    });
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  final repositories = <FamilyRepository>[];

  setUp(() async {
    folder = await Directory.systemTemp.createTemp(
      'mykids-login-interruption-',
    );
    await databaseFactory.setDatabasesPath(folder.path);
    FlutterSecureStorage.setMockInitialValues({
      'endpoint': 'https://family-a.example',
      'setup_role': 'parent',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });

  tearDown(() async {
    for (final repo in repositories) {
      await repo.db?.close();
      repo.client.close();
      repo.dispose();
    }
    repositories.clear();
    await deleteOwnedTestTemp(folder);
  });

  Map<String, dynamic> state(String id) => {
    'user': {'id': id, 'role': 'parent'},
  };

  Future<FamilyRepository> initialize(MockClient client) async {
    final repo = FamilyRepository(client: client);
    repositories.add(repo);
    await repo.initialize();
    return repo;
  }

  test('a cancelled sign-in response cannot restore the old account', () async {
    final entered = Completer<void>(), answer = Completer<http.Response>();
    var snapshots = 0;
    final repo = await initialize(
      MockClient((request) async {
        if (request.url.path == '/v1/login') {
          entered.complete();
          return answer.future;
        }
        snapshots++;
        return http.Response(jsonEncode(state('cancelled-parent')), 200);
      }),
    );
    final pending = repo
        .login('https://family-a.example', 'synthetic', 'local-only-password')
        .then<Object?>((_) => null, onError: (Object e) => e);
    await entered.future;
    expect(await repo.cancelLogin(), true);
    answer.complete(http.Response('{"token":"discarded-login-token"}', 200));
    final outcome = await pending;
    expect(outcome, isA<ApiFailure>());
    expect(repo.signedIn, false);
    expect(repo.snapshot, isNull);
    expect(await repo.storage.read(key: 'session'), isNull);
    expect(snapshots, 0);
  });

  test(
    'a late sign-in cannot replace a newer account or forward its token',
    () async {
      final entered = Completer<void>(), oldAnswer = Completer<http.Response>();
      final forwarded = <String>[];
      final repo = await initialize(
        MockClient((request) async {
          if (request.url.host == 'family-a.example' &&
              request.url.path == '/v1/login') {
            entered.complete();
            return oldAnswer.future;
          }
          if (request.url.host == 'family-b.example' &&
              request.headers['Authorization'] == 'Bearer stale-a-token') {
            forwarded.add(request.url.toString());
          }
          if (request.url.path == '/v1/login') {
            return http.Response('{"token":"fresh-b-token"}', 200);
          }
          return http.Response(jsonEncode(state('fresh-account-b')), 200);
        }),
      );
      final old = repo
          .login('https://family-a.example', 'first', 'local-only-password')
          .then<Object?>((_) => null, onError: (Object e) => e);
      await entered.future;
      await repo.login(
        'https://family-b.example',
        'second',
        'local-only-password',
      );
      oldAnswer.complete(http.Response('{"token":"stale-a-token"}', 200));
      expect(await old, isA<ApiFailure>());
      expect(forwarded, isEmpty);
      expect(repo.token, 'fresh-b-token');
      expect(repo.userId, 'fresh-account-b');
      expect(await repo.storage.read(key: 'session'), 'fresh-b-token');
    },
  );

  test(
    'cancellation while loading the family leaves no credentials or cache',
    () async {
      final entered = Completer<void>(), answer = Completer<http.Response>();
      final repo = await initialize(
        MockClient((request) async {
          if (request.url.path == '/v1/login') {
            return http.Response('{"token":"unconfirmed-token"}', 200);
          }
          entered.complete();
          return answer.future;
        }),
      );
      final pending = repo
          .login('https://family-a.example', 'synthetic', 'local-only-password')
          .then<Object?>((_) => null, onError: (Object e) => e);
      await entered.future;
      expect(repo.token, 'unconfirmed-token');
      expect(await repo.cancelLogin(), true);
      answer.complete(
        http.Response(jsonEncode(state('cancelled-parent')), 200),
      );
      expect(await pending, isA<ApiFailure>());
      expect(repo.signedIn, false);
      expect(repo.snapshot, isNull);
      expect(await repo.storage.read(key: 'session'), isNull);
      for (final table in ['identity', 'cache', 'outbox']) {
        expect(await repo.db!.query(table), isEmpty);
      }
    },
  );

  test('cancelling cannot log out an already confirmed family', () async {
    final repo = await initialize(
      MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path == '/v1/login'
                ? {'token': 'confirmed-token'}
                : state('confirmed-parent'),
          ),
          200,
        ),
      ),
    );
    await repo.login(
      'https://family-a.example',
      'synthetic',
      'local-only-password',
    );
    expect(await repo.cancelLogin(), false);
    expect(repo.userId, 'confirmed-parent');
    expect(await repo.storage.read(key: 'session'), 'confirmed-token');
    expect(await repo.db!.query('cache'), hasLength(1));
  });

  test(
    'overlapping local preparation sends only the newest credentials',
    () async {
      final usernames = <String>[];
      final repo = await initialize(
        MockClient((request) async {
          if (request.url.path == '/v1/login') {
            usernames.add(
              (jsonDecode(request.body) as Map)['username'] as String,
            );
            return http.Response('{"token":"newest-token"}', 200);
          }
          return http.Response(jsonEncode(state('newest-parent')), 200);
        }),
      );
      final old = repo
          .login('https://family-a.example', 'first', 'local-only-password')
          .then<Object?>((_) => null, onError: (Object e) => e);
      final fresh = repo.login(
        'https://family-b.example',
        'second',
        'local-only-password',
      );
      expect(await old, isA<ApiFailure>());
      await fresh;
      expect(usernames, ['second']);
      expect(repo.token, 'newest-token');
      expect(repo.endpoint, 'https://family-b.example');
    },
  );

  Future<WaitingLogin> openLogin(
    WidgetTester tester, {
    String role = 'parent',
    double textScale = 1,
    Future<void> Function()? onLogin,
  }) async {
    final repo = WaitingLogin()
      ..variant = role
      ..endpoint = 'https://family-a.example';
    repositories.add(repo);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AnimatedBuilder(
          animation: repo,
          builder: (_, _) => repo.variant.isEmpty
              ? RoleScreen(repository: repo)
              : LoginScreen(
                  repository: repo,
                  onLogin: onLogin ?? () async {},
                  onUpdates: () async {},
                ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('login-username')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'synthetic',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('login-password')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'local-only-password',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Войти'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pump();
    expect(repo.responses, hasLength(1));
    return repo;
  }

  for (final role in FamilyRepository.roles) {
    testWidgets('$role can return to role choice during a waiting connection', (
      tester,
    ) async {
      var completed = 0;
      final repo = await openLogin(
        tester,
        role: role,
        onLogin: () async {
          completed++;
        },
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repo.variant, '');
      expect(find.byType(RoleScreen), findsOneWidget);
      repo.responses.single.complete();
      await tester.pump();
      expect(completed, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('system Back cancels a waiting connection', (tester) async {
    final repo = await openLogin(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RoleScreen), findsOneWidget);
    repo.responses.single.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('child can cancel on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = await openLogin(tester, role: 'child', textScale: 2);
    await tester.scrollUntilVisible(
      find.text('Отменить подключение'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Отменить подключение'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Подключение…'), findsNothing);
    repo.responses.single.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'cancel preserves typed fields and a late failure cannot disturb retry',
    (tester) async {
      var completed = 0;
      final repo = await openLogin(
        tester,
        onLogin: () async {
          completed++;
        },
      );
      await tester.ensureVisible(find.text('Отменить подключение'));
      await tester.tap(find.text('Отменить подключение'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-password')))
            .controller!
            .text,
        'local-only-password',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();
      expect(repo.responses, hasLength(2));
      repo.responses.first.completeError(
        ApiFailure(401, 'Отменённый старый вход'),
      );
      await tester.pump();
      expect(find.text('Отменённый старый вход'), findsNothing);
      expect(find.text('Подключение…'), findsOneWidget);
      repo.responses.last.complete();
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-password')))
            .controller!
            .text,
        '',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelled invitation can recover a created profile using the same credentials',
    (tester) async {
      var completed = 0;
      final repo = await openLogin(
        tester,
        onLogin: () async {
          completed++;
        },
      );
      await tester.ensureVisible(find.text('Отменить подключение'));
      await tester.tap(find.text('Отменить подключение'));
      await tester.pumpAndSettle();
      repo.responses.first.complete();
      await tester.pump();
      await tester.ensureVisible(find.text('У меня есть приглашение'));
      await tester.tap(find.text('У меня есть приглашение'));
      await tester.pump();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      for (final entry in {
        'invite': 'local-invitation-token',
        'name': 'Тестовый участник',
      }.entries) {
        final finder = find.byKey(ValueKey('login-${entry.key}'));
        await tester.scrollUntilVisible(
          finder,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(finder, entry.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Присоединиться'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Присоединиться'));
      await tester.pump();
      expect(repo.credentials.last['invite'], 'local-invitation-token');
      await tester.ensureVisible(find.text('Отменить подключение'));
      await tester.tap(find.text('Отменить подключение'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Профиль мог уже создаться'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-invite')), findsNothing);
      repo.responses[1].complete();
      await tester.pump();
      expect(completed, 0);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Войти'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();
      expect(repo.credentials.last['invite'], isNull);
      expect(repo.credentials.last['username'], 'synthetic');
      expect(repo.credentials.last['password'], 'local-only-password');
      repo.responses.last.complete();
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
