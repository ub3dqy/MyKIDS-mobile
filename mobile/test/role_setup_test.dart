import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/role_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_temp.dart';

class SetupFixture extends FamilyRepository {
  @override
  Future<void> sync() async {}
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory folder;
  final repositories = <FamilyRepository>[];
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    folder = await Directory.systemTemp.createTemp('mykids-setup-test-');
    await databaseFactory.setDatabasesPath(folder.path);
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
    expect(folder.parent.path, Directory.systemTemp.path);
    expect(
      folder.uri.pathSegments.any((e) => e.startsWith('mykids-setup-test-')),
      true,
    );
    await deleteOwnedTestTemp(folder);
  });

  test(
    'first launch has no role; saved choice survives restart and can be reset',
    () async {
      final repo = FamilyRepository();
      repositories.add(repo);
      await repo.initialize();
      expect(repo.variant, '');
      await repo.selectRole('relative');
      final restarted = FamilyRepository();
      repositories.add(restarted);
      await restarted.initialize();
      expect(restarted.variant, 'relative');
      await restarted.selectRole('');
      expect(await restarted.storage.read(key: 'setup_role'), '');
      await expectLater(repo.selectRole('admin'), throwsA(isA<ApiFailure>()));
      repo.token = 'synthetic-session';
      await expectLater(repo.selectRole('parent'), throwsA(isA<ApiFailure>()));
    },
  );

  for (final actualRole in FamilyRepository.roles) {
    test(
      'server account role overrides setup preference: $actualRole',
      () async {
        final fresh = {
          'user': {'id': 'synthetic-user', 'role': actualRole},
        };
        final repo = FamilyRepository(
          client: MockClient((request) async {
            expect(
              jsonDecode(request.body.isEmpty ? '{}' : request.body),
              isNot(contains('role')),
            );
            return http.Response(
              jsonEncode(
                request.url.path == '/v1/login'
                    ? {'token': 'synthetic-session'}
                    : fresh,
              ),
              200,
            );
          }),
        );
        repositories.add(repo);
        await repo.initialize();
        await repo.selectRole(actualRole == 'parent' ? 'child' : 'parent');
        await repo.login(
          'https://family.example',
          'synthetic',
          'synthetic-password',
        );
        expect(repo.role, actualRole);
        expect(repo.variant, actualRole);
        expect(repo.signedIn, true);
        final restarted = FamilyRepository(
          client: MockClient(
            (_) async => http.Response(jsonEncode(fresh), 200),
          ),
        );
        repositories.add(restarted);
        await restarted.initialize(actualRole == 'parent' ? 'child' : 'parent');
        expect(restarted.role, actualRole);
        expect(restarted.signedIn, true);
        await restarted.sync();
        expect(restarted.signedIn, true);
        expect(restarted.role, actualRole);
      },
    );
  }

  test('invalid server role cannot open an authenticated app', () async {
    final repo = FamilyRepository(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path == '/v1/login'
                ? {'token': 'synthetic-session'}
                : {
                    'user': {'id': 'synthetic-user', 'role': 'admin'},
                  },
          ),
          200,
        ),
      ),
    );
    repositories.add(repo);
    await repo.initialize();
    await repo.selectRole('parent');
    await expectLater(
      repo.login('https://family.example', 'synthetic', 'synthetic-password'),
      throwsA(isA<ApiFailure>()),
    );
    expect(repo.signedIn, false);
    expect(repo.snapshot, null);
  });

  for (final role in FamilyRepository.roles) {
    testWidgets('one app selects $role, opens login and returns to choice', (
      tester,
    ) async {
      final repo = SetupFixture()..endpoint = 'https://family.example';
      repositories.add(repo);
      await tester.pumpWidget(MyKidsApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.byType(RoleScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(ValueKey('setup-$role')), 200);
      await tester.tap(find.byKey(ValueKey('setup-$role')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(repo.variant, role);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(RoleScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('role choice fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FamilyRepository();
    repositories.add(repo);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: RoleScreen(repository: repo),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('setup-relative')),
      200,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('setup-relative'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-relative')));
    await tester.pumpAndSettle();
    expect(repo.variant, 'relative');
    expect(tester.takeException(), null);
  });
}
