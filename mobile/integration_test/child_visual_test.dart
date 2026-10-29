import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/child_visuals.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:mykids_family/updates.dart';
import 'package:mykids_family/visuals.dart';

class QuietUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri manifestUrl, String role) async => null;
}

/// Synthetic unregistered identity; no storage or production connection.
class ChildFixture extends FamilyRepository {
  bool queued = false;
  int submissions = 0;
  ChildFixture()
    : super(client: MockClient((_) async => http.Response('{}', 200))) {
    variant = 'child';
    token = 'synthetic-unregistered-child';
    online = true;
    snapshot = {
      'user': {'id': 'child', 'name': 'Стёпа', 'role': 'child'},
      'family': {'timezone': 'Europe/Moscow'},
      'server_time': '2026-10-11T12:00:00Z',
      'balance': {'total': 125, 'available': 125, 'reserved': 0},
      'tasks': [
        {
          'id': 'task',
          'title': 'Прочитать 10 страниц',
          'description': 'Расскажи семье, что тебе понравилось в книге.',
          'due_at': '2030-01-01T12:00:00Z',
          'reward': 20,
          'penalty': 0,
          'status': 'assigned',
          'financial_approved': 1,
          'require_photo': 0,
          'note': '',
          'version': 1,
        },
      ],
      'rewards': [
        {
          'id': 'reward',
          'title': 'Семейный поход в кино',
          'description': 'Выбираем фильм вместе',
          'price': 200,
          'available': 1,
        },
      ],
      'goal': {'reward_id': 'reward'},
      'ledger': <Map<String, dynamic>>[],
    };
  }
  @override
  Future<void> sync() async {}
  @override
  Future<List<Map<String, Object?>>> pending() async => [];
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    expect(path, '/v1/tasks/task/submissions');
    expect(offlineSubmission, true);
    submissions++;
    if (queued) return {'queued': true, 'message': 'Сохранено'};
    (snapshot!['tasks'] as List).single['status'] = 'submitted';
    notifyListeners();
    return {'accepted': true, 'message': 'Отправлено на проверку'};
  }

  void approve() {
    (snapshot!['tasks'] as List).single['status'] = 'completed';
    snapshot!['ledger'] = [
      {
        'id': 'earned',
        'child_id': 'child',
        'source_type': 'task',
        'actual': 20,
        'requested': 20,
        'reason': 'Выполнено: Прочитать 10 страниц',
        'created_at': '2026-10-11T12:01:00Z',
      },
    ];
    snapshot!['balance'] = {'total': 145, 'available': 145, 'reserved': 0};
    notifyListeners();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('child illustrated screens and truthful joy on Android', (
    tester,
  ) async {
    final repo = ChildFixture();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(
      MyKidsApp(repository: repo, createUpdates: QuietUpdates.new),
    );
    await tester.runAsync(
      () => precacheFamilyArtwork(tester.element(find.byType(MyKidsApp))),
    );
    Future<void> settle() async {
      // This screen intentionally stays alive with periodic raster animation.
      // Use bounded frames rather than waiting for all scheduled frames to end.
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(String name, {bool settleFirst = true}) async {
      if (settleFirst) await settle();
      // A newly mounted FutureBuilder needs its own frame even when the atlas
      // was already decoded. Wait for actual painters, not arbitrary delay.
      for (int attempt = 0; attempt < 40; attempt++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        final ready = find
            .byType(RasterSprite)
            .evaluate()
            .every(
              (sprite) => find
                  .descendant(
                    of: find.byWidget(sprite.widget),
                    matching: find.byType(CustomPaint),
                  )
                  .evaluate()
                  .isNotEmpty,
            );
        if (ready) break;
      }
      for (final sprite in find.byType(RasterSprite).evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(sprite.widget),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      }
      // Native screenshot requests schedule a frame asynchronously. Keep
      // pumping while they finish even on a completely static screen.
      bool complete = false;
      final pending = binding.takeScreenshot('child-v2-$name');
      pending.whenComplete(() => complete = true).ignore();
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!complete && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      if (!complete) throw StateError('Native screenshot timeout: $name');
      await pending;
      debugPrint('Verified screenshot: $name');
    }

    await capture('today');
    for (final item in {
      'Календарь': 'calendar',
      'Задания': 'tasks',
      'Монеты': 'money',
      'Семья': 'family',
    }.entries) {
      await tester.tap(find.text(item.key).last);
      await capture(item.value);
    }
    await tester.tap(find.text('Задания').last);
    await settle();
    Future<void> submit() async {
      debugPrint('Submitting synthetic task; queued=${repo.queued}');
      await tester.tap(find.text('Прочитать 10 страниц'));
      await settle();
      await tester.ensureVisible(find.text('Готово — отправить на проверку'));
      await tester.tap(find.text('Готово — отправить на проверку'));
      await settle();
      await tester.tap(find.text('Отправить на проверку'));
      await settle();
      expect(find.text('Отличный шаг!'), findsOneWidget);
      expect(find.text('+20 монет'), findsNothing);
    }

    await submit();
    expect(repo.rows('tasks').single['status'], 'submitted');
    await capture('submitted');
    await tester.tap(find.text('Здорово!'));
    await settle();
    repo.approve();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(repo.rows('tasks').single['status'], 'completed');
    expect(
      find.descendant(
        of: find.byType(ChildSuccessDialog),
        matching: find.text('+20 монет'),
      ),
      findsOneWidget,
    );
    final mascot = find.descendant(
      of: find.byType(ChildSuccessDialog),
      matching: find.byType(ChildMotion),
    );
    final sprite = find.descendant(
      of: mascot,
      matching: find.byType(RasterSprite),
    );
    final firstFrame = tester.widget<RasterSprite>(sprite).source;
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.widget<RasterSprite>(sprite).source, isNot(firstFrame));
    // Native screenshot transfer can take longer than the short jump. Verify
    // authored frame changes above; capture the complete visible dialog below.
    await capture('reward');
    await tester.tap(find.text('Здорово!'));
    await settle();
    repo.notifyListeners();
    await settle();
    expect(find.byType(ChildSuccessDialog), findsNothing);
    repo.queued = true;
    repo.online = false;
    (repo.snapshot!['tasks'] as List).single['status'] = 'assigned';
    repo.notifyListeners();
    await settle();
    await submit();
    expect(
      find.textContaining('Результат сохранён на телефоне.'),
      findsOneWidget,
    );
    await capture('offline-saved');
    await tester.tap(find.text('Здорово!'));
    await settle();
    expect(repo.submissions, 2);
    binding.reportData = {
      ...?binding.reportData,
      'all_five_child_tabs_rendered': true,
      'all_visible_sprites_decoded': true,
      'submission_does_not_claim_coins': true,
      'confirmed_reward_visible': true,
      'animation_source_changes_native': true,
      'repeated_snapshot_does_not_repeat_celebration': true,
      'offline_submission_has_correct_feedback': true,
      'scope': 'Actual Android 16 UI; isolated synthetic responses. No real family login or production data writes. Physical phones not tested.',
    };
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
  });
}
