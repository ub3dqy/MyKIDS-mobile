import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_review.dart';
import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/design_today.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/task_screen.dart';
import 'package:mykids_family/main.dart' as family;
import 'package:mykids_family/invitation.dart';

import 'dart:convert';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('MyKidsNunito')
      ..addFont(rootBundle.load('assets/designs/Nunito.ttf'));
    await font.load();
  });
  test('all five designs have distinct full specifications and retain legacy default', () {
    expect(GameDesign.all.map((d) => d.id).toSet().length, 5);
    expect(GameDesign.byId(''), isNull);
    expect(GameDesign.byId('unknown'), isNull);
    expect(
      Invitation(
        role: 'child',
        token: DesignReviewRepository.reviewInvitation,
      ).token.length,
      43,
    );
    for (final design in GameDesign.all) {
      final theme = design.theme(true);
      expect(theme.textTheme.bodyMedium!.fontSize, 16);
      expect(theme.scaffoldBackgroundColor, design.background);
      expect(theme.cardTheme.shape, isNotNull);
      expect(
        design.animation,
        startsWith('assets/designs/${design.id}-motion'),
      );
      expect(design.animation, endsWith('.png'));
    }
  });

  test(
    'review workflow preserves approval and reserved money contracts',
    () async {
      final repo = DesignReviewRepository();
      addTearDown(() {
        repo.client.close();
        repo.dispose();
      });
      await repo.mutate(
        '/v1/tasks/read/submissions',
        {'note': 'Прочитал!'},
        files: ['assets/designs/blocks-scene.png'],
      );
      final submission = repo.rows('submissions').single;
      expect(submission['accepted'], 1);
      expect(submission['note'], 'Прочитал!');
      final photoIds =
          jsonDecode(submission['attachment_ids'] as String) as List;
      expect(photoIds, hasLength(1));
      expect(
        (await repo.attachment(photoIds.single as String)).existsSync(),
        isTrue,
      );
      await repo.mutate(
        '/v1/tasks/read/submissions/photos',
        {'submission_id': submission['id']},
        files: ['assets/designs/comic-scene.png'],
      );
      expect(
        jsonDecode(repo.rows('submissions').single['attachment_ids'] as String),
        hasLength(2),
      );
      expect(repo.snapshot!['balance']['available'], 125);
      expect(repo.rows('tasks').first['status'], 'submitted');
      repo.switchRole('parent');
      await repo.mutate('/v1/tasks/read/actions', {'action': 'approve'});
      expect(repo.snapshot!['balance']['available'], 145);
      await repo.mutate('/v1/tasks/read/actions', {'action': 'approve'});
      expect(repo.snapshot!['balance']['available'], 145);
      repo.switchRole('child');
      await repo.mutate('/v1/redemptions', {'reward_id': 'picnic'});
      expect(repo.snapshot!['balance']['reserved'], 100);
      expect(repo.snapshot!['balance']['available'], 45);
      final id = repo.rows('redemptions').single['id'];
      repo.switchRole('parent');
      await repo.mutate('/v1/redemptions/$id/actions', {'action': 'reject'});
      expect(repo.snapshot!['balance']['available'], 145);
      expect(repo.snapshot!['balance']['reserved'], 0);
      await repo.mutate('/v1/redemptions/$id/actions', {'action': 'reject'});
      expect(repo.snapshot!['balance']['available'], 145);
      expect(repo.snapshot!['balance']['reserved'], 0);
    },
  );

  for (final design in GameDesign.all) {
    testWidgets('${design.id}: compact phone with large system text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = DesignReviewRepository();
      gameDesign.value = design;
      addTearDown(() {
        gameDesign.value = null;
        repo.client.close();
        repo.dispose();
      });
      await tester.pumpWidget(
        family.MyKidsApp(
          repository: repo,
          createBackground: ReviewBackground.new,
          createUpdates: ReviewUpdates.new,
        ),
      );
      await frames(tester);
      expect(tester.takeException(), isNull);
      for (final label in ['Календарь', 'Задания', 'Монеты', 'Семья']) {
        await tester.tap(find.widgetWithText(TextButton, label).last);
        await frames(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: '${design.id}: large text $label',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
    });
    testWidgets(
      '${design.id}: real child, parent and relative screens, not a separate mock UI',
      (tester) async {
        tester.view.physicalSize = const Size(412, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = DesignReviewRepository();
        gameDesign.value = design;
        addTearDown(() {
          gameDesign.value = null;
          repo.client.close();
          repo.dispose();
        });
        await tester.pumpWidget(DesignReviewApp(repository: repo));
        await frames(tester);
        expect(find.byType(GameToday), findsOneWidget);
        expect(find.text('Твой день'), findsOneWidget);
        expect(find.text('Мои задания'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final label in ['Календарь', 'Задания', 'Монеты', 'Семья']) {
          await tester.tap(find.widgetWithText(TextButton, label).last);
          await frames(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: '${design.id}: $label',
          );
        }
        expect(find.byType(FamilyScreen), findsOneWidget);
        for (final label in ['Контакты', 'Звонки', 'Чаты']) {
          await tester.tap(find.text(label).last);
          await frames(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: '${design.id}: $label',
          );
        }
        await tester.tap(find.text('Мама').first);
        await frames(tester);
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.text('Не забудь шапочку для бассейна 💙'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await frames(tester);
        repo.switchRole('parent');
        await frames(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Задания').last);
        await frames(tester);
        expect(find.byType(TaskScreen), findsOneWidget);
        expect(find.text('Добавить задание'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Добавить задание'));
        await frames(tester);
        expect(find.text('Название'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await frames(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Монеты').last);
        await frames(tester);
        expect(find.byType(MoneyScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        repo.switchRole('relative');
        await frames(tester);
        expect(find.widgetWithText(TextButton, 'Монеты'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await frames(tester);
      },
    );
  }
}
