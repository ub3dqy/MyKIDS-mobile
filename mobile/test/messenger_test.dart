import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/call_view.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/messenger_widgets.dart';
import 'package:mykids_family/visuals.dart';

import 'support/messenger_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          null,
        );
  });

  for (final role in ['child', 'parent', 'relative']) {
    testWidgets(
      'conversation list and calls remain readable at 320px with large text: $role',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = MessengerFixture(role: role);
        await tester.pumpWidget(
          MaterialApp(
            theme: familyTheme(role == 'child'),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: FamilyScreen(
                  repository: repo,
                  perform: (action) async {
                    await action();
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.text('Папа: Отлично. Скоро увидимся!'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 3')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Звонки'));
        await tester.tap(find.text('Звонки'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Входящий'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      },
    );
  }

  testWidgets(
    'chat retains failed draft, sends once, loads history and records a read receipt',
    (tester) async {
      final repo = MessengerFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: familyTheme(true),
          home: ChatScreen(
            repository: repo,
            room: repo.rows('rooms').firstWhere((r) => r['kind'] == 'private'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MessageBubble), findsNWidgets(4));
      expect(find.byTooltip('Аудиозвонок'), findsOneWidget);
      expect(find.byTooltip('Видеозвонок'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      expect(find.byTooltip('Отправить'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Новое сообщение');
      await tester.pump();
      repo.failSend = true;
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось отправить. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Новое сообщение',
      );
      repo.failSend = false;
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      expect(repo.sent, ['Новое сообщение']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.ensureVisible(find.byKey(const ValueKey<dynamic>('later')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        repo.history.any(
          (m) => (m['receipts'] as List).any(
            (r) => r['user_id'] == repo.userId && r['read_at'] != null,
          ),
        ),
        true,
      );
      await tester.scrollUntilVisible(
        find.text('Более ранние сообщения'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Более ранние сообщения'));
      await tester.pumpAndSettle();
      expect(repo.earlierLoaded, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      repo.client.close();
      repo.dispose();
    },
  );

  for (final group in [false, true]) {
    testWidgets(
      'call ${group ? 'group' : 'individual'} supports small screen, large text and hangup',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var ended = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: FamilyCallView(
                title: 'Очень длинное имя семейного разговора',
                status: 'Соединение установлено',
                people: [
                  const CallPerson(name: 'Папа', local: true),
                  if (group) ...[
                    const CallPerson(name: 'Мама'),
                    const CallPerson(name: 'Бабушка'),
                    const CallPerson(name: 'Стёпа'),
                  ],
                ],
                controls: [
                  CallControl(
                    label: 'Микрофон',
                    icon: Icons.mic,
                    onPressed: () {},
                  ),
                  CallControl(
                    label: 'Сменить камеру',
                    icon: Icons.cameraswitch,
                    onPressed: () {},
                  ),
                  CallControl(
                    label: 'Камера',
                    icon: Icons.videocam,
                    onPressed: () {},
                  ),
                  CallControl(
                    label: 'Динамик',
                    icon: Icons.volume_up,
                    onPressed: () {},
                  ),
                  CallControl(
                    label: 'Bluetooth',
                    icon: Icons.bluetooth,
                    onPressed: () {},
                  ),
                  CallControl(
                    label: 'Пригласить',
                    icon: Icons.person_add,
                    onPressed: () {},
                  ),
                ],
                onClose: () => ended = true,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Завершить'));
        await tester.tap(find.text('Завершить'));
        expect(ended, true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final height in [640.0, 800.0]) {
    testWidgets(
      'chat remains usable with large text, a multiline draft, keyboard and send error: $height',
      (tester) async {
        tester.view.physicalSize = Size(320, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = MessengerFixture();
        await tester.pumpWidget(
          MaterialApp(
            theme: familyTheme(true),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, height),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 300),
              ),
              child: ChatScreen(
                repository: repo,
                room: repo
                    .rows('rooms')
                    .firstWhere((r) => r['kind'] == 'private'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Длинное сообщение для семейного чата ' * 112,
        );
        await tester.pump();
        repo.failSend = true;
        await tester.tap(find.byTooltip('Отправить'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isNotEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        repo.client.close();
        repo.dispose();
      },
    );
  }
}
