import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/action_cancelled.dart';
import 'package:mykids_family/engagement/engagement_pages.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/preview_controller.dart';
import 'package:mykids_family/engagement/production_controller.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite/sqflite.dart';

import 'support/engagement_fixture.dart';

class _DbMarker extends Fake implements Database {}

class _Repository extends ProductionFixtureRepository {
  final calls = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? handle;
  Future<String> Function(String)? keep;
  List<Map<String, dynamic>> queuedRows = [];
  @override
  Future<List<Map<String, dynamic>>> pending() async => queuedRows;
  _Repository(super.preview);
  @override
  Future<String> keepFile(String path) => keep!(path);
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    calls.add({
      'path': path,
      'body': body,
      'method': method,
      'offline': offlineSubmission,
      'files': files,
    });
    if (handle != null) return handle!(path, body);
    if (path.startsWith('/v1/engagement/')) {
      if (body['expected_revision'] != play['revision']) {
        throw ApiFailure(409, 'Прогресс изменился');
      }
      switch (body['action']) {
        case 'choose_hero':
          play['state']['hero'] = body['hero'];
        case 'rename_hero':
          play['state']['name'] = body['name'];
        case 'wear':
          final worn = (play['state']['worn'] as List).cast<String>();
          body['worn'] == true
              ? worn.add(body['item'] as String)
              : worn.remove(body['item']);
          play['state']['worn'] = worn.toSet().toList();
        case 'set_adventure':
          play['state']['adventure_task_ids'] = body['task_ids'];
      }
      play['revision'] = (play['revision'] as int) + 1;
      publish();
      return {'ok': true};
    }
    if (path.endsWith('/submissions')) {
      final id = path.split('/')[3];
      (snapshot!['tasks'] as List).firstWhere((t) => t['id'] == id)['status'] =
          'submitted';
      publish();
      return {'accepted': true};
    }
    return {'ok': true};
  }

  @override
  Future<void> refreshAfterChange() async {
    publish();
  }
}

