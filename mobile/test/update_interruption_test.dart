import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final offer = UpdateOffer(
    role: 'family',
    package: 'ru.mykids.mykids_family.parent',
    version: '0.1.40',
    versionCode: 41,
    bytes: 100,
    sha: 'a' * 64,
    certificate: 'b' * 64,
    notes: 'Проверка прерванного обновления',
    url: Uri.parse('https://family.example/downloads/MyKIDS-0.1.40.apk'),
    directory: '/unused-updates',
  );
  late Map<String, Object> state;
  late List<String> calls;
  String? installError;
  bool statusFails = false;
  setUp(() {
    state = {'state': 'ready', 'received': 100, 'bytes': 100};
    calls = [];
    installError = null;
    statusFails = false;
    messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'downloadStatus':
          if (statusFails) throw PlatformException(code: 'UPDATE_DOWNLOAD');
          return state;
        case 'installUpdate':
          if (installError != null) {
            throw PlatformException(
              code: installError!,
              message: installError == 'UPDATE_SPACE'
                  ? 'Недостаточно места для установки обновления.'
                  : null,
            );
          }
          return 'installer_opened';
        case 'startDownload':
          return state = {'state': 'ready', 'received': 100, 'bytes': 100};
        case 'cancelDownload':
          state = {'state': 'idle'};
          return null;
        case 'cancelUpdate':
          return null;
        default:
          throw StateError('Unexpected native method: ${call.method}');
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(nativeUpdates, null));
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UpdateDialog(offer: offer)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final missing in ['idle', 'failed']) {
    testWidgets('a $missing APK can be downloaded again after install fails', (
      tester,
    ) async {
      await open(tester);
      state = {'state': missing};
      installError = 'UPDATE_INVALID';
      await tester.tap(find.text('Установить'));
      await tester.pumpAndSettle();
      expect(find.text('Скачать и обновить'), findsOneWidget);
      expect(calls.where((method) => method == 'startDownload'), isEmpty);
      installError = null;
      await tester.tap(find.text('Скачать и обновить'));
      await tester.pumpAndSettle();
      expect(calls.where((method) => method == 'startDownload'), hasLength(1));
      expect(calls.where((method) => method == 'installUpdate'), hasLength(1));
      expect(find.text('Установить'), findsOneWidget);
    });
  }
  testWidgets('an invalid APK remains retryable when status also fails', (
    tester,
  ) async {
    await open(tester);
    statusFails = true;
    installError = 'UPDATE_INVALID';
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();
    expect(find.text('Скачать и обновить'), findsOneWidget);
    expect(calls.where((method) => method == 'startDownload'), isEmpty);
  });
  testWidgets('a cancelled installer keeps a complete APK for explicit retry', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'installUpdate'), hasLength(1));
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'installUpdate'), hasLength(2));
    expect(calls.where((method) => method == 'startDownload'), isEmpty);
  });
  testWidgets('installer opening failure retains a still verified APK', (
    tester,
  ) async {
    await open(tester);
    installError = 'UPDATE_INSTALL';
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();
    expect(find.text('Установить'), findsOneWidget);
    expect(calls.where((method) => method == 'startDownload'), isEmpty);
  });
  testWidgets(
    'low install space retains the APK and allows an explicit retry',
    (tester) async {
      await open(tester);
      installError = 'UPDATE_SPACE';
      await tester.tap(find.text('Установить'));
      await tester.pumpAndSettle();
      expect(
        find.text('Недостаточно места для установки обновления.'),
        findsOneWidget,
      );
      expect(find.text('Установить'), findsOneWidget);
      expect(calls.where((method) => method == 'startDownload'), isEmpty);
      expect(calls.where((method) => method == 'cancelDownload'), isEmpty);
      installError = null;
      await tester.tap(find.text('Установить'));
      await tester.pumpAndSettle();
      expect(calls.where((method) => method == 'installUpdate'), hasLength(2));
      expect(calls.where((method) => method == 'startDownload'), isEmpty);
    },
  );
  testWidgets('low download space shows the cause and keeps download retry', (
    tester,
  ) async {
    state = {
      'state': 'failed',
      'message': 'Недостаточно места для скачивания обновления.',
    };
    await open(tester);
    expect(
      find.text('Недостаточно места для скачивания обновления.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Скачать и обновить'));
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'startDownload'), hasLength(1));
    expect(find.text('Установить'), findsOneWidget);
    expect(calls.where((method) => method == 'installUpdate'), isEmpty);
  });
  testWidgets('cancellation racing download completion clears ready state', (
    tester,
  ) async {
    state = {'state': 'running', 'received': 40, 'bytes': 100};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UpdateDialog(offer: offer)),
      ),
    );
    await tester.pump();
    await tester.pump();
    final cancel = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Отменить загрузку'),
        )
        .onPressed!;
    state = {'state': 'ready', 'received': 100, 'bytes': 100};
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Установить'), findsOneWidget);
    cancel(); // Tap from the previous frame, after the final polling result.
    await tester.pumpAndSettle();
    expect(find.text('Скачать и обновить'), findsOneWidget);
    expect(calls.where((method) => method == 'cancelDownload'), hasLength(1));
    expect(calls.where((method) => method == 'installUpdate'), isEmpty);
  });
}
