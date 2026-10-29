import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/invitation_scanner.dart';

class InvitationCamera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  Completer<void>? startGate;
  Completer<void>? stopGate;
  int starts = 0, stops = 0, disposals = 0;
  bool running = false;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    await startGate?.future;
    running = true;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
    running = false;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    running = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MobileScannerPlatform previous;
  late InvitationCamera camera;
  late GlobalKey<NavigatorState> navigator;
  Invitation? accepted;

  setUp(() {
    previous = MobileScannerPlatform.instance;
    camera = InvitationCamera();
    MobileScannerPlatform.instance = camera;
    navigator = GlobalKey<NavigatorState>();
    accepted = null;
  });

  Future<void> mount(WidgetTester tester, {bool pending = false}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      if (camera.startGate?.isCompleted == false) camera.startGate!.complete();
      if (camera.stopGate?.isCompleted == false) camera.stopGate!.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      MobileScannerPlatform.instance = previous;
      await camera.captures.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Ввод приглашения')),
      ),
    );
    unawaited(
      navigator.currentState!
          .push<Invitation>(
            MaterialPageRoute<Invitation>(
              builder: (_) => const InvitationScanner(role: 'child'),
            ),
          )
          .then((value) => accepted = value),
    );
    if (pending) {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    } else {
      await tester.pumpAndSettle();
      expect(camera.running, isTrue);
    }
  }

  Future<void> cover(WidgetTester tester) async {
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Экран поверх камеры')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('covering the invitation scanner releases the camera', (
    tester,
  ) async {
    await mount(tester);
    await cover(tester);
    expect(camera.running, isFalse);
    expect(camera.stops, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(camera.running, isTrue);
    expect(camera.starts, 2);
  });

  testWidgets('background resume cannot restart a covered scanner', (
    tester,
  ) async {
    await mount(tester);
    await cover(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    final starts = camera.starts;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.starts, starts);
    expect(camera.running, isFalse);
    expect(find.text('Экран поверх камеры'), findsOneWidget);
  });

  testWidgets('a late camera start releases a session covered during startup', (
    tester,
  ) async {
    camera.startGate = Completer<void>();
    await mount(tester, pending: true);
    expect(camera.starts, 1);
    await cover(tester);
    camera.startGate!.complete();
    await tester.pumpAndSettle();
    expect(camera.running, isFalse);
    expect(camera.stops, 1);
    expect(accepted, isNull);
  });

  testWidgets('retained manual entry cannot close a covering route', (
    tester,
  ) async {
    await mount(tester);
    final callback = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Ввести код вручную'),
        )
        .onPressed!;
    await cover(tester);
    callback();
    await tester.pumpAndSettle();
    expect(find.text('Экран поверх камеры'), findsOneWidget);
    expect(accepted, isNull);
  });

  testWidgets('retained manual entry is harmless after scanner disposal', (
    tester,
  ) async {
    await mount(tester);
    final callback = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Ввести код вручную'),
        )
        .onPressed!;
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(callback, returnsNormally);
    expect(find.text('Ввод приглашения'), findsOneWidget);
    expect(camera.running, isFalse);
    expect(camera.disposals, 1);
  });

  testWidgets(
    'manual entry closes the current scanner and releases its camera',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Ввести код вручную'));
      await tester.pumpAndSettle();
      expect(find.text('Ввод приглашения'), findsOneWidget);
      expect(camera.running, isFalse);
      expect(camera.disposals, 1);
      expect(accepted, isNull);
    },
  );

  testWidgets('only a matching invitation returns from the current scanner', (
    tester,
  ) async {
    await mount(tester);
    final valid = Invitation(role: 'child', token: 'a' * 43);
    camera.captures.add(
      BarcodeCapture(barcodes: [Barcode(rawValue: valid.qrData)]),
    );
    await tester.pumpAndSettle();
    expect(accepted?.token, valid.token);
    expect(accepted?.role, 'child');
    expect(find.text('Ввод приглашения'), findsOneWidget);
    expect(camera.running, isFalse);
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
  });

  testWidgets(
    'covered captures and wrong role invitations do not return a token',
    (tester) async {
      await mount(tester);
      final callback = tester
          .widget<MobileScanner>(find.byType(MobileScanner))
          .onDetect!;
      callback(
        BarcodeCapture(
          barcodes: [
            Barcode(
              rawValue: Invitation(role: 'parent', token: 'b' * 43).qrData,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Это приглашение для родителей. Выберите эту роль'),
        findsOneWidget,
      );
      expect(camera.running, isTrue);
      await cover(tester);
      callback(
        BarcodeCapture(
          barcodes: [
            Barcode(
              rawValue: Invitation(role: 'child', token: 'c' * 43).qrData,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Экран поверх камеры'), findsOneWidget);
      expect(accepted, isNull);
    },
  );

  testWidgets('an interrupted QR return resumes scanning after uncovering', (
    tester,
  ) async {
    await mount(tester);
    camera.stopGate = Completer<void>();
    camera.captures.add(
      BarcodeCapture(
        barcodes: [
          Barcode(
            rawValue: Invitation(role: 'child', token: 'd' * 43).qrData,
          ),
        ],
      ),
    );
    await tester.pump();
    expect(camera.stops, 1);
    await cover(tester);
    camera.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(accepted, isNull);
    expect(find.text('Экран поверх камеры'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(camera.running, isTrue);
    expect(find.text('Сканировать приглашение'), findsOneWidget);
  });

  testWidgets(
    'backgrounding during QR completion keeps the scanner resumable',
    (tester) async {
      await mount(tester);
      camera.stopGate = Completer<void>();
      camera.captures.add(
        BarcodeCapture(
          barcodes: [
            Barcode(
              rawValue: Invitation(role: 'child', token: 'e' * 43).qrData,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(camera.stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      camera.stopGate!.complete();
      await tester.pumpAndSettle();
      expect(accepted, isNull);
      expect(camera.running, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.running, isTrue);
      expect(find.text('Сканировать приглашение'), findsOneWidget);
    },
  );
}
