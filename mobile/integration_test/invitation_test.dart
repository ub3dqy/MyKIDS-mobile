import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/invitation_dialog.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'rendered QR codes decode on Android and fill the child invitation',
    (tester) async {
      final token = List.filled(43, 'a').join();
      final decoder = MobileScannerController(autoStart: false);
      final ownerRepo = FamilyRepository()
        ..token = 'synthetic-qr-owner'
        ..snapshot = {
          'user': {'id': 'synthetic-parent', 'role': 'parent'},
        };
      final owner = InvitationOwner(ownerRepo);
      addTearDown(() {
        owner.dispose();
        ownerRepo.client.close();
        ownerRepo.dispose();
      });
      final captures = <String, BarcodeCapture>{};
      final file = File(
        '${Directory.systemTemp.path}/mykids-synthetic-invitation.png',
      );
      await binding.convertFlutterSurfaceToImage();
      try {
        for (final role in Invitation.roles) {
          final invitation = Invitation(role: role, token: token);
          await tester.pumpWidget(
            MaterialApp(
              theme: familyTheme(false),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => InvitationDialog(
                        invitation: invitation,
                        owner: owner,
                        expiresAt: DateTime.now().toUtc().add(
                          const Duration(hours: 24),
                        ),
                      ),
                    ),
                    child: const Text('Пригласить'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Пригласить'));
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('invitation-qr')),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          final capture = await decoder.analyzeImage(
            file.path,
            formats: const [BarcodeFormat.qrCode],
          );
          expect(capture, isNotNull);
          expect(capture!.barcodes.single.rawValue, invitation.qrData);
          captures[role] = capture;
          if (role == 'child') {
            await binding.takeScreenshot('parent-invitation-qr');
          }
          await tester.tap(find.text('Закрыть'));
          await tester.pumpAndSettle();
        }
      } finally {
        if (await file.exists()) await file.delete();
        await decoder.dispose();
      }
      // The host driver grants camera only to this isolated emulator test app.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!await Permission.camera.isGranted) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Camera permission was not granted to the test app');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
      }
      final repo = FamilyRepository()..variant = 'child';
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('У меня есть приглашение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сканировать QR-код'));
      await tester.pump(const Duration(seconds: 1));
      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      final cameraDeadline = DateTime.now().add(const Duration(seconds: 25));
      while (!scanner.controller!.value.isRunning) {
        if (DateTime.now().isAfter(cameraDeadline)) {
          throw StateError('The Android camera did not start');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }
      scanner.onDetect!(captures['parent']!);
      await tester.pump();
      expect(
        find.text('Это приглашение для родителей. Выберите эту роль'),
        findsOneWidget,
      );
      scanner.onDetect!(captures['child']!);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(MobileScanner), findsNothing);
      expect(scanner.controller!.value.isRunning, false);
      expect(find.widgetWithText(TextField, token), findsOneWidget);
      expect(repo.signedIn, false);
      await binding.takeScreenshot('child-invitation-filled');
      binding.reportData = {
        ...?binding.reportData,
        'qr_roles_decoded': Invitation.roles,
        'camera_started_on_emulator': true,
        'wrong_role_rejected': true,
        'invite_field_filled': true,
        'registration_not_submitted': true,
        'scope': 'Android 16 emulator; bundled ML Kit decoded actual rendered QR images. Emulated camera started; decoded image results passed to the normal camera callback. Optical scanning between physical phones was not exercised. All tokens are synthetic and unregistered.',
      };
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    },
  );
}
