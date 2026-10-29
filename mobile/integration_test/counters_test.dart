import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/child_today.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';

import '../test/counters_test.dart' show CountersFixture, showCounters;
import '../test/field_layout_test.dart' show mountFields, revealField;
import '../test/unread_badge_test.dart' show ReadFixture, settleReads;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android updates task, financial and viewed message counters', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('counters-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
    }

    for (final role in ['parent', 'child']) {
      final repo = CountersFixture(role: role);
      try {
        await showCounters(
          tester,
          repo,
          () => role == 'parent'
              ? TodayScreen(repository: repo, openPage: (_) {})
              : ChildToday(repository: repo, openPage: (_) {}),
          size: null,
        );
        final before = role == 'parent'
            ? 'Результатов на проверке: 1'
            : 'Проверено 1 из 3';
        await revealField(tester, find.text(before));
        repo.approved();
        await tester.pumpAndSettle();
        expect(
          find.text(
            role == 'parent'
                ? 'Результатов на проверке: 0'
                : 'Проверено 2 из 3',
          ),
          findsOneWidget,
        );
        if (role == 'parent') {
          repo.firstPaid();
          repo.secondCancelled();
          await tester.pumpAndSettle();
          expect(find.text('Заявок на награды и деньги: 0'), findsOneWidget);
        }
        await capture(role);
        if (role == 'parent') {
          await showCounters(
            tester,
            repo,
            () => MoneyScreen(
              repository: repo,
              perform: (_) async => fail('Viewing must not move money'),
            ),
            size: null,
          );
          expect(
            find.text('Всего: 75 · в заявках: 0 · доступно: 75'),
            findsOneWidget,
          );
          await revealField(tester, find.text('Штрафы ждут подтверждения: 1'));
          repo.fineApplied();
          await tester.pumpAndSettle();
          expect(find.text('Штрафы ждут подтверждения: 0'), findsOneWidget);
          await revealField(
            tester,
            find.text('Всего: -425 · в заявках: 0 · доступно: -425'),
          );
          await capture('money');
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        repo.client.close();
        repo.dispose();
      }
    }
    final chat = ReadFixture()..holdRead = Completer<void>();
    try {
      await mountFields(
        tester,
        Scaffold(
          body: FamilyScreen(repository: chat, perform: (_) async {}),
        ),
        scale: 1.2,
        screenSize: null,
      );
      await tester.tap(find.text('Степан'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      expect(chat.readRequests.length, 1);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      chat.holdRead!.complete();
      await settleReads(tester);
      expect(chat.readRequests.length, 2);
      expect(chat.unread, 0);
      expect(
        find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 2')),
        findsNothing,
      );
      await capture('chat');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chat.client.close();
      chat.dispose();
    }
    binding.reportData = {
      ...?binding.reportData,
      'synthetic_only': true,
      'physical_devices_tested': false,
      'parent_review_updates': true,
      'child_daily_progress_updates': true,
      'requests_and_money_update': true,
      'pending_penalties_update': true,
      'quick_back_confirms_all_viewed_messages': true,
    };
  });
}
