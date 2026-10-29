import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/login_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/schedule.dart';
import 'package:mykids_family/settings_screen.dart';
import 'package:mykids_family/visuals.dart';

import '../test/calendar_test.dart' as calendar;
import '../test/field_layout_test.dart'
    show mountFields, revealField, labelFits, SettingsFixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('large text fields and settings remain separated on Android', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await binding.takeScreenshot('fields-$name');
    }

    for (final role in ['child', 'parent', 'relative']) {
      final repo = FamilyRepository()
        ..variant = role
        ..endpoint = 'https://family.example';
      await mountFields(
        tester,
        LoginScreen(
          repository: repo,
          onLogin: () async {},
          onUpdates: () async {},
        ),
        child: role == 'child',
        screenSize: null,
      );
      await tester.runAsync(
        () => precacheFamilyArtwork(tester.element(find.byType(LoginScreen))),
      );
      await revealField(tester, find.text('У меня есть приглашение'));
      await tester.tap(find.text('У меня есть приглашение'));
      await tester.pump(const Duration(milliseconds: 200));
      for (final entry in {
        'invite': 'Приглашение от родителя',
        'name': 'Ваше имя',
        'username': 'Логин',
        'password': 'Пароль',
      }.entries) {
        final field = find.byKey(ValueKey('login-${entry.key}'));
        await revealField(tester, field);
        await tester.enterText(
          field,
          entry.key == 'invite'
              ? List.filled(43, 'A').join()
              : 'Искусственный профиль',
        );
        await tester.pump();
        labelFits(tester, field, entry.value);
      }
      await capture('$role-login-bottom');
      await revealField(tester, find.byKey(const ValueKey('login-invite')));
      await capture('$role-login-top');
      await tester.pumpWidget(const SizedBox.shrink());
      repo.client.close();
      repo.dispose();
    }
    final repo = SettingsFixture();
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
      screenSize: null,
    );
    await revealField(tester, find.text('Настройки уведомлений телефона'));
    await capture('settings');
    await revealField(tester, find.text('Часовой пояс и тихие часы'));
    await tester.tap(find.text('Часовой пояс и тихие часы'));
    await tester.pump(const Duration(milliseconds: 300));
    final zone = find.byKey(const ValueKey('field-timezone'));
    labelFits(tester, zone, 'Часовой пояс');
    await capture('settings-time-form');
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
    final data = calendar.snapshot([])
      ..['subjects'] = [
        {
          'id': 'subject',
          'name': 'Изобразительное искусство и художественный труд',
        },
      ];
    await mountFields(
      tester,
      CalendarEditor(
        snapshot: data,
        day: familyClock(data, DateTime.utc(2026, 10, 12, 12)),
        initial: {
          ...calendar.event('Урок', '08:30', '09:30'),
          'subject_id': 'subject',
        },
      ),
      screenSize: null,
    );
    await revealField(tester, find.byKey(const ValueKey('event-note')));
    labelFits(tester, find.byKey(const ValueKey('event-note')), 'Примечание');
    await capture('calendar');
    await tester.pumpWidget(const SizedBox.shrink());
    await mountFields(
      tester,
      const FamilyForm(
        title: 'Задание и награда',
        fields: [
          FamilyField(
            'person',
            'Кому поручить выполнение задания',
            kind: 'choice',
            initial: 'relative',
            choices: {'relative': 'Бабушка Александра Константиновна'},
          ),
          FamilyField('reward', 'Награда за выполнение задания', kind: 'int'),
          FamilyField(
            'description',
            'Описание задания',
            kind: 'note',
            required: false,
          ),
        ],
      ),
      screenSize: null,
    );
    labelFits(
      tester,
      find.byKey(const ValueKey('field-person')),
      'Кому поручить выполнение задания',
    );
    await capture('shared-form');
    expect(tester.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'roles_checked': 3,
      'text_scale': 2,
      'pages_checked': [
        'login',
        'settings',
        'family_time',
        'calendar',
        'shared_task_school_money_form',
      ],
      'labels_above_fields_verified': true,
      'physical_phone_tested': false,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
