import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../design_review_repository.dart';
import '../design_system.dart';
import '../repository.dart';
import 'engagement_model.dart';
import 'preview_storage.dart';

PlayState initialPreviewState() {
  final result = PlayState();
  result.room = ['plant', 'chair', null];
  result.joined = {'picnic'};
  result.adventureTaskIds = ['flowers', 'read', 'bag'];
  result.missions = [
    const FamilyMission(
      'picnic',
      'Наш семейный пикник',
      'Каждый помогает — и мы вместе отправляемся на прогулку.',
      'Пикник всей семьёй',
      [
        MissionStep(
          'picnic-child',
          'child',
          'Собрать свой рюкзак',
          taskId: 'bag',
        ),
        MissionStep('picnic-parent', 'parent', 'Приготовить угощение'),
        MissionStep(
          'picnic-relative',
          'relative',
          'Выбрать место для прогулки',
        ),
      ],
    ),
    const FamilyMission(
      'movie',
      'Уютный вечер вместе',
      'Выберем фильм и устроим домашний кинотеатр.',
      'Вечер любимого кино',
      [
        MissionStep(
          'movie-child',
          'child',
          'Выбрать фильм',
          taskId: 'movie-task',
        ),
        MissionStep('movie-parent', 'parent', 'Выбрать время'),
        MissionStep('movie-relative', 'relative', 'Приготовить плед'),
      ],
    ),
  ];
  return result;
}

typedef PlaySave = Future<void> Function(String value);

/// Synthetic transactions are isolated from the public app and server.
/// The real repository's task/reward rules are reused rather than simulated twice.
class EngagementReviewRepository extends DesignReviewRepository {
  PreviewEngagementController? owner;
  Future<Map<String, dynamic>> directMutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) => super.mutate(
    path,
    body,
    method: method,
    offlineSubmission: offlineSubmission,
    files: files,
  );
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) => owner == null
      ? directMutate(
          path,
          body,
          method: method,
          offlineSubmission: offlineSubmission,
          files: files,
        )
      : owner!.transaction(
          () => directMutate(
            path,
            body,
            method: method,
            offlineSubmission: offlineSubmission,
            files: files,
          ),
        );
}

class PreviewEngagementController extends EngagementController {
  final EngagementReviewRepository repository;
  final PlaySave save;
  @override
  PlayState state = initialPreviewState();
  String designId = 'blocks';
  @override
  bool busy = false;
  @override
  String? storageError;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  PreviewEngagementController(this.repository, {PlaySave? save})
    : save = save ?? writePlayPreview {
    repository.owner = this;
    if (!repository.rows('tasks').any((t) => t['id'] == 'movie-task')) {
      (repository.snapshot!['tasks'] as List).add(
        repository.task(
          'movie-task',
          'Выбрать фильм',
          'Предложи семье фильм на вечер.',
          0,
          21,
        ),
      );
    }
    repository.addListener(_repositoryChanged);
    _reconcile();
  }

  static Future<PreviewEngagementController> load({String? design}) async {
    final controller = PreviewEngagementController(
      EngagementReviewRepository(),
    );
    try {
      final encoded = await readPlayPreview();
      if (encoded != null) controller.restore(encoded);
    } catch (_) {
      controller.storageError =
          'Пробный прогресс не удалось прочитать. Открыт новый пример.';
    }
    if (GameDesign.byId(design ?? '') != null) controller.designId = design!;
    gameDesign.value = GameDesign.byId(controller.designId)!;
    return controller;
  }

  void _repositoryChanged() {
    if (!_disposed && !busy) notifyListeners();
  }