void main() {
  late PreviewEngagementController preview;
  late _Repository repo;
  setUp(() {
    preview = PreviewEngagementController(
      EngagementReviewRepository(),
      save: (_) async {},
    );
    repo = _Repository(preview);
  });
  tearDown(() {
    repo.client.close();
    repo.dispose();
    preview.dispose();
  });
  ProductionEngagementController make({
    PlayPhotos? photos,
    PlayReview? review,
  }) {
    final c = ProductionEngagementController(
      repo,
      selectPhotos: photos,
      showDetailedReview: review,
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'acknowledged old queue errors never block a later successful action',
    () async {
      repo.db = _DbMarker();
      repo.queuedRows = [
        {
          'id': 'old',
          'path': '/v1/engagement/child/commands',
          'state': 'failed',
          'error': 'Прежний конфликт',
        },
      ];
      final c = make();
      await Future<void>.delayed(Duration.zero);
      expect(c.storageError, 'Прежний конфликт');
      await c.renameHero('Луна');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.name, 'Луна');
      expect(c.storageError, isNull);
      repo.db = null;
    },
  );
  test(
    'a newly rejected queued command still reports the real conflict',
    () async {
      repo.db = _DbMarker();
      final c = make();
      await Future<void>.delayed(Duration.zero);
      repo.handle = (path, body) async {
        repo.queuedRows = [
          {
            'id': 'new',
            'path': path,
            'body': jsonEncode(body),
            'state': 'pending',
          },
        ];
        return {'queued': true};
      };
      await c.renameHero('Луна');
      repo.queuedRows.single['state'] = 'failed';
      repo.queuedRows.single['error'] = 'Новый конфликт';
      repo.publish();
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, isFalse);
      expect(c.storageError, 'Новый конфликт');
      repo.db = null;
    },
  );
  test(
    'HTTP 503 preserves a durable profile command without a false failure',
    () async {
      repo.db = _DbMarker();
      final c = make();
      await Future<void>.delayed(Duration.zero);
      repo.handle = (path, body) async {
        repo.queuedRows = [
          {'path': path, 'state': 'pending', 'body': jsonEncode(body)},
        ];
        throw ApiFailure(503, 'Сервер временно недоступен');
      };
      await c.renameHero('Солнце');
      expect(c.busy, isTrue);
      expect(c.state.name, 'Искра');
      expect(repo.calls.single['offline'], isTrue);
      repo.db = null;
    },
  );
  test(
    'HTTP 503 is never reported as saved without a matching queue row',
    () async {
      repo.db = _DbMarker();
      repo.handle = (_, _) async => throw ApiFailure(503, 'Сбой сервера');
      final c = make();
      await expectLater(c.renameHero('Солнце'), throwsA(isA<ApiFailure>()));
      expect(c.busy, isFalse);
      repo.db = null;
    },
  );
  test(
    'HTTP 503 keeps a queued task waiting without unlocking cosmetics',
    () async {
      repo.db = _DbMarker();
      final c = make();
      await Future<void>.delayed(Duration.zero);
      repo.handle = (path, body) async {
        repo.queuedRows = [
          {
            'path': path,
            'state': 'pending',
            'body': jsonEncode({
              ...body,
              'attachment_ids': ['uploaded'],
            }),
          },
        ];
        throw ApiFailure(503, 'Сбой сервера');
      };
      await c.submit('read', 'Прочитал');
      expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
      expect(c.state.earned, isNot(contains('headphones')));
      repo.db = null;
    },
  );
  test(
    'queued task notice clears after the server accepts durable replay',
    () async {
      repo.db = _DbMarker();
      final c = make();
      await Future<void>.delayed(Duration.zero);
      repo.handle = (path, body) async {
        repo.queuedRows = [
          {'path': path, 'state': 'pending'},
        ];
        return {'queued': true};
      };
      await c.submit('read', 'Прочитал');
      expect(c.storageError, isNotNull);
      repo.queuedRows = [];
      (repo.snapshot!['tasks'] as List).firstWhere(
        (t) => t['id'] == 'read',
      )['status'] = 'submitted';
      repo.publish();
      await Future<void>.delayed(Duration.zero);
      expect(c.storageError, isNull);
      expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
      repo.db = null;
    },
  );
  testWidgets('a rejected creation never opens an identical remote mission', (
    tester,
  ) async {
    repo.switchRole('parent');
    final c = make();
    gameDesign.value = GameDesign.all.first;
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => gameDesign.value = null);
    await tester.pumpWidget(
      MaterialApp(
        theme: gameDesign.value!.theme(false),
        builder: (_, child) => EngagementScope(controller: c, child: child!),
        home: const MissionCreatePage(),
      ),
    );
    final fields = find.byType(TextFormField);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(fields.at(i), 'Дело $i');
    }
    repo.handle = (_, body) async {
      (repo.play['state']['missions'] as List).add({
        'id': 'remote',
        'title': body['title'],
        'description': body['description'],
        'reward': body['reward'],
        'steps': [
          {
            'id': 'a',
            'owner': 'child',
            'title': body['child_step'],
            'task_id': 'bag',
          },
          {
            'id': 'b',
            'owner': 'parent',
            'title': body['parent_step'],
            'task_id': null,
          },
          {
            'id': 'c',
            'owner': body['helper_id'],
            'title': body['helper_step'],
            'task_id': null,
          },
        ],
      });
      repo.publish();
      throw ApiFailure(409, 'Прогресс изменился');
    };
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.text('Создать миссию'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Создать миссию'));
    await tester.pumpAndSettle();
    expect(find.text('Новая семейная миссия'), findsOneWidget);
    expect(find.text('Наша миссия'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'queued profile command blocks duplicates until durable replay finishes',
    () async {
      repo.db = _DbMarker();
      final c = make();
      await Future<void>.delayed(Duration.zero);
      repo.handle = (path, body) async {
        repo.queuedRows = [
          {'path': path, 'state': 'pending'},
        ];
        return {'queued': true};
      };
      await c.renameHero('Звезда');
      expect(c.busy, isTrue);
      await expectLater(c.renameHero('Второе имя'), throwsA(isA<ApiFailure>()));
      expect(repo.calls, hasLength(1));
      repo.queuedRows = [];
      repo.play['state']['name'] = 'Звезда';
      repo.publish();
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, isFalse);
      expect(c.state.name, 'Звезда');
      expect(c.storageError, isNull);
      repo.db = null;
    },
  );
  test(
    'optional submitted photos still require the existing detailed review',
    () async {
      repo.switchRole('parent');
      (repo.snapshot!['tasks'] as List).firstWhere(
        (t) => t['id'] == 'read',
      )['status'] = 'submitted';
      repo.snapshot!['submissions'] = [
        {'task_id': 'read', 'accepted': 1, 'attachment_ids': '["photo"]'},
      ];
      repo.publish();
      var opened = false;
      final c = make(
        review: (id) async {
          opened = true;
          (repo.snapshot!['tasks'] as List).firstWhere(
            (t) => t['id'] == id,
          )['status'] = 'completed';
          repo.publish();
        },
      );
      await c.review('read', approve: true);
      expect(opened, isTrue);
      expect(repo.calls, isEmpty);
    },
  );
  test(
    'generation changes are guarded even before the repository notifies',
    () async {
      final started = Completer<void>(),
          finish = Completer<Map<String, dynamic>>();
      repo.handle = (_, _) {
        started.complete();
        return finish.future;
      };
      final c = make();
      final action = c.renameHero('Чужое имя');
      await started.future;
      repo.generation++;
      finish.complete({'ok': true});
      await expectLater(action, throwsA(isA<ApiFailure>()));
      expect(c.state.name, 'Искра');
    },
  );
  test(
    'partial photo-copy failure removes only fresh unqueued copies',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'mykids-play-photos-',
      );
      try {
        final original = File('${temporary.path}/original.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final copy = File('${temporary.path}/owned.jpg');
        var count = 0;
        repo.keep = (path) async {
          if (count++ > 0) throw const FileSystemException('copy failed');
          return (await original.copy(copy.path)).path;
        };
        (repo.snapshot!['tasks'] as List).firstWhere(
          (t) => t['id'] == 'read',
        )['require_photo'] = 1;
        repo.publish();
        final c = make(photos: (_) async => [original.path, original.path]);
        await expectLater(
          c.submit('read', 'Готово'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await original.exists(), isTrue);
        expect(await copy.exists(), isFalse);
        expect(repo.calls, isEmpty);
      } finally {
        await temporary.delete(recursive: true);
      }
    },
  );
  test(
    'server DTO preserves all agreed content with no preview unlock decisions',
    () {
      final c = make();
      expect(c.state.toJson(), preview.state.toJson());
      expect(c.tasks.map((t) => t.title), preview.tasks.map((t) => t.title));
      expect(c.completedCount, 1);
      expect(c.memberName('parent'), 'Мама');
    },
  );
  test(
    'commands send authenticated child path and current revision, serialized',
    () async {
      final c = make();
      await Future.wait([c.chooseHero('squad'), c.renameHero('Молния')]);
      expect(repo.calls.map((r) => r['body']['expected_revision']), [1, 2]);
      expect(
        repo.calls.every((r) => r['path'] == '/v1/engagement/child/commands'),
        isTrue,
      );
      expect(c.state.hero, 'squad');
      expect(c.state.name, 'Молния');
      expect(
        repo.calls.every((r) => !(r['body'] as Map).containsKey('earned')),
        isTrue,
      );
    },
  );
  test(
    'cosmetics use absolute desired state rather than replaying a toggle',
    () async {
      final c = make();
      await c.wear('badge');
      expect(repo.calls.single['body']['worn'], isFalse);
      expect(c.state.worn, isEmpty);
    },
  );
  test(
    'real submission carries version, marked time and note; no local award',
    () async {
      final c = make();
      await c.submit('read', 'Прочитал книгу');
      final body = repo.calls.single['body'] as Map;
      expect(body['task_version'], 1);
      expect(DateTime.parse(body['marked_at'] as String).isUtc, isTrue);
      expect(body['note'], 'Прочитал книгу');
      expect(repo.calls.single['offline'], isTrue);
      expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
      expect(c.completedCount, 1);
      expect(c.state.earned, preview.state.earned);
    },
  );
  test('queued result shows waiting, blocks duplicate and does not unlock cosmetics', () async {
    repo.handle = (_, _) async => {'queued': true};
    final c = make();
    await c.submit('read', 'Готово');
    expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
    expect(c.completedCount, 1);
    await expectLater(c.submit('read', 'Ещё раз'), throwsA(isA<ApiFailure>()));
    expect(repo.calls.length, 1);
  });
  test(
    'cancelled required-photo selection sends no incomplete result',
    () async {
      (repo.snapshot!['tasks'] as List).firstWhere(
        (t) => t['id'] == 'read',
      )['require_photo'] = 1;
      repo.publish();
      final c = make(photos: (_) async => null);
      await expectLater(
        c.submit('read', 'Рассказ'),
        throwsA(isA<PlayActionCancelled>()),
      );
      expect(repo.calls, isEmpty);
      expect(c.busy, isFalse);
      expect(c.storageError, isNull);
    },
  );
  test('required-photo and counted review opens the existing complete result screen', () async {
    repo.switchRole('parent');
    final task = (repo.snapshot!['tasks'] as List).firstWhere(
      (t) => t['id'] == 'read',
    );
    task['require_photo'] = 1;
    task['status'] = 'submitted';
    repo.publish();
    var opened = false;
    final c = make(
      review: (id) async {
        expect(id, 'read');
        opened = true;
        (repo.snapshot!['tasks'] as List).firstWhere(
          (t) => t['id'] == id,
        )['status'] = 'completed';
        repo.publish();
      },
    );
    await c.review('read', approve: true);
    expect(opened, isTrue);
    expect(repo.calls, isEmpty);
  });
  test('cancelled detailed review never reports confirmation', () async {
    repo.switchRole('parent');
    final task = (repo.snapshot!['tasks'] as List).firstWhere(
      (t) => t['id'] == 'read',
    );
    task['require_photo'] = 1;
    task['status'] = 'submitted';
    repo.publish();
    final c = make(review: (_) async {});
    await expectLater(
      c.review('read', approve: true),
      throwsA(isA<PlayActionCancelled>()),
    );
    expect(c.tasks.firstWhere((t) => t.id == 'read').waiting, isTrue);
    expect(repo.calls, isEmpty);
  });
  test('a changed session cannot receive an earlier action result', () async {
    final started = Completer<void>(),
        finish = Completer<Map<String, dynamic>>();
    repo.handle = (_, _) {
      started.complete();
      return finish.future;
    };
    final c = make();
    final action = c.renameHero('Старое имя');
    await started.future;
    repo.switchRole('parent');
    finish.complete({'ok': true});
    await expectLater(action, throwsA(isA<ApiFailure>()));
    expect(c.role, 'parent');
    expect(c.state.name, 'Искра');
  });
  test(
    'private child task data is not needed to show shared mission completion',
    () {
      repo.switchRole('relative');
      repo.snapshot!['tasks'] = [];
      repo.snapshot!['submissions'] = [];
      repo.play['mission_tasks'] = [
        {
          'id': 'bag',
          'child_id': 'child',
          'title': 'Собрать рюкзак',
          'status': 'completed',
          'reward': 0,
        },
      ];
      repo.publish();
      final c = make();
      expect(c.tasks.single.completed, isTrue);
      expect(c.tasks.single.reward, 0);
      expect(c.tasks.single.submissionNote, isEmpty);
      expect(c.stepDone(c.state.missions.first.steps.first), isTrue);
    },
  );
  test(
    'total confirmed count remains correct after more than 1000 saved task IDs',
    () {
      repo.play['confirmed_total'] = 1200;
      repo.publish();
      final c = make();
      expect(c.completedCount, 1200);
    },
  );
}
