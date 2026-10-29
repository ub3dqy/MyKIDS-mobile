import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mykids_family/assistant_rules.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/calendar.dart';
import 'package:mykids_family/call_view.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';

import 'calendar_test.dart' as fixture;

void main() {
  testWidgets(
    'native call identity is refreshed when the cached user becomes available',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final mirrored = <Map<dynamic, dynamic>>[];
      messenger.setMockMethodCallHandler(nativeCalls, (call) async {
        if (call.method == 'identity') mirrored.add(call.arguments as Map);
        return null;
      });
      final repo = FamilyRepository()..token = 'synthetic-session';
      final background = BackgroundServices(repo);
      background.identityChanged();
      await tester.pump();
      repo.snapshot = {
        'user': {'id': 'a' * 32, 'role': 'child'},
      };
      background.identityChanged();
      await tester.pump();
      expect(mirrored.length, 2);
      expect(mirrored.last['user'], 'a' * 32);
      expect(mirrored.last['session'], repo.sessionTag);
      expect(mirrored.last.values, isNot(contains(repo.token)));
      messenger.setMockMethodCallHandler(nativeCalls, null);
      repo.client.close();
      repo.dispose();
    },
  );
  test(
    'helper reads nested lessons, reminders are 45 minutes before each target',
    () {
      final data = fixture.snapshot([
        {
          ...fixture.event('Школа', '09:00', '14:00'),
          'activities': jsonEncode([
            {
              'id': 'pe',
              'title': 'ФИЗИЧЕСКАЯ КУЛЬТУРА',
              'start': '11:00',
              'end': '12:00',
            },
          ]),
        },
        fixture.event('Музыкальная школа', '17:00', '18:00'),
        fixture.event('Регби', '19:00', '20:00'),
      ])..['user'] = {'role': 'child'};
      final day = DateTime(2026, 10, 12);
      expect(assistantHints(data, day).map((hint) => hint.title), [
        'ФИЗИЧЕСКАЯ КУЛЬТУРА',
        'Музыкальная школа',
        'Регби',
      ]);
      final reminders = calendarReminders(
        data,
        DateTime.utc(2026, 10, 12, 4),
      ).where((item) => item.key.startsWith('assistant:')).toList();
      expect(reminders.map((item) => clockText(item.at)), [
        '10:15',
        '16:15',
        '18:15',
      ]);
      expect(reminders.first.body, contains('форму'));
      expect(reminders.first.body, contains('спортивную обувь'));
      expect(reminders.last.body, contains('воды'));
      data['user'] = {'role': 'parent'};
      expect(
        calendarReminders(
          data,
          DateTime.utc(2026, 10, 12, 4),
        ).where((item) => item.key.startsWith('assistant:')),
        isEmpty,
      );
      data['assistant_rules'] = <Map<String, dynamic>>[];
      expect(assistantHints(data, day), isEmpty);
    },
  );

  test(
    'helper honors calendar cancellation and edited rule text and lead time',
    () {
      final data = fixture.snapshot([fixture.event('Регби', '19:00', '20:00')])
        ..['user'] = {'role': 'child'}
        ..['assistant_rules'] = [
          {
            ...defaultAssistantRules.last,
            'message': 'Мяч и вода',
            'minutes_before': 60,
          },
        ];
      final reminders = calendarReminders(
        data,
        DateTime.utc(2026, 10, 12, 4),
      ).where((item) => item.key.startsWith('assistant:'));
      expect(clockText(reminders.single.at), '18:00');
      expect(reminders.single.body, contains('Мяч и вода'));
      data['schedule_exceptions'] = [
        {'schedule_id': 'Регби', 'date': '2026-10-12', 'replacement': null},
      ];
      expect(assistantHints(data, DateTime(2026, 10, 12)), isEmpty);
    },
  );

  testWidgets(
    'short parent password is explained and receives focus without submitting',
    (tester) async {
      var attempts = 0;
      final repo = FamilyRepository(
        client: MockClient((request) async {
          attempts++;
          throw StateError('Should not submit invalid input');
        }),
      )..variant = 'parent';
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            repository: repo,
            onLogin: () async {},
            onUpdates: () async {},
          ),
        ),
      );
      await tester.tap(find.text('У меня есть приглашение'));
      await tester.pumpAndSettle();
      for (final entry in {
        'login-invite': 'valid-invitation',
        'login-name': 'Мама',
        'login-username': 'mama',
        'login-password': 'short',
      }.entries) {
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      await tester.ensureVisible(find.text('Присоединиться'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Присоединиться').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Присоединиться'));
      await tester.pumpAndSettle();
      expect(
        find.text('Пароль должен содержать не менее 12 символов'),
        findsOneWidget,
      );
      final password = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('login-password')),
          matching: find.byType(EditableText),
        ),
      );
      expect(password.focusNode.hasFocus, isTrue);
      expect(attempts, 0);
      repo.client.close();
    },
  );

  testWidgets('server field error keeps draft open and focuses the field', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FamilyForm(
          title: 'Награда',
          fields: const [
            FamilyField('title', 'Название', initial: 'Конструктор'),
            FamilyField('price', 'Стоимость', kind: 'int', initial: 0),
          ],
          onSave: (data) async {
            attempts++;
            if (data['price'] == 0) {
              throw ApiFailure(
                422,
                'Стоимость должна быть больше нуля',
                fields: {'price': 'Стоимость должна быть больше нуля'},
              );
            }
            return {};
          },
        ),
      ),
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyForm), findsOneWidget);
    expect(find.text('Конструктор'), findsOneWidget);
    final price = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('field-price')),
        matching: find.byType(EditableText),
      ),
    );
    expect(price.focusNode.hasFocus, isTrue);
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'video stage fills screen while hang-up remains visible at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
              padding: EdgeInsets.only(top: 24, bottom: 48),
            ),
            child: FamilyCallView(
              title: 'Мама',
              status: 'Соединение установлено',
              people: const [
                CallPerson(
                  name: 'Мама',
                  video: ColoredBox(color: Colors.blue),
                ),
              ],
              controls: const [Text('Микрофон')],
              onClose: () {},
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('call-fullscreen-stage'))),
        const Rect.fromLTWH(0, 0, 320, 800),
      );
      expect(find.text('Завершить').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