  @override
  String get role => repository.role;
  @override
  String get currentMemberId => repository.userId;
  @override
  String get childId => 'child';
  @override
  List<PlayMember> get members => repository
      .rows('members')
      .map(
        (m) => PlayMember(
          m['id'] as String,
          m['name'] as String,
          m['role'] as String,
        ),
      )
      .toList();
  @override
  List<PlayTask> get tasks => repository
      .rows('tasks')
      .where(
        (t) =>
            t['child_id'] == 'child' &&
            !['cancelled', 'not_completed'].contains(t['status']),
      )
      .map(
        (t) => PlayTask(
          t['id'] as String,
          t['title'] as String,
          t['description'] as String? ?? '',
          t['status'] as String,
          (t['reward'] as num? ?? 0).toInt(),
          reviewNote: t['note'] as String? ?? '',
          submissionNote:
              repository
                      .rows('submissions')
                      .where((s) => s['task_id'] == t['id'])
                      .lastOrNull?['note']
                  as String? ??
              '',
        ),
      )
      .toList();

  void _reconcile() {
    state.confirmedTasks.addAll(
      tasks.where((t) => t.completed).map((t) => t.id),
    );
    state.earned.addAll(
      playItems
          .where(
            (i) => i.familyReward
                ? completedMissions > 0
                : completedCount >= i.tasks,
          )
          .map((i) => i.id),
    );
  }

  String encode() => jsonEncode({
    'schema': 1,
    'synthetic_family': true,
    'design': designId,
    'state': state.toJson(),
    'snapshot': repository.snapshot,
    'sequence': repository.sequence,
  });

  void restore(String encoded) {
    if (encoded.length > 1500000) {
      throw const FormatException('Oversized preview');
    }
    final value = jsonDecode(encoded) as Map<String, dynamic>;
    if (value['schema'] != 1 || value['synthetic_family'] != true) {
      throw const FormatException('Not an isolated preview');
    }
    final snapshot = Map<String, dynamic>.from(value['snapshot'] as Map);
    final family = snapshot['family'] as Map;
    final user = snapshot['user'] as Map;
    if (family['id'] != 'review-family' ||
        !['child', 'parent', 'father', 'relative'].contains(user['id']) ||
        !FamilyRepository.roles.contains(user['role'])) {
      throw const FormatException('Not the synthetic family');
    }
    final restored = PlayState.fromJson(
      Map<String, dynamic>.from(value['state'] as Map),
    );
    final memberIds = (snapshot['members'] as List)
        .cast<Map>()
        .map((m) => m['id'])
        .toSet();
    if (restored.missions.any(
          (m) => m.steps.any((s) => !memberIds.contains(s.owner)),
        ) ||
        restored.praise.any((p) => !memberIds.contains(p['sender']))) {
      throw const FormatException('Unknown participant');
    }
    final design = value['design'] as String;
    if (GameDesign.byId(design) == null) {
      throw const FormatException('Unknown design');
    }
    final sequence = value['sequence'] as int;
    if (sequence < 100 || sequence > 1000000) {
      throw const FormatException('Invalid sequence');
    }
    final rows = (snapshot['tasks'] as List).cast<Map>();
    if (rows.length > 500 ||
        rows.any(
          (t) =>
              t['child_id'] != 'child' ||
              t['id'] is! String ||
              t['title'] is! String ||
              t['status'] is! String,
        )) {
      throw const FormatException('Invalid synthetic tasks');
    }
    state = restored;
    designId = design;
    repository.snapshot = snapshot;
    repository.variant = user['role'] as String;
    repository.sequence = sequence;
    repository.token = 'synthetic-design-review-only';
    repository.endpoint = 'https://design-review.invalid';
  }

