import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android validates the newer signed APK and rejects invalid candidates',
    (tester) async {
      final info = (await nativeUpdates.invokeMapMethod<String, dynamic>(
        'appInfo',
      ))!;
      expect(info['package'], 'ru.mykids.mykids_family.parent');
      expect(info['versionCode'], 10);
      final file = File('${info['updateDirectory']}/MyKIDS-0.1.11.apk');
      await file.parent.create(recursive: true);
      await File('${info['updateDirectory']}/native-ready')
          .writeAsString('ready');
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (!await file.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('The isolated APK fixture was not copied');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final checksum = (await sha256.bind(file.openRead()).first).toString();
      final args = {
        'fileName': 'MyKIDS-0.1.11.apk',
        'versionCode': 12,
        'bytes': await file.length(),
        'sha256': checksum,
      };
      expect(
        await nativeUpdates.invokeMethod<String>('verifyUpdate', args),
        'verified',
      );
      for (final invalid in [
        {...args, 'sha256': List.filled(64, '0').join()},
        {...args, 'versionCode': 10},
        {...args, 'fileName': 'MyKIDS-child-0.1.11.apk'},
        {...args, 'fileName': '../MyKIDS-0.1.11.apk'},
        {...args, 'bytes': (args['bytes'] as int) + 1},
      ]) {
        await expectLater(
          nativeUpdates.invokeMethod<String>('verifyUpdate', invalid),
          throwsA(isA<PlatformException>()),
        );
      }
      for (final name in ['MyKIDS-0.1.10.apk', 'MyKIDS-0.1.9.apk']) {
        final rejected = File('${info['updateDirectory']}/$name');
        await expectLater(
          nativeUpdates.invokeMethod<String>('verifyUpdate', {
            'fileName': name,
            'versionCode': 11,
            'bytes': await rejected.length(),
            'sha256': (await sha256.bind(rejected.openRead()).first).toString(),
          }),
          throwsA(isA<PlatformException>()),
        );
      }
      final repo = FamilyRepository()..variant = 'child';
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(true),
          home: LoginScreen(
            repository: repo,
            onLogin: () async {},
            onUpdates: () async {},
          ),
        ),
      );
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(LoginScreen))),
      );
      // The child greeting has periodic frames; do not wait for it to stop.
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(find.text('Адрес семейного сервера'), findsNothing);
      expect(find.text('Проверить обновления приложения'), findsOneWidget);
      expect(tester.takeException(), isNull);
      bool captured = false;
      final capture = binding.takeScreenshot('unified-update-login');
      capture.whenComplete(() => captured = true).ignore();
      final captureDeadline = DateTime.now().add(const Duration(seconds: 25));
      while (!captured && DateTime.now().isBefore(captureDeadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      if (!captured) throw StateError('Native login screenshot timed out');
      await capture;
      binding.reportData = {
        ...?binding.reportData,
        'native_signature_verified': true,
        'invalid_candidates_rejected': true,
        'foreign_package_rejected': true,
        'foreign_signer_rejected': true,
        'scope': 'Android 16 emulator; unified debug APK (code 10) validates newer unified debug fixture (code 12) with matching debug signature; installer confirmation not automated',
      };
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );
}
