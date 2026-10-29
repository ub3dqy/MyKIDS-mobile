import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/form_layout.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/visuals.dart';

import 'calendar_test.dart' as calendar;
import 'support/messenger_fixture.dart';

class SettingsFixture extends ContactsFixture {
  final changes = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    changes.add(body);
    return {'ok': true};
  }
}

Future<void> mountFields(
  WidgetTester tester,
  Widget screen, {
  bool child = false,
  double scale = 2,
  Size? screenSize = const Size(320, 800),
}) async {
  if (screenSize != null) {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1;
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: familyTheme(child),
      locale: const Locale('ru'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru')],
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: widget!,
      ),
      home: screen,
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> revealField(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pump(const Duration(milliseconds: 200));
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pump(const Duration(milliseconds: 200));
}

void labelFits(WidgetTester tester, Finder input, String label) {
  final group = find
      .ancestor(of: input, matching: find.byType(LabeledInput))
      .first;
  final caption = find.descendant(of: group, matching: find.text(label));
  final labelBox = tester.getRect(caption);
  final inputBox = tester.getRect(input);
  final groupBox = tester.getRect(group);
  expect(labelBox.bottom, lessThanOrEqualTo(inputBox.top - 6));
  expect(labelBox.left, greaterThanOrEqualTo(groupBox.left));
  expect(labelBox.right, lessThanOrEqualTo(groupBox.right));
  expect(tester.takeException(), isNull);
}

void main() {
  tearDown(() async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('input labels remain available to screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = FamilyRepository()..variant = 'parent';
    addTearDown(() {
      repo.client.close();
      repo.dispose();
    });
    await mountFields(
      tester,
      LoginScreen(
        repository: repo,
        onLogin: () async {},
        onUpdates: () async {},
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final input = find.byKey(const ValueKey('login-username'));
    await revealField(tester, input);
    expect(
      tester.getSemantics(input).getSemanticsData().label,
      contains('Логин'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets(
    'task comment and dialog actions remain usable above a keyboard',
    (tester) async {
      final repo = MessengerFixture();
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      repo.snapshot!['tasks'] = [
        {
          'id': 'synthetic-task',
          'title': 'Собрать школьный рюкзак',
          'description': 'Проверить всё по списку',
          'note': '',
          'status': 'assigned',
          'due_at': '2026-10-13T16:00:00Z',
          'reward': 10,
          'penalty': 0,
          'financial_approved': 1,
          'require_photo': 0,
          'version': 1,
          'author_id': 'parent',
        },
      ];
      await mountFields(
        tester,
        Scaffold(
          body: TaskScreen(
            repository: repo,
            perform: (action) async {
              throw StateError('This layout test must not submit a task');
            },
          ),
        ),
        child: true,
      );
      await revealField(tester, find.text('Собрать школьный рюкзак'));
      await tester.tap(find.text('Собрать школьный рюкзак'));
      await tester.pump(const Duration(milliseconds: 300));
      await revealField(tester, find.text('Готово — отправить на проверку'));
      await tester.tap(find.text('Готово — отправить на проверку'));
      await tester.pump(const Duration(milliseconds: 300));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pump(const Duration(milliseconds: 200));
      final comment = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await Scrollable.ensureVisible(tester.element(comment), alignment: .5);
      await tester.enterText(
        comment,
        'Искусственный длинный комментарий для проверки поля',
      );
      await tester.pump();
      labelFits(tester, comment, 'Комментарий');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final role in ['child', 'parent', 'relative']) {
    testWidgets(
      'invitation fields remain separate with long input and large text: $role',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FamilyRepository()..variant = role;
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        await mountFields(
          tester,
          LoginScreen(
            repository: repo,
            onLogin: () async {},
            onUpdates: () async {},
          ),
          child: role == 'child',
        );
        await revealField(tester, find.text('У меня есть приглашение'));
        await tester.tap(find.text('У меня есть приглашение'));
        await tester.pump(const Duration(milliseconds: 200));
        Rect? previous;
        for (final field in {
          'invite': 'Приглашение от родителя',
          'name': 'Ваше имя',
          'username': 'Логин',
          'password': 'Пароль',
        }.entries) {
          final input = find.byKey(ValueKey('login-${field.key}'));
          await revealField(tester, input);
          await tester.enterText(
            input,
            field.key == 'invite'
                ? List.filled(43, 'A').join()
                : 'Искусственный длинный текст для проверки',
          );
          await tester.pump();
          labelFits(tester, input, field.value);
          final group = find
              .ancestor(of: input, matching: find.byType(LabeledInput))
              .first;
          final scroll = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          final box = tester
              .getRect(group)
              .shift(Offset(0, scroll.position.pixels));
          if (previous != null) {
            expect(box.top - previous.bottom, greaterThanOrEqualTo(15));
          }
          previous = box;
        }
        final password = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('login-password')),
            matching: find.byType(TextField),
          ),
        );
        expect(password.obscureText, true);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'shared task, school and money form wraps choice values and validation errors',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountFields(
        tester,
        const FamilyForm(
          title: 'Семейная форма',
          fields: [
            FamilyField(
              'owner',
              'Ответственный участник семьи с длинным именем',
              kind: 'choice',
              initial: 'relative',
              choices: {
                'relative': 'Бабушка Александра Константиновна',
                'parent': 'Родитель',
              },
            ),
            FamilyField(
              'amount',
              'Количество монет за выполнение задания',
              kind: 'int',
            ),
            FamilyField(
              'note',
              'Что нужно сделать и на что обратить внимание',
              kind: 'note',
              required: false,
            ),
          ],
        ),
      );
      final choice = find.byKey(const ValueKey('field-owner'));
      labelFits(
        tester,
        choice,
        'Ответственный участник семьи с длинным именем',
      );
      final selected = find
          .descendant(
            of: choice,
            matching: find.text('Бабушка Александра Константиновна'),
          )
          .first;
      expect(
        tester.getRect(selected).bottom,
        lessThanOrEqualTo(tester.getRect(choice).bottom),
      );
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Родитель').last);
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('field-amount'));
      await revealField(tester, amount);
      await tester.enterText(amount, 'abc');
      await revealField(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      await revealField(tester, amount);
      expect(find.text('Введите целое число'), findsOneWidget);
      labelFits(tester, amount, 'Количество монет за выполнение задания');
      await revealField(tester, find.byKey(const ValueKey('field-note')));
      labelFits(
        tester,
        find.byKey(const ValueKey('field-note')),
        'Что нужно сделать и на что обратить внимание',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings buttons have gaps and the timezone form remains usable',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = SettingsFixture();
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      await mountFields(
        tester,
        Scaffold(
          body: SettingsScreen(
            repository: repo,
            background: BackgroundServices(repo),
            onUpdates: () async {},
            perform: (action) async {
              await action();
            },
          ),
        ),
      );
      Rect? previous;
      for (final name in [
        'Включить уведомления',
        'Настройки уведомлений телефона',
        'Настройки работы в фоне',
        'Показ входящих звонков на экране',
      ]) {
        await revealField(tester, find.text(name));
        final button = find
            .ancestor(
              of: find.text(name),
              matching: find.byType(OutlinedButton),
            )
            .first;
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final box = tester
            .getRect(button)
            .shift(Offset(0, scroll.position.pixels));
        final textBox = tester.getRect(find.text(name));
        expect(textBox.height, lessThan(box.height));
        if (previous != null) {
          expect(box.top - previous.bottom, greaterThanOrEqualTo(15));
        }
        previous = box;
        expect(tester.takeException(), isNull);
      }
      await revealField(tester, find.text('Часовой пояс и тихие часы'));
      await tester.tap(find.text('Часовой пояс и тихие часы'));
      await tester.pumpAndSettle();
      final zone = find.byKey(const ValueKey('field-timezone'));
      labelFits(tester, zone, 'Часовой пояс');
      await tester.tap(zone);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Екатеринбург').last);
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.changes.single['timezone'], 'Asia/Yekaterinburg');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'simple calendar fields and missing activity times fit at 320px',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = calendar.snapshot([]);
      await mountFields(
        tester,
        CalendarEditor(
          snapshot: data,
          day: familyClock(data, DateTime.utc(2026, 10, 12, 12)),
          initial: calendar.event('Школа', '09:00', '14:00'),
        ),
      );
      final title = find.byKey(const ValueKey('event-title'));
      labelFits(tester, title, 'Название');
      final note = find.byKey(const ValueKey('event-note'));
      await revealField(tester, note);
      labelFits(tester, note, 'Примечание');
      await revealField(tester, find.text('Добавить занятие'));
      await tester.tap(find.text('Добавить занятие'));
      await tester.pump();
      final activity = find.byKey(const ValueKey('activity-title-0'));
      await revealField(tester, activity);
      labelFits(tester, activity, 'Название занятия');
      await tester.enterText(
        activity,
        'Изобразительное искусство и художественный труд',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await revealField(tester, find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(
        find.text('У каждого занятия выберите начало и окончание'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