  Future<T> transaction<T>(Future<T> Function() action) {
    final operation = _tail.then((_) async {
      if (_disposed) throw StateError('Preview closed');
      final before = encode();
      busy = true;
      notifyListeners();
      try {
        final result = await action();
        _reconcile();
        await save(encode());
        storageError = null;
        return result;
      } catch (error) {
        restore(before);
        gameDesign.value = GameDesign.byId(designId);
        repository.notifyListeners();
        storageError = 'Изменение не сохранено. Попробуйте ещё раз.';
        rethrow;
      } finally {
        busy = false;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _change(void Function() action) =>
      transaction(() async => action());
  void _child([String? feature]) {
    if (role != 'child') throw StateError('Это действие выполняет ребёнок');
    if (feature != null && state.enabled[feature] != true) {
      throw StateError('Раздел пока выключен семьёй');
    }
  }

  void _parent() {
    if (role != 'parent') throw StateError('Это действие выполняет родитель');
  }

  PlayTask _task(String id) => tasks.firstWhere((t) => t.id == id);
  FamilyMission _mission(String id) =>
      state.missions.firstWhere((m) => m.id == id);

  Future<void> chooseDesign(String id) => _change(() {
    if (GameDesign.byId(id) == null) throw ArgumentError('Unknown design');
    designId = id;
  });
  Future<void> switchRole(String value) => _change(() {
    if (value == 'father') {
      repository.snapshot!['user'] = repository
          .rows('members')
          .firstWhere((m) => m['id'] == value);
      repository.variant = 'parent';
      return;
    }
    if (!FamilyRepository.roles.contains(value)) {
      throw ArgumentError('Unknown role');
    }
    repository.switchRole(value);
  });
  Future<void> resetExample() => transaction(() async {
    repository.reset();
    (repository.snapshot!['tasks'] as List).add(
      repository.task(
        'movie-task',
        'Выбрать фильм',
        'Предложи семье фильм на вечер.',
        0,
        21,
      ),
    );
    state = initialPreviewState();
  });
  @override
  Future<void> chooseHero(String id) => _change(() {
    _child('hero');
    if (id != 'auto' && GameDesign.byId(id) == null) {
      throw ArgumentError('Unknown hero');
    }
    state.hero = id;
  });
  @override
  Future<void> renameHero(String value) => _change(() {
    _child('hero');
    final name = value.trim();
    if (name.isEmpty ||
        name.characters.length > 18 ||
        name.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(name)) {
      throw ArgumentError('Придумай имя от 1 до 18 букв');
    }
    state.name = name;
  });
  @override
  Future<void> wear(String id) => _change(() {
    _child('hero');
    final item = playItem(id);
    if (!item.wearable || !unlocked(item)) {
      throw StateError('Предмет пока закрыт');
    }
    state.worn.contains(id) ? state.worn.remove(id) : state.worn.add(id);
  });
  @override
  Future<void> place(String? id, int slot) => _change(() {
    _child('hero');
    if (slot < 0 || slot > 2) throw ArgumentError('Unknown slot');
    if (id != null) {
      final item = playItem(id);
      if (item.wearable || !unlocked(item)) {
        throw StateError('Предмет пока закрыт');
      }
      for (var i = 0; i < 3; i++) {
        if (state.room[i] == id) state.room[i] = null;
      }
    }
    state.room[slot] = id;
  });
  @override
  Future<void> submit(String taskId, String note) => transaction(() async {
    _child();
    final task = _task(taskId);
    if (!task.canSubmit) throw StateError('Это задание уже отправлено');
    if (note.length > 300) throw ArgumentError('Слишком длинный рассказ');
    await repository.directMutate('/v1/tasks/$taskId/submissions', {
      'note': note,
    });
  });
  @override
  Future<void> review(
    String taskId, {
    required bool approve,
    String note = '',
  }) => transaction(() async {
    _parent();
    if (!_task(taskId).waiting) throw StateError('Результат уже проверен');
    if (!approve && note.trim().isEmpty) {
      throw ArgumentError('Подскажите, что исправить');
    }
    await repository.directMutate('/v1/tasks/$taskId/actions', {
      'action': approve ? 'approve' : 'return',
      'note': note.trim(),
    });
  });
  @override
  Future<void> join(String missionId) => _change(() {
    _child('family');
    _mission(missionId);
    state.joined.add(missionId);
  });
  @override
  Future<void> markOwnStep(String missionId, String stepId) => _change(() {
    final step = _mission(missionId).steps.firstWhere((s) => s.id == stepId);
    if (role == 'child' ||
        step.owner != currentMemberId ||
        step.taskId != null) {
      throw StateError('Можно отметить только своё дело');
    }
    state.adultSteps.add(step.id);
  });
  @override
  Future<void> claimAdventure() => _change(() {
    _child('adventure');
    if (adventureTasks.length != 3 ||
        !adventureTasks.every((t) => t.completed)) {
      throw StateError('Дела ещё не подтверждены');
    }
    state.adventureClaimed = true;
  });
  @override
  Future<void> chooseAdventureTasks(List<String> ids) => _change(() {
    _parent();
    if (ids.length != 3 ||
        ids.toSet().length != 3 ||
        ids.any((id) => !tasks.any((t) => t.id == id))) {
      throw ArgumentError('Выберите три разных задания');
    }
    if (ids.join('\n') == state.adventureTaskIds.join('\n')) return;
    state.adventureTaskIds = List.of(ids);
    state.adventureClaimed = false;
  });
  @override
  Future<void> claimMission(String missionId) => _change(() {
    _child('family');
    if (!state.joined.contains(missionId) ||
        !missionDone(_mission(missionId))) {
      throw StateError('Семейная миссия ещё продолжается');
    }
    state.claimedMissions.add(missionId);
  });
  @override
  Future<void> setEnabled(String feature, bool value) => _change(() {
    _parent();
    if (!state.enabled.containsKey(feature)) {
      throw ArgumentError('Unknown feature');
    }
    state.enabled[feature] = value;
  });
  @override
  Future<void> sendPraise(String missionId, String text) => _change(() {
    _mission(missionId);
    if (!praiseMessages.contains(text) ||
        (role == 'child' && text != 'Спасибо!') ||
        (role != 'child' && text == 'Спасибо!')) {
      throw ArgumentError('Unknown reaction');
    }
    if (state.praise.any(
      (p) =>
          p['mission'] == missionId &&
          p['sender'] == currentMemberId &&
          p['text'] == text,
    )) {
      return;
    }
    if (state.praise.length == 40) state.praise.removeAt(0);
    state.praise.add({
      'mission': missionId,
      'sender': currentMemberId,
      'text': text,
    });
  });
  @override
  Future<void> createMission({
    required String title,
    required String description,
    required String reward,
    required String childStep,
    required String parentStep,
    required String helperId,
    required String helperStep,
  }) => transaction(() async {
    _parent();
    if (helperId == currentMemberId ||
        !members.any((m) => m.id == helperId && m.role != 'child')) {
      throw ArgumentError('Выберите другого взрослого из семьи');
    }
    if (state.missions.length >= 20) throw StateError('Пока достаточно миссий');
    for (final (value, limit) in [
      (title, 60),
      (description, 240),
      (reward, 80),
      (childStep, 80),
      (parentStep, 80),
      (helperStep, 80),
    ]) {
      if (value.trim().isEmpty || value.length > limit) {
        throw ArgumentError('Заполните поля коротко и понятно');
      }
    }
    final before = repository.rows('tasks').map((t) => t['id']).toSet();
    await repository.directMutate('/v1/tasks', {
      'title': childStep.trim(),
      'description': description.trim(),
      'child_id': childId,
      'reward': 0,
      'penalty': 0,
      'kind': 'optional',
    });
    final task = repository
        .rows('tasks')
        .singleWhere((t) => !before.contains(t['id']));
    final id = 'mission-${repository.sequence++}';
    state.missions.add(
      FamilyMission(id, title.trim(), description.trim(), reward.trim(), [
        MissionStep(
          '$id-child',
          childId,
          childStep.trim(),
          taskId: task['id'] as String,
        ),
        MissionStep('$id-parent', currentMemberId, parentStep.trim()),
        MissionStep('$id-helper', helperId, helperStep.trim()),
      ]),
    );
  });

  @override
  void dispose() {
    _disposed = true;
    repository.removeListener(_repositoryChanged);
    repository.owner = null;
    repository.client.close();
    repository.dispose();
    super.dispose();
  }
}
