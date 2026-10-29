import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/role_screen.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

import '../test/support/messenger_fixture.dart';

class NoSetupUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri manifestUrl, String role) async => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'one Android package sets up all roles and opens their family contacts',
    (tester) async {
      final info = (await nativeUpdates.invokeMapMethod<String, dynamic>(
        'appInfo',
      ))!;
      expect(info['package'], 'ru.mykids.mykids_family.parent');
      const storage = FlutterSecureStorage();
      // Only the owned emulator, never a signed-in family installation.
      expect(await storage.read(key: 'session'), null);
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await binding.takeScreenshot('unified-$name');
      }

      for (final entry in {
        'parent': 'papa',
        'child': 'stepa',
        'relative': 'grandma1',
      }.entries) {
        await storage.delete(key: 'setup_role');
        final fixture = ContactsFixture(actorId: entry.value);
        final repo = FamilyRepository(
          client: MockClient((request) async {
            final body = request.url.path == '/v1/login'
                ? {'token': 'synthetic-android-${entry.key}'}
                : request.url.path == '/v1/snapshot'
                ? fixture.snapshot!
                : request.url.path.endsWith('/messages')
                ? {'messages': <dynamic>[]}
                : {'ok': true};
            return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
          }),
        );
        await repo.initialize();
        expect(repo.variant, '');
        await tester.pumpWidget(
          MyKidsApp(
            repository: repo,
            createUpdates: NoSetupUpdates.new,
            now: () => DateTime.utc(2026, 10, 12, 10),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
        );
        if (entry.key == 'parent') await capture('role-choice');
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('setup-${entry.key}')),
          200,
        );
        await tester.tap(find.byKey(ValueKey('setup-${entry.key}')));
        await tester.pumpAndSettle();
        expect(await storage.read(key: 'setup_role'), entry.key);
        await capture('${entry.key}-login');
        // Drive the same production login method with an artificial server response.
        await storage.write(key: 'morning:${entry.value}', value: '2026-10-12');
        await repo.login(
          'https://family.example',
          'synthetic-${entry.key}',
          'synthetic-password',
        );
        expect(repo.role, entry.key);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Семья'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Контакты'));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('contact-${entry.value}')), findsNothing);
        await capture('${entry.key}-contacts');
        final peer = entry.value == 'papa' ? 'mama' : 'papa';
        await tester.ensureVisible(find.byKey(ValueKey('contact-$peer')));
        await tester.tap(find.byKey(ValueKey('contact-$peer')));
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.byTooltip('Аудиозвонок'), findsOneWidget);
        expect(find.byTooltip('Видеозвонок'), findsOneWidget);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.logout(remote: false);
        await repo.db!.close();
        repo.client.close();
        repo.dispose();
        fixture.client.close();
        fixture.dispose();
        final restarted = FamilyRepository();
        await restarted.initialize();
        expect(restarted.variant, entry.key);
        await restarted.db!.close();
        restarted.client.close();
        restarted.dispose();
      }
      await storage.delete(key: 'setup_role');
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'roles_checked': 3,
        'package': info['package'],
        'native_firebase_existing_registration': true,
        'role_choice_persisted': true,
        'private_chat_calls_present': true,
        'physical_phones_tested': false,
      };
      expect(find.byType(RoleScreen), findsNothing);
    },
  );
}
