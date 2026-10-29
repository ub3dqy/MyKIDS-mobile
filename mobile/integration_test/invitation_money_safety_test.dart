import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/invitation.dart';
import 'package:mykids_family/invitation_dialog.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/visuals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('native invitations and money retain the initiating family', (
    tester,
  ) async {
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
    final transport = http.Client();
    final invitationMounted = ValueNotifier(true);
    final decoder = MobileScannerController(autoStart: false);
    Future<void> perform(Future<Map<String, dynamic>> Function() action) async {
      try {
        await action();
      } on ApiFailure catch (error) {
        if (error.status != 409) rethrow;
      }
    }

    Future<void> stage(String name) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await File('${support.path}/mykids-quality108-stage.json')
          .writeAsString(jsonEncode({'stage': name}));
      final ack = File('${support.path}/mykids-quality108-continue-$name');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!await ack.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Coordinator timed out: $name');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await ack.delete();
    }

    Future<void> until(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Required native state absent');
        }
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder target) async {
      if (find.byType(Scrollable).evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          target,
          240,
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
      home: Scaffold(
        appBar: AppBar(title: const Text('MyKIDS')),
        body: body,
      ),
    );
    Future<void> login(String name) async {
      if (repo.signedIn) await repo.logout(remote: false);
      await repo.login(
        endpoint,
        'quality108-$name',
        'synthetic-native-invitation-123',
      );
    }

    Future<void> invitations() async {
      invitationMounted.value = true;
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<bool>(
            valueListenable: invitationMounted,
            builder: (_, shown, _) => shown
                ? FamilyInvitations(repository: repo, perform: perform)
                : const Center(child: Text('Раздел закрыт')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> money() async {
      await tester.pumpWidget(
        app(
          ListenableBuilder(
            listenable: repo,
          builder: (_, _) => repo.signedIn && repo.snapshot != null
              ? MoneyScreen(repository: repo, perform: perform)
              : const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    VoidCallback callback(String label) => tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          ),
        )
        .onPressed!;
    Future<Map<String, dynamic>> stats() async {
      final response = await transport.get(
        Uri.parse('$endpoint/quality108/stats'),
        headers: {'X-MyKIDS-QA': 'quality108-loopback-only'},
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    int writes(Map<String, dynamic> data, String prefix) =>
        (data['writes'] as List)
            .where((row) => (row['path'] as String).startsWith(prefix))
            .length;
    try {
      await Workmanager().initialize(backgroundSync);
      await repo.initialize();
      await login('parent');
      await invitations();
      await tap(find.text('Подключить бабушку или дедушку'));
      await until(() => find.byType(InvitationDialog).evaluate().isNotEmpty);
      final invitation = tester
          .widget<InvitationDialog>(find.byType(InvitationDialog))
          .invitation;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('invitation-qr')),
      );
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final qrFile = File('${support.path}/quality108-rendered-qr.png');
      await qrFile.writeAsBytes(bytes!.buffer.asUint8List());
      final capture = await decoder.analyzeImage(
        qrFile.path,
        formats: const [BarcodeFormat.qrCode],
      );
      expect(capture, isNotNull);
      expect(
        Invitation.parse(
          capture!.barcodes.single.rawValue!,
          expectedRole: 'relative',
        ).token,
        invitation.token,
      );
      final oldCopy = callback('Скопировать');
      final oldClose = callback('Закрыть');
      await tap(find.text('Скопировать'));
      expect((await Clipboard.getData('text/plain'))?.text, invitation.token);
      await stage('invite-open');
      final navigator = Navigator.of(
        tester.element(find.byType(InvitationDialog)),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Важный экран'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr, skipOffstage: false), findsNothing);
      await Clipboard.setData(const ClipboardData(text: 'quality108-sentinel'));
      oldCopy();
      oldClose();
      await tester.pumpAndSettle();
      expect(find.text('Важный экран'), findsOneWidget);
      expect(
        (await Clipboard.getData('text/plain'))?.text,
        'quality108-sentinel',
      );
      await stage('invite-covered');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr), findsOneWidget);
      invitationMounted.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr, skipOffstage: false), findsNothing);
      expect(find.text('Приглашение недоступно'), findsOneWidget);
      await stage('invite-source-removed');
      await tap(find.text('Закрыть'));
      await until(() => find.byType(InvitationDialog).evaluate().isEmpty);
      await invitations();
      await tap(find.text('Подключить бабушку или дедушку'));
      await until(() => find.byType(InvitationDialog).evaluate().isNotEmpty);
      final accountCopy = callback('Скопировать');
      await login('outside');
      await tester.pumpAndSettle();
      accountCopy();
      await tester.pumpAndSettle();
      expect(find.byType(InvitationQr, skipOffstage: false), findsNothing);
      expect(
        (await Clipboard.getData('text/plain'))?.text,
        'quality108-sentinel',
      );
      await stage('invite-account-invalid');
      await tap(find.text('Закрыть'));
      await until(() => find.byType(InvitationDialog).evaluate().isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await login('child');
      await money();
      await tap(find.text('Велосипед · 100 монет'));
      await tap(find.text('Копить на это'));
      await until(() => repo.snapshot?['goal']?['reward_id'] != null);
      await stage('goal-chosen');
      await tap(find.text('Велосипед · 100 монет'));
      await tap(find.text('Самокат · 150 монет'));
      await tester.scrollUntilVisible(
        find.text('Копить на это'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      final oldGoal = callback('Копить на это');
      final moneyNavigator = Navigator.of(
        tester.element(find.byType(MoneyScreen)),
      );
      moneyNavigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Важный экран'))),
        ),
      );
      await tester.pumpAndSettle();
      final beforeCover = writes(await stats(), '/v1/goal');
      oldGoal();
      await tester.pumpAndSettle();
      expect(writes(await stats(), '/v1/goal'), beforeCover);
      expect(find.text('Важный экран'), findsOneWidget);
      await stage('money-covered');
      moneyNavigator.pop();
      await tester.pumpAndSettle();
      await login('outside-child');
      oldGoal();
      await tester.pumpAndSettle();
      expect(writes(await stats(), '/v1/goal'), beforeCover);
      await tester.pumpWidget(const SizedBox.shrink());
      await money();
      await tap(find.text('Велосипед · 100 монет'));
      await tap(find.text('Копить на это'));
      await until(() => repo.snapshot?['goal']?['reward_id'] != null);
      expect(writes(await stats(), '/v1/goal'), beforeCover + 1);
      await stage('goal-old-action-blocked');
      await tester.pumpWidget(const SizedBox.shrink());
      await login('parent');
      await money();
      await tester.scrollUntilVisible(
        find.text('Отменить'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      final oldWaive = callback('Отменить');
      await tap(find.text('Отменить'));
      await until(
        () => repo.rows('penalties').every((row) => row['status'] != 'pending'),
      );
      expect(writes(await stats(), '/v1/penalties/'), 1);
      await stage('penalty-waived');
      await login('outside');
      oldWaive();
      await tester.pumpAndSettle();
      final finalStats = await stats();
      expect(writes(finalStats, '/v1/penalties/'), 1);
      expect(writes(finalStats, '/v1/goal'), 2);
      expect(writes(finalStats, '/v1/invites'), 2);
      expect(
        (finalStats['writes'] as List).every((row) => row['status'] == 200),
        true,
      );
      await File('${support.path}/mykids-quality108-server-stats.json')
          .writeAsString(jsonEncode(finalStats));
      await File('${support.path}/mykids-quality108-proof.json').writeAsString(
        jsonEncode({
          'qr_decoded_from_actual_rendering': true,
          'actual_sensitive_copy': true,
          'invitation_source_disposal_masks_secret': true,
          'invitation_account_change_masks_secret': true,
          'covering_route_preserved': true,
          'old_money_actions_send_no_request': true,
          'fresh_goal_and_waiver_work': true,
          'no_cross_family_write': true,
          'physical_phone': false,
        }),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await decoder.dispose();
      invitationMounted.dispose();
      await repo.logout(remote: false);
      await repo.db?.close();
      transport.close();
      repo.client.close();
      repo.dispose();
    }
  });
}
