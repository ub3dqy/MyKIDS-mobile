import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/assistant_settings.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/task_photo_viewer.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Keep native screenshots on the same frame schedule as a running app,
  // including repaint requests while the coordinator inspects the screen.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'actual Android settings and chat photo keep their original owner',
    (tester) async {
      final emulator = await Process.run('/system/bin/getprop', [
        'ro.kernel.qemu',
      ]);
      expect(
        Platform.isAndroid && emulator.stdout.toString().trim() == '1',
        true,
      );
      expect(gameDesign.value?.id, 'islands');
      HttpOverrides.global = null;
      tzdata.initializeTimeZones();
      const endpoint = 'http://127.0.0.1:18803';
      final support = await getApplicationSupportDirectory();
      final repo = FamilyRepository();
      final background = BackgroundServices(repo);
      final transport = http.Client();

      Future<void> stage(String name) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        await File('${support.path}/mykids-quality107-stage.json')
            .writeAsString(jsonEncode({'stage': name}));
        final ack = File('${support.path}/mykids-quality107-continue-$name');
        final deadline = DateTime.now().add(const Duration(seconds: 90));
        while (!await ack.exists()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native coordinator timed out at $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await ack.delete();
      }

      Future<void> until(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Android did not reach its required state');
          }
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.pumpAndSettle();
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
        home: body,
      );
      Future<void> settings() async {
        await tester.pumpWidget(
          app(
            Scaffold(
              appBar: AppBar(title: const Text('Настройки семьи')),
              body: ListenableBuilder(
                listenable: repo,
                builder: (_, _) => SettingsScreen(
                  repository: repo,
                  background: background,
                  perform: (action) async {
                    await action();
                  },
                  onUpdates: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> login(String name) async {
        if (repo.signedIn) {
          await repo.logout(remote: false);
        }
        await repo.login(
          endpoint,
          'quality107-$name',
          'synthetic-native-settings-123',
        );
      }

      Future<Map<String, dynamic>> control(
        String path, {
        bool get = false,
      }) async {
        final response = get
            ? await transport.get(
                Uri.parse('$endpoint$path'),
                headers: {'X-MyKIDS-QA': 'quality107-loopback-only'},
              )
            : await transport.post(
                Uri.parse('$endpoint$path'),
                headers: {'X-MyKIDS-QA': 'quality107-loopback-only'},
              );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      try {
        await Workmanager().initialize(backgroundSync);
        await repo.initialize();
        await login('parent');
        await settings();
        await tap(find.text('Часовой пояс и тихие часы'));
        await stage('quiet-draft');
        repo.online = false;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        final save = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Сохранить'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(save.onPressed, isNull);
        expect(find.byType(Form), findsOneWidget);
        await stage('quiet-offline');
        repo.online = true;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        await tap(find.text('Сохранить'));
        await until(() => find.byType(FamilyForm).evaluate().isEmpty);
        expect(repo.snapshot!['family']['quiet_start'], '21:00:00');
        await settings();
        await tap(find.text('Часовой пояс и тихие часы'));
        await login('outside');
        await tester.pumpAndSettle();
        expect(find.byType(Form), findsNothing);
        expect(find.text('Сохранить'), findsNothing);
        await stage('quiet-access-invalid');

        await tester.pumpWidget(const SizedBox.shrink());
        await login('parent');
        await tester.pumpWidget(app(AssistantSettings(repository: repo)));
        await tester.pumpAndSettle();
        await tap(find.text('Добавить правило'));
        await tester.enterText(
          find.byKey(const ValueKey('field-title')),
          'Личное правило 107',
        );
        await tester.enterText(
          find.byKey(const ValueKey('field-keywords')),
          'регби, тренировка',
        );
        final note = find.byKey(const ValueKey('field-message'));
        await tester.ensureVisible(note);
        await tester.enterText(note, 'Возьми форму и воду.');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await stage('assistant-draft');
        await tap(find.text('Сохранить'));
        await until(() => find.byType(FamilyForm).evaluate().isEmpty);
        await tap(find.text('Личное правило 107'));
        await login('outside');
        await tester.pumpAndSettle();
        expect(find.byType(Form), findsNothing);
        await stage('assistant-access-invalid');

        await tester.pumpWidget(const SizedBox.shrink());
        await login('parent');
        await tester.pumpWidget(app(AssistantSettings(repository: repo)));
        await tester.pumpAndSettle();
        final card = find.ancestor(
          of: find.text('Личное правило 107'),
          matching: find.byType(ListTile),
        );
        await tap(find.descendant(of: card, matching: find.byType(IconButton)));
        await stage('assistant-delete-confirm');
        await control('/quality107/fault?mode=before');
        await tap(find.text('Удалить'));
        await until(
          () => find
              .textContaining('Удаление ожидает сверки')
              .evaluate()
              .isNotEmpty,
        );
        expect(await repo.pending(), hasLength(1));
        await stage('assistant-delete-queued');
        await control('/quality107/fault?mode=off');
        await repo.sync();
        await until(() => find.text('Личное правило 107').evaluate().isEmpty);
        expect(await repo.pending(), isEmpty);
        await stage('assistant-delete-complete');

        final room = repo
            .rows('rooms')
            .firstWhere((r) => r['kind'] == 'private');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 16, 16),
          Paint()..color = Colors.teal,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final source = File('${support.path}/synthetic-quality107.png');
        await source.writeAsBytes(bytes!.buffer.asUint8List());
        final upload = await repo.upload(
          source.path,
          'room',
          room['id'] as String,
        );
        await repo.mutate('/v1/rooms/${room['id']}/messages', {
          'attachment_id': upload['id'],
        });
        await source.delete();
        await tester.pumpWidget(app(ChatScreen(repository: repo, room: room)));
        await tester.pumpAndSettle();
        await tap(find.text('Открыть фото'));
        await until(() => find.byType(InteractiveViewer).evaluate().isNotEmpty);
        await stage('chat-photo-full');
        // The full-screen viewer has no scroll list; exercise its actual zoom control.
        await tester.tap(find.byTooltip('Увеличить'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          greaterThan(1),
        );
        await stage('chat-photo-zoomed');
        repo.online = false;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        await stage('chat-photo-offline');
        await tester.tap(find.byTooltip('Показать целиком'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value,
          Matrix4.identity(),
        );
        await stage('chat-photo-fit');
        repo.online = true;
        repo.notifyListeners();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        final covering = navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Другой открытый экран')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await login('outside');
        await tester.pumpAndSettle();
        expect(find.text('Другой открытый экран'), findsOneWidget);
        expect(find.byType(TaskPhotoViewer, skipOffstage: false), findsNothing);
        await stage('photo-cover-preserved');
        navigator.pop();
        await covering;
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
        await stage('photo-access-invalid');
        final stats = await control('/quality107/stats', get: true);
        final actions = stats['actions'] as List;
        expect(
          actions.where((r) => r['username'] == 'quality107-outside'),
          isEmpty,
        );
        expect(
          actions.where((r) => r['action'] == 'family.settings').single['n'],
          1,
        );
        expect(
          actions
              .where((r) => r['action'] == 'assistant.rule.saved')
              .single['n'],
          1,
        );
        expect(
          actions
              .where((r) => r['action'] == 'assistant.rule.deleted')
              .single['n'],
          1,
        );
        final keys = (stats['delete_keys'] as List).cast<String>();
        expect(keys.length, greaterThanOrEqualTo(2));
        expect(keys.toSet(), hasLength(1));
        await File('${support.path}/mykids-quality107-server-stats.json')
            .writeAsString(jsonEncode(stats));
        await File('${support.path}/mykids-quality107-proof.json')
            .writeAsString(
              jsonEncode({
                'quiet_save_and_offline_draft': true,
                'old_quiet_form_hidden': true,
                'assistant_saved_and_masked': true,
                'uncertain_delete_single_command': true,
                'chat_full_screen_zoom_and_offline': true,
                'photo_owner_masking': true,
                'covering_route_preserved': true,
                'no_cross_family_write': true,
                'physical_phone': false,
              }),
            );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await repo.logout(remote: false);
        await repo.db?.close();
        background.dispose();
        repo.client.close();
        transport.close();
        repo.dispose();
      }
    },
  );
}
