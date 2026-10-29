import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/background.dart' show nativeCalls;
import 'package:mykids_family/invitation_dialog.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';

class TestCamera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  int starts = 0, stops = 0, disposals = 0;
  bool denied = false;
  Completer<void>? stopGate;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async => disposals++;
  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final token = List.filled(43, 'a').join();
  for (final role in Invitation.roles) {
    test('QR preserves the exact one-time token for $role', () {
      final invitation = Invitation(role: role, token: token);
      final decoded = Invitation.parse(invitation.qrData, expectedRole: role);
      expect(decoded.token, token);
      expect(decoded.role, role);
      expect(invitation.qrData.contains('https:'), false);
    });
  }
  test('foreign and malformed QR codes cannot supply a family invitation', () {
    final valid = Invitation(role: 'child', token: token).qrData;
    for (final data in [
      'https://foreign.example/invite?token=$token',
      token,
      valid.replaceFirst('mykids:', 'https:'),
      valid.replaceFirst('invite?', 'invite:443?'),
      valid.replaceFirst('invite?', 'invite/path?'),
      valid.replaceFirst('invite?', 'user@invite?'),
      '$valid#fragment',
      '$valid&token=$token',
      '$valid&endpoint=https://foreign.example',
      valid.replaceFirst('version=1', 'version=2'),
      valid.replaceFirst(token, 'short'),
      valid.replaceFirst(token, '${token.substring(1)}%2F'),
      valid.replaceFirst('role=child', 'role=admin'),
      List.filled(513, 'a').join(),
    ]) {
      expect(
        () => Invitation.parse(data, expectedRole: 'child'),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
  test('a valid invitation for a different application is rejected', () {
    expect(
      () => Invitation.parse(
        Invitation(role: 'parent', token: token).qrData,
        expectedRole: 'child',
      ),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.message,
          'message',
          contains('родителей'),
        ),
      ),
    );
  });
  testWidgets(
    'invitation fits a small screen with large text and copies raw token',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = call.arguments as Map;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        nativeCalls,
        (call) async {
          expect(call.method, 'copyInvitation');
          clipboard = {'text': (call.arguments as Map)['token']};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          nativeCalls,
          null,
        ),
      );
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
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => InvitationDialog(
                    invitation: Invitation(role: 'child', token: token),
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
      expect(find.byType(InvitationQr), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Скопировать'));
      await tester.pumpAndSettle();
      expect(clipboard?['text'], token);
      expect(find.text('Код скопирован'), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
    },
  );

  late TestCamera camera;
  late MobileScannerPlatform original;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = TestCamera();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = original;
  });
  Future<FamilyRepository> openScanner(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = FamilyRepository()..variant = 'child';
    addTearDown(() {
      repo.client.close();
      repo.dispose();
    });
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
    await tester.tap(find.text('У меня есть приглашение'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сканировать QR-код'));
    await tester.pumpAndSettle();
    return repo;
  }

  BarcodeCapture capture(String role) => BarcodeCapture(
    barcodes: [
      Barcode(
        rawValue: Invitation(role: role, token: token).qrData,
        format: BarcodeFormat.qrCode,
      ),
    ],
  );
  testWidgets(
    'scanning fills the child invite without submitting registration',
    (tester) async {
      final repo = await openScanner(tester);
      camera.captures.add(capture('parent'));
      await tester.pumpAndSettle();
      expect(
        find.text('Это приглашение для родителей. Выберите эту роль'),
        findsOneWidget,
      );
      camera.captures.add(capture('child'));
      camera.captures.add(capture('child'));
      await tester.pumpAndSettle();
      expect(find.byType(MobileScanner), findsNothing);
      expect(find.widgetWithText(TextField, token), findsOneWidget);
      expect(repo.signedIn, false);
      expect(camera.stops, greaterThan(0));
      expect(camera.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('camera permission denial leaves manual input available', (
    tester,
  ) async {
    camera.denied = true;
    await openScanner(tester);
    expect(
      find.text(
        'Разрешите MyKIDS доступ к камере, чтобы прочитать приглашение.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Ввести код вручную'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('login-invite')),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Приглашение от родителя'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('returning during camera stop cannot close the login screen', (
    tester,
  ) async {
    await openScanner(tester);
    camera.stopGate = Completer<void>();
    camera.captures.add(capture('child'));
    await tester.pump();
    await tester.tap(find.text('Ввести код вручную'));
    await tester.pump(const Duration(milliseconds: 400));
    camera.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, token), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'camera pauses in background and resumes without capturing there',
    (tester) async {
      await openScanner(tester);
      final starts = camera.starts;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      camera.captures.add(capture('child'));
      await tester.pump();
      expect(find.byType(MobileScanner), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.starts, greaterThan(starts));
      await tester.tap(find.text('Ввести код вручную'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
