import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/task_photo_viewer.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

class AccessWire extends http.BaseClient {
  final inner = http.Client();
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('Synthetic connection loss');
    request.persistentConnection = false;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'owned Android checks family permissions and photo route ownership',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      HttpOverrides.global = null;
      tzdata.initializeTimeZones();
      const endpoint = 'http://127.0.0.1:18806';
      final support = await getApplicationSupportDirectory();
      final wire = AccessWire();
      final repo = FamilyRepository(client: wire);
      final background = BackgroundServices(repo);
      final control = http.Client();
      final errors = <ApiFailure>[];
      var actionsInFlight = 0;
      Completer<void>? beforeSend;
      double? scaleOverride;

      Future<void> until(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Expected native state absent');
          }
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.pumpAndSettle();
      }

      Future<void> stage(String name) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await File('${support.path}/mykids-quality117-stage.json')
            .writeAsString(jsonEncode({'stage': name}));
        final ack = File('${support.path}/mykids-quality117-continue-$name');
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Capture timed out at $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        await ack.delete();
      }

      Future<void> tap(Finder target) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            target,
            230,
            maxScrolls: 60,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target.hitTestable());
        await tester.pumpAndSettle();
      }

      Widget app(Widget body) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: familyTheme(false),
        builder: (context, child) => scaleOverride == null
            ? child!
            : MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scaleOverride)),
                child: child!,
              ),
        home: body,
      );
      Future<void> mount(Widget body) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(app(body));
        await tester.pumpAndSettle();
      }

      Future<void> perform(
        Future<Map<String, dynamic>> Function() action,
      ) async {
        actionsInFlight++;
        try {
          await beforeSend?.future;
          await action();
        } on ApiFailure catch (error) {
          if (error.status != 409) rethrow;
          errors.add(error);
        } finally {
          actionsInFlight--;
        }
      }

      Future<void> settings() => mount(
        Scaffold(
          appBar: AppBar(title: const Text('Настройки семьи')),
          body: ListenableBuilder(
            listenable: repo,
            builder: (_, _) => SettingsScreen(
              repository: repo,
              background: background,
              perform: perform,
              onUpdates: () async {},
            ),
          ),
        ),
      );
      Future<void> login(String name) async {
        if (repo.signedIn) await repo.logout(remote: false);
        await repo.login(
          endpoint,
          'quality117-$name',
          'synthetic-native-access-123',
        );
      }

      Map<String, dynamic> relative() => repo
          .rows('members')
          .singleWhere((member) => member['role'] == 'relative');
      Finder permission() => find.ancestor(
        of: find.text('Смотреть свои задания'),
        matching: find.byType(SwitchListTile),
      );
      Future<void> expandRelative() async {
        await tap(find.text(relative()['name'] as String));
        await tester.ensureVisible(find.text('Смотреть свои задания'));
        await tester.pumpAndSettle();
      }

      Future<Map<String, dynamic>> stats() async {
        final response = await control.get(
          Uri.parse('$endpoint/quality117/stats'),
          headers: {'X-MyKIDS-QA': 'quality117-loopback-only'},
        );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      Future<void> gallery(List<Future<File> Function()> photos) async {
        await mount(
          Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Семейные фотографии')),
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    final viewer = TaskPhotoViewer(
                      repository: repo,
                      photos: photos,
                    );
                    Navigator.of(context)
                        .push<void>(MaterialPageRoute(builder: (_) => viewer));
                  },
                  child: const Text('Открыть фотографии'),
                ),
              ),
            ),
          ),
        );
        await tap(find.text('Открыть фотографии'));
        await tester.pump(const Duration(milliseconds: 400));
      }

      Finder photoButton(String tooltip) => find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      );
      TransformationController transform() => tester
          .widget<InteractiveViewer>(
            find.byKey(const ValueKey('task-photo-zoom')),
          )
          .transformationController!;

      try {
        await Workmanager().initialize(backgroundSync);
        await repo.initialize();
        await login('parent');
        await settings();
        await expandRelative();
        final stale = tester.widget<SwitchListTile>(permission()).onChanged!;
        await tap(find.text('Смотреть свои задания'));
        await until(() => actionsInFlight == 0 && !repo.syncing);
        expect(relative()['view_tasks'], 0);
        expect(relative()['create_tasks'], 1);
        expect(relative()['review_tasks'], 1);
        expect(relative()['active'], 1);
        await stage('permissions-current');
        stale(true);
        await tester.pumpAndSettle();
        expect((await stats())['writes'], hasLength(1));
        await login('outside-parent');
        await tester.pumpAndSettle();
        stale(true);
        await tester.pumpAndSettle();
        expect((await stats())['writes'], hasLength(1));
        expect(relative()['view_tasks'], 1);
        await stage('permissions-stale-owner');

        await login('parent');
        await settings();
        await expandRelative();
        wire.offline = true;
        repo.online = false;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(permission()).onChanged, isNull);
        expect(find.textContaining('Подключитесь к интернету'), findsWidgets);
        await stage('permissions-offline');
        wire.offline = false;
        await repo.sync();
        await tester.pumpAndSettle();
        await tap(find.text('Смотреть свои задания'));
        await until(() => actionsInFlight == 0 && !repo.syncing);
        expect(relative()['view_tasks'], 1);
        await stage('permissions-reconnected');
        beforeSend = Completer<void>();
        tester.widget<SwitchListTile>(permission()).onChanged!(false);
        await tester.pump();
        await login('outside-parent');
        beforeSend.complete();
        await until(() => errors.isNotEmpty && actionsInFlight == 0);
        expect((await stats())['writes'], hasLength(2));
        await stage('permissions-deferred-blocked');
        beforeSend = null;

        await login('parent');
        for (final design in GameDesign.all) {
          gameDesign.value = design;
          await settings();
          await expandRelative();
          expect(
            MediaQuery.textScalerOf(tester.element(permission())).scale(14),
            greaterThanOrEqualTo(20),
          );
          await stage('permissions-style-${design.id}');
        }
        await settings();
        await tap(find.text('Часовой пояс и тихие часы'));
        expect(find.byType(FamilyForm), findsOneWidget);
        await stage('settings-quiet-form');
        await tester.tap(find.byTooltip('Назад'));
        await tester.pumpAndSettle();

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 64, 64),
          Paint()..color = Colors.teal,
        );
        canvas.drawCircle(
          const Offset(32, 32),
          18,
          Paint()..color = Colors.amber,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(64, 64);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('${support.path}/quality117-photo.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        final room = repo
            .rows('rooms')
            .firstWhere((r) => r['kind'] == 'private');
        final first = await repo.upload(
          file.path,
          'room',
          room['id'] as String,
        );
        final second = await repo.upload(
          file.path,
          'room',
          room['id'] as String,
        );
        final photos = <Future<File> Function()>[
          () => repo.attachment(first['id'] as String),
          () => repo.attachment(second['id'] as String),
        ];
        await gallery(photos);
        await until(() => find.byType(InteractiveViewer).evaluate().isNotEmpty);
        await stage('photo-first');
        final center = tester.getCenter(find.byType(InteractiveViewer));
        final fingerOne = await tester.createGesture(pointer: 81);
        final fingerTwo = await tester.createGesture(pointer: 82);
        await fingerOne.down(center - const Offset(40, 0));
        await fingerTwo.down(center + const Offset(40, 0));
        await tester.pump();
        await fingerOne.moveTo(center - const Offset(90, 0));
        await fingerTwo.moveTo(center + const Offset(90, 0));
        await tester.pump();
        await fingerOne.moveTo(center - const Offset(130, 0));
        await fingerTwo.moveTo(center + const Offset(130, 0));
        await tester.pump();
        await fingerOne.up();
        await fingerTwo.up();
        await tester.pumpAndSettle();
        expect(transform().value.getMaxScaleOnAxis(), greaterThan(1.4));
        await tap(find.byTooltip('Увеличить'));
        expect(transform().value.getMaxScaleOnAxis(), greaterThan(1));
        await stage('photo-zoom');
        await tap(find.byTooltip('Следующее фото'));
        await until(
          () =>
              find.text('Фото 2 из 2').evaluate().isNotEmpty &&
              find.byType(InteractiveViewer).evaluate().isNotEmpty,
        );
        expect(transform().value, Matrix4.identity());
        await stage('photo-second');
        final close = tester
            .widget<IconButton>(photoButton('Закрыть фотографию'))
            .onPressed!;
        final previous = tester
            .widget<IconButton>(photoButton('Предыдущее фото'))
            .onPressed!;
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Экран поверх фотографии')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        close();
        previous();
        await tester.pumpAndSettle();
        expect(find.text('Экран поверх фотографии'), findsOneWidget);
        await stage('photo-cover-preserved');
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('Фото 2 из 2'), findsOneWidget);
        await tap(find.byTooltip('Показать целиком'));
        expect(transform().value, Matrix4.identity());
        await stage('photo-fit');
        await tap(find.byTooltip('Закрыть фотографию'));
        close();
        previous();
        await tester.pumpAndSettle();
        expect(find.text('Открыть фотографии'), findsOneWidget);

        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        await until(
          () =>
              tester.view.physicalSize.width > tester.view.physicalSize.height,
        );
        scaleOverride = 2;
        var failDownload = true, retries = 0;
        await gallery([
          () async {
            retries++;
            if (failDownload) {
              throw const SocketException('Synthetic photo download failure');
            }
            return repo.attachment(first['id'] as String);
          },
        ]);
        await until(
          () =>
              find.text('Не удалось открыть фотографию').evaluate().isNotEmpty,
        );
        await stage('photo-error-landscape');
        failDownload = false;
        await tap(find.text('Повторить'));
        await until(() => find.byType(InteractiveViewer).evaluate().isNotEmpty);
        expect(retries, 2);
        await stage('photo-retry-landscape');
        await tap(find.byTooltip('Закрыть фотографию'));
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await until(
          () =>
              tester.view.physicalSize.height > tester.view.physicalSize.width,
        );
        scaleOverride = null;
        await gallery(photos);
        await until(() => find.byType(InteractiveViewer).evaluate().isNotEmpty);
        await login('outside-parent');
        await until(
          () => find
              .byType(TaskPhotoViewer, skipOffstage: false)
              .evaluate()
              .isEmpty,
        );
        expect(
          find.byType(InteractiveViewer, skipOffstage: false),
          findsNothing,
        );
        await stage('photo-owner-invalid');
        final finalStats = await stats();
        expect(finalStats['writes'], hasLength(2));
        for (final row in finalStats['writes'] as List) {
          expect(row['status'], 200);
          expect((row['body'] as Map).keys.toSet(), {
            'view_tasks',
            'expected_revision',
          });
        }
        expect(finalStats['ledger_rows'], 0);
        expect(finalStats['real_families'], false);
        expect(tester.takeException(), isNull);
        await File('${support.path}/mykids-quality117-server-stats.json')
            .writeAsString(jsonEncode(finalStats));
        await File('${support.path}/mykids-quality117-proof.json')
            .writeAsString(
              jsonEncode({
                'passed': true,
                'physical_phone': false,
                'current_relative_permission_update': true,
                'stale_permission_callbacks_blocked': true,
                'offline_permissions_disabled_and_recovered': true,
                'deferred_permission_action_rechecked': true,
                'photo_zoom_and_pages': true,
                'photo_controls_owner_current_route_only': true,
                'photo_retry_short_landscape': true,
                'five_styles_large_text': true,
                'owner_change_masks_photo': true,
              }),
            );
      } finally {
        if (beforeSend?.isCompleted == false) beforeSend!.complete();
        await until(() => actionsInFlight == 0 && !repo.syncing);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await tester.pumpWidget(const SizedBox.shrink());
        background.dispose();
        control.close();
        repo.client.close();
        repo.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
