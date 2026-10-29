import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_model.dart';
import 'package:mykids_family/engagement/preview_controller.dart';

void main() {
  PreviewEngagementController make({Future<void> Function(String)? save}) {
    final c = PreviewEngagementController(
      EngagementReviewRepository(),
      save: save ?? (_) async {},
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'first snapshot has one confirmed deal and exactly the starter objects',
    () {
      final c = make();
      expect(c.completedCount, 1);
      expect(c.state.earned, {'badge', 'plant', 'chair'});
      expect(c.adventureTasks.map((t) => t.id), ['flowers', 'read', 'bag']);
      expect(c.unlocked(playItem('headphones')), isFalse);
      expect(c.repository.endpoint, 'https://design-review.invalid');
    },
  );
  test(
    'child submission waits for parent; duplicate approval cannot pay twice',
    () async {
      final c = make();
      final balance = c.repository.snapshot!['balance']['total'];
      await c.submit('read', 'Прочитал любимую книгу');
      expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
      expect(c.completedCount, 1);
      expect(c.unlocked(playItem('desk')), isFalse);
      await expectLater(c.review('read', approve: true), throwsStateError);
      await c.switchRole('parent');
      await c.review('read', approve: true);
      expect(c.completedCount, 2);
      expect(c.unlocked(playItem('headphones')), isTrue);
      expect(c.unlocked(playItem('desk')), isTrue);
      expect(c.repository.snapshot!['balance']['total'], balance + 20);
      await expectLater(c.review('read', approve: true), throwsStateError);
      expect(c.repository.snapshot!['balance']['total'], balance + 20);
    },
  );
  test('returned result includes the actual parent hint and can be submitted again', () async {
    final c = make();
    await c.submit('read', 'Готово');
    await c.switchRole('parent');
    await c.review(
      'read',
      approve: false,
      note: 'Расскажи, кто главный герой книги',
    );
    final task = c.tasks.firstWhere((t) => t.id == 'read');
    expect(task.status, 'returned');
    expect(task.reviewNote, 'Расскажи, кто главный герой книги');
    expect(task.submissionNote, 'Готово');
    await c.switchRole('child');
    await c.submit('read', 'Теперь рассказал');
    await c.switchRole('parent');
    await c.review('read', approve: true);
    expect(c.completedCount, 2);
  });
  test(
    'locked objects and another participant step cannot be changed by child',
    () async {
      final c = make();
      await expectLater(c.wear('cape'), throwsStateError);
      await expectLater(c.place('desk', 2), throwsStateError);
      await expectLater(
        c.markOwnStep('picnic', 'picnic-parent'),
        throwsStateError,
      );
      await expectLater(c.setEnabled('hero', false), throwsStateError);
      expect(c.state.worn, {'badge'});
      expect(c.state.room, ['plant', 'chair', null]);
      expect(c.state.adultSteps, isEmpty);
    },
  );
  test(
    'failed persistence rolls back task state, coins, achievements and queue',
    () async {
      var fail = false;
      String? saved;
      final c = make(
        save: (value) async {
          if (fail) throw StateError('simulated storage failure');
          saved = value;
        },
      );
      await c.submit('read', 'Готово');
      await c.switchRole('parent');
      final balance = c.repository.snapshot!['balance']['total'];
      fail = true;
      await expectLater(c.review('read', approve: true), throwsStateError);
      expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
      expect(c.completedCount, 1);
      expect(c.repository.snapshot!['balance']['total'], balance);
      expect(c.storageError, isNotNull);
      fail = false;
      await c.review('read', approve: true);
      expect(c.completedCount, 2);
      expect(c.storageError, isNull);
      expect(jsonDecode(saved!)['state']['confirmed_tasks'], contains('read'));
    },
  );
  test(
    'rapid duplicate submissions are serialized without duplicate results',
    () async {
      final c = make();
      final first = c.submit('read', 'Первый результат');
      final second = c.submit('read', 'Повторный результат');
      await first;
      await expectLater(second, throwsStateError);
      expect(
        c.repository
            .rows('submissions')
            .where((s) => s['task_id'] == 'read')
            .length,
        1,
      );
    },
  );
  test(
    'one physical item moves between slots, and state survives every world',
    () async {
      final c = make();
      await c.renameHero('Метеор');
      await c.chooseHero('comic');
      await c.place('plant', 2);
      expect(c.state.room, [null, 'chair', 'plant']);
      for (final design in GameDesign.all) {
        await c.chooseDesign(design.id);
        final restored = make();
        restored.restore(c.encode());
        expect(restored.state.hero, 'comic');
        expect(restored.state.name, 'Метеор');
        expect(restored.state.room, [null, 'chair', 'plant']);
        expect(restored.state.earned, c.state.earned);
        expect(restored.designId, design.id);
      }
    },
  );
  test(
    'earned items are retained if an old confirmed task is later cancelled',
    () async {
      final c = make();
      await c.submit('read', 'Готово');
      await c.switchRole('parent');
      await c.review('read', approve: true);
      await c.switchRole('child');
      await c.wear('headphones');
      await c.place('desk', 2);
      await c.switchRole('parent');
      await c.repository.mutate('/v1/tasks/read/actions', {'action': 'cancel'});
      expect(c.completedCount, 2);
      expect(c.unlocked(playItem('headphones')), isTrue);
      expect(c.state.worn, contains('headphones'));
      expect(c.state.room, contains('desk'));
    },
  );
  test('family victory needs all three participants; praise and claim are idempotent', () async {
    final c = make();
    await c.submit('bag', 'Рюкзак собран');
    await c.switchRole('parent');
    await c.review('bag', approve: true);
    await c.markOwnStep('picnic', 'picnic-parent');
    expect(c.completedMissions, 0);
    await c.sendPraise('picnic', 'Горжусь тобой!');
    await c.sendPraise('picnic', 'Горжусь тобой!');
    expect(c.state.praise.length, 1);
    await expectLater(
      c.markOwnStep('picnic', 'picnic-relative'),
      throwsStateError,
    );
    await c.switchRole('relative');
    await c.markOwnStep('picnic', 'picnic-relative');
    expect(c.completedMissions, 1);
    expect(c.unlocked(playItem('trophy')), isTrue);
    final balance = c.repository.snapshot!['balance']['total'];
    await c.switchRole('child');
    await c.claimMission('picnic');
    await c.claimMission('picnic');
    await c.sendPraise('picnic', 'Спасибо!');
    expect(c.state.claimedMissions, {'picnic'});
    expect(c.repository.snapshot!['balance']['total'], balance);
    await c.place('trophy', 2);
    expect(c.state.room[2], 'trophy');
  });
  test('parent-created mission has one real task and shared event without minted coins', () async {
    final c = make();
    await c.switchRole('parent');
    final count = c.tasks.length,
        balance = c.repository.snapshot!['balance']['total'];
    await c.createMission(
      title: 'Пойдём в парк',
      description: 'Подготовимся к прогулке',
      reward: 'Прогулка вместе',
      childStep: 'Взять мяч',
      parentStep: 'Собрать воду',
      helperId: 'father',
      helperStep: 'Выбрать маршрут',
    );
    expect(c.tasks.length, count + 1);
    final mission = c.state.missions.last;
    expect(mission.steps.last.owner, 'father');
    expect(c.memberName(mission.steps.last.owner), 'Папа');
    await expectLater(
      c.markOwnStep(mission.id, mission.steps.last.id),
      throwsStateError,
    );
    await c.switchRole('father');
    await c.markOwnStep(mission.id, mission.steps.last.id);
    expect(c.state.adultSteps, contains(mission.steps.last.id));
    await c.switchRole('parent');
    expect(
      c.tasks.any(
        (t) => t.id == mission.steps.first.taskId && t.title == 'Взять мяч',
      ),
      isTrue,
    );
    expect(c.repository.snapshot!['balance']['total'], balance);
    await c.switchRole('child');
    await c.join(mission.id);
    expect(c.state.joined, contains(mission.id));
    await expectLater(c.claimMission(mission.id), throwsStateError);
  });
  test(
    'parent selects actual tasks for an adventure and preserves earned items',
    () async {
      final c = make();
      await expectLater(
        c.chooseAdventureTasks(['read', 'bag', 'movie-task']),
        throwsStateError,
      );
      await c.switchRole('parent');
      await expectLater(
        c.chooseAdventureTasks(['read', 'read', 'bag']),
        throwsArgumentError,
      );
      await c.chooseAdventureTasks(['movie-task', 'read', 'bag']);
      expect(c.adventureTasks.map((t) => t.id), ['movie-task', 'read', 'bag']);
      expect(c.state.earned, contains('chair'));
      final restored = make()..restore(c.encode());
      expect(restored.adventureTasks.first.title, 'Выбрать фильм');
    },
  );
  test(
    'turning a feature off preserves objects and rejects child modification',
    () async {
      final c = make();
      await c.switchRole('parent');
      await c.setEnabled('hero', false);
      await c.switchRole('child');
      await expectLater(c.chooseHero('comic'), throwsStateError);
      expect(c.state.earned, {'badge', 'plant', 'chair'});
      await c.switchRole('parent');
      await c.setEnabled('hero', true);
      await c.switchRole('child');
      await c.chooseHero('comic');
      expect(c.state.hero, 'comic');
    },
  );
  test(
    'invalid restore is rejected without replacing the synthetic family',
    () {
      final c = make();
      final before = c.encode();
      final encoded = jsonDecode(before) as Map<String, dynamic>;
      encoded['snapshot']['family']['id'] = 'another-family';
      expect(() => c.restore(jsonEncode(encoded)), throwsFormatException);
      expect(c.encode(), before);
      final state = c.state.toJson()..['room'] = ['plant', 'plant', null];
      expect(() => PlayState.fromJson(state), throwsFormatException);
    },
  );
}
