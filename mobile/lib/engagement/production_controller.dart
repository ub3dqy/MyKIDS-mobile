import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../repository.dart';
import 'action_cancelled.dart';
import 'engagement_model.dart';

typedef PlayPhotos = Future<List<String>?> Function(Map<String, dynamic> task);
typedef PlayReview = Future<void> Function(String taskId);

/// Uses the ordinary authenticated snapshot, cache and durable command queue.
/// No preview data, role selection or local unlock decisions enter this adapter.
class ProductionEngagementController extends EngagementController {
  final FamilyRepository repository;
  final PlayPhotos? selectPhotos;
  final PlayReview? showDetailedReview;
  PlayState _state = PlayState();
  Map<String, dynamic>? _entry;
  Object? _source;
  String _session = '';
  String get _identity =>
      '${repository.endpoint}|${repository.sessionTag}|${repository.generation}|$currentMemberId';
  Set<String> _pendingSubmissions = {};
  final Set<String> _reportedQueueFailures = {};
  Future<void>? _pendingRead;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;
  bool _working = false, _queuedProfile = false;
  @override
  bool get busy => _working || _queuedProfile;
  @override
  String? storageError;

  ProductionEngagementController(
    this.repository, {
    this.selectPhotos,
    this.showDetailedReview,
  }) {
    repository.addListener(_changed);
    _readSnapshot();
    unawaited(_refreshPending());
  }

  @override
  PlayState get state => _state;
  @override
  String get role => repository.role;
  @override
  String get currentMemberId => repository.userId;
  @override
  Object get accessIdentity => _identity;
  @override
  String get childId => role == 'child'
      ? currentMemberId
      : repository
                    .rows('members')
                    .where((m) => m['role'] == 'child' && m['active'] != 0)
                    .firstOrNull?['id']
                as String? ??
            '';
  @override
  List<PlayMember> get members => repository
      .rows('members')
      .where((m) => m['active'] != 0)
      .map(
        (m) => PlayMember(
          m['id'] as String,
          m['name'] as String,
          m['role'] as String,
        ),
      )
      .toList();
  @override
  int get completedCount =>
      (_entry?['confirmed_total'] as num?)?.toInt() ??
      _state.confirmedTasks.length;

  void _readSnapshot() {
    final session = _identity;
    if (session != _session) {
      _session = session;
      _source = null;
      _entry = null;
      _state = PlayState();
      _pendingSubmissions = {};
      _reportedQueueFailures.clear();
      _queuedProfile = false;
      storageError = null;
    }
    if (identical(_source, repository.snapshot)) return;
    _source = repository.snapshot;
    _entry = repository
        .rows('engagement')
        .where((e) => e['child_id'] == childId)
        .firstOrNull;
    try {
      _state = _entry == null
          ? PlayState()
          : PlayState.fromJson(
              Map<String, dynamic>.from(_entry!['state'] as Map),
            );
    } catch (_) {
      _entry = null;
      _state = PlayState();
      storageError = 'Не удалось прочитать прогресс. Обнови данные при подключении к интернету.';
    }
  }

  void _changed() {
    if (_disposed) return;
    _readSnapshot();
    unawaited(_refreshPending());
    notifyListeners();
  }

  Future<void> _refreshPending() {
    if (_pendingRead != null) return _pendingRead!;
    final operation = _loadPending();
    _pendingRead = operation;
    return operation.whenComplete(() {
      if (identical(_pendingRead, operation)) _pendingRead = null;
    });
  }

  Future<void> _loadPending() async {
    if (_disposed || repository.db == null || !repository.signedIn) return;
    final session = _session;
    try {
      final rows = await repository.pending();
      if (_disposed || session != _session || session != _identity) return;
      final pending = <String>{};
      var pendingProfile = false;
      String? pendingFailure;
      for (final row in rows) {
        if (row['path'] == '/v1/engagement/$childId/commands') {
          if (row['state'] == 'pending') {
            pendingProfile = true;
          } else if (row['state'] == 'failed' && _newQueueFailure(row)) {
            pendingFailure =
                row['error'] as String? ??
                'Прогресс изменился. Повтори действие после обновления данных.';
          }
          continue;
        }
        final match = RegExp(r'^/v1/tasks/([^/]+)/submissions$')
            .firstMatch(row['path'] as String);
        if (match == null) continue;
        if (row['state'] == 'pending') {
          pending.add(match.group(1)!);
        } else if (row['state'] == 'failed' && _newQueueFailure(row)) {
          pendingFailure =
              row['error'] as String? ??
              'Семья изменила задание. Открой его заново.';
        }
      }
      final wasQueued = _queuedProfile || _pendingSubmissions.isNotEmpty;
      final nextMessage =
          pendingFailure ??
          (pendingProfile
              ? 'Изменения сохранены на телефоне. Дождись подключения к интернету.'
              : pending.isNotEmpty
              ? 'Результат сохранён на телефоне. Отправим семье после подключения.'
              : wasQueued
              ? null
              : storageError);
      if (!setEquals(_pendingSubmissions, pending) ||
          _queuedProfile != pendingProfile ||
          storageError != nextMessage) {
        _pendingSubmissions = pending;
        _queuedProfile = pendingProfile;
        storageError = nextMessage;
        notifyListeners();
      }
    } catch (_) {
      // A cache read must never erase a queued result or unlock an item.
    }
  }

  bool _newQueueFailure(Map<String, dynamic> row) => _reportedQueueFailures.add(
    row['id'] as String? ??
        jsonEncode([row['path'], row['body'], row['error']]),
  );

  @override
  List<PlayTask> get tasks {
    final rows = <String, Map<String, dynamic>>{};
    for (final task in (_entry?['mission_tasks'] as List? ?? [])) {
      final row = Map<String, dynamic>.from(task as Map);
      rows[row['id'] as String] = row;
    }
    for (final task in repository.rows('tasks')) {
      if (task['child_id'] == childId) rows[task['id'] as String] = task;
    }
    return rows.values
        .where((t) => !['cancelled', 'not_completed'].contains(t['status']))
        .map((t) {
          final status =
              _pendingSubmissions.contains(t['id']) &&
                  ['assigned', 'returned'].contains(t['status'])
              ? 'submitted'
              : t['status'] as String;
          final submission = repository
              .rows('submissions')
              .where((s) => s['task_id'] == t['id'] && s['accepted'] != 0)
              .lastOrNull;
          return PlayTask(
            t['id'] as String,
            t['title'] as String,
            t['description'] as String? ?? '',
            status,
            ((t['status'] == 'completed'
                            ? t['awarded_reward'] ?? t['reward']
                            : t['reward'])
                        as num? ??
                    0)
                .toInt(),
            reviewNote: t['note'] as String? ?? '',
            submissionNote: submission?['note'] as String? ?? '',
          );
        })
        .toList();
  }

  Future<void> _run(Future<void> Function(String session) action) {
    final requestedSession = _session;
    final operation = _tail.then((_) async {
      _guard(requestedSession);
      _working = true;
      storageError = null;
      notifyListeners();
      try {
        await action(requestedSession);
        _guard(requestedSession);
        _readSnapshot();
      } on PlayActionCancelled {
        rethrow;
      } catch (error) {
        if (!_disposed && _session == requestedSession) {
          storageError = error is ApiFailure
              ? error.message
              : 'Не получилось сохранить. Попробуй ещё раз.';
        }
        if (error is ApiFailure &&
            error.status == 409 &&
            repository.signedIn &&
            _session == requestedSession) {
          try {
            await repository.refreshAfterChange();
          } catch (_) {
            /* Keep the original error. */
          }
        }
        rethrow;
      } finally {
        _working = false;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  void _guard(String session) {
    if (_disposed ||
        !repository.signedIn ||
        _session != session ||
        _identity != session) {
      throw ApiFailure(
        401,
        'Семейный доступ изменён. Открой приложение заново.',
      );
    }
  }

  Future<void> _command(String action, Map<String, dynamic> values) => _run((
    session,
  ) async {
    if (_queuedProfile) {
      throw ApiFailure(
        409,
        'Предыдущее изменение ещё отправляется. Дождись подключения.',
      );
    }
    if (_entry == null || childId.isEmpty) {
      throw ApiFailure(
        409,
        childId.isEmpty
            ? 'Сначала подключите ребёнка к семье.'
            : 'Подключись к интернету, чтобы получить прогресс.',
      );
    }
    final result = await _sendQueued('/v1/engagement/$childId/commands', {
      'action': action,
      'expected_revision': _entry!['revision'],
      ...values,
    });
    _guard(session);
    if (result['queued'] == true) {
      _queuedProfile = true;
      storageError =
          'Изменение сохранено для отправки. Дождись подключения к интернету.';
    }
  });

  Future<Map<String, dynamic>> _sendQueued(
    String path,
    Map<String, dynamic> body, {
    bool submission = false,
    List<String> files = const [],
  }) async {
    final session = _session;
    try {
      return await repository.mutate(
        path,
        body,
        offlineSubmission: true,
        files: files,
      );
    } on ApiFailure catch (error) {
      if (error.status < 500 || repository.db == null) rethrow;
      final pending = await repository.pending();
      _guard(session);
      for (final row in pending) {
        if (row['path'] != path || row['state'] != 'pending') continue;
        final raw = row['body'];
        if (raw == jsonEncode(body)) return {'queued': true};
        // Upload retries can already have persisted attachment IDs. The exact
        // task version and client timestamp still identify this submission.
        if (submission && raw is String) {
          final saved = jsonDecode(raw) as Map<String, dynamic>;
          if (saved['marked_at'] == body['marked_at'] &&
              saved['task_version'] == body['task_version'] &&
              saved['note'] == body['note']) {
            return {'queued': true};
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> chooseHero(String id) => _command('choose_hero', {'hero': id});
  @override
  Future<void> renameHero(String value) =>
      _command('rename_hero', {'name': value.trim()});
  @override
  Future<void> wear(String id) =>
      _command('wear', {'item': id, 'worn': !state.worn.contains(id)});
  @override
  Future<void> place(String? id, int slot) =>
      _command('place', {'item': id, 'slot': slot});
  @override
  Future<void> chooseAdventureTasks(List<String> ids) =>
      _command('set_adventure', {'task_ids': List.of(ids)});
  @override
  Future<void> claimAdventure() => _command('claim_adventure', {
    'task_ids': List.of(state.adventureTaskIds),
  });
  @override
  Future<void> join(String missionId) =>
      _command('join_mission', {'mission_id': missionId});
  @override
  Future<void> markOwnStep(String missionId, String stepId) =>
      _command('complete_step', {'mission_id': missionId, 'step_id': stepId});
  @override
  Future<void> claimMission(String missionId) =>
      _command('claim_mission', {'mission_id': missionId});
  @override
  Future<void> setEnabled(String feature, bool value) =>
      _command('set_enabled', {'feature': feature, 'value': value});
  @override
  Future<void> sendPraise(String missionId, String text) =>
      _command('praise', {'mission_id': missionId, 'text': text});
  @override
  Future<void> createMission({
    required String title,
    required String description,
    required String reward,
    required String childStep,
    required String parentStep,
    required String helperId,
    required String helperStep,
  }) => _command('create_mission', {
    'title': title,
    'description': description,
    'reward': reward,
    'child_step': childStep,
    'parent_step': parentStep,
    'helper_id': helperId,
    'helper_step': helperStep,
  });

  Map<String, dynamic> _task(String id) =>
      repository
          .rows('tasks')
          .where((t) => t['id'] == id && t['child_id'] == childId)
          .firstOrNull ??
      (throw ApiFailure(404, 'Задание больше недоступно. Обнови данные.'));

  @override
  Future<void> submit(String taskId, String note) => _run((session) async {
    if (role != 'child') throw ApiFailure(403, 'Результат отправляет ребёнок.');
    await _refreshPending();
    if (_pendingSubmissions.contains(taskId)) {
      throw ApiFailure(
        409,
        'Результат уже сохранён для отправки. Дождись подключения.',
      );
    }
    final task = Map<String, dynamic>.from(_task(taskId));
    if (!['assigned', 'returned'].contains(task['status'])) {
      throw ApiFailure(409, 'Результат уже отправлен. Обнови данные.');
    }
    final photos = <String>[];
    if (task['require_photo'] == 1) {
      final selected = await selectPhotos?.call(task);
      _guard(session);
      if (selected == null) throw const PlayActionCancelled();
      try {
        for (final path in selected) {
          photos.add(await repository.keepFile(path));
          _guard(session);
        }
      } catch (_) {
        // These are only fresh owned copies; no queue command references them.
        // Original gallery images and already queued photos are never removed.
        for (final path in photos) {
          try {
            await File(path).delete();
          } on FileSystemException {
            /* Already removed on session change. */
          }
        }
        rethrow;
      }
    }
    final result = await _sendQueued(
      '/v1/tasks/$taskId/submissions',
      {
        'note': note,
        'attachment_ids': <String>[],
        'task_version': task['version'],
        'marked_at': DateTime.now().toUtc().toIso8601String(),
      },
      submission: true,
      files: photos,
    );
    _guard(session);
    if (result['queued'] == true) {
      _pendingSubmissions.add(taskId);
      storageError =
          'Результат сохранён на телефоне. Отправим семье после подключения.';
    } else if (result['accepted'] != true) {
      throw ApiFailure(
        409,
        result['message'] as String? ??
            'Задание изменилось. Результат сохранён для родителя.',
      );
    }
  });

  @override
  Future<void> review(
    String taskId, {
    required bool approve,
    String note = '',
  }) => _run((session) async {
    if (role != 'parent') throw ApiFailure(403, 'Дело подтверждает родитель.');
    final task = Map<String, dynamic>.from(_task(taskId));
    final attachments = repository
        .rows('submissions')
        .where((s) => s['task_id'] == taskId && s['accepted'] != 0)
        .lastOrNull?['attachment_ids'];
    final hasPhotos = attachments is List
        ? attachments.isNotEmpty
        : attachments is String &&
              attachments.trim().isNotEmpty &&
              attachments.trim() != '[]';
    if (approve &&
        (task['require_photo'] == 1 ||
            task['reward_options'] != null ||
            hasPhotos)) {
      if (showDetailedReview == null) {
        throw ApiFailure(
          409,
          'Открой результат в разделе заданий, чтобы проверить фотографии и награду.',
        );
      }
      await showDetailedReview!(taskId);
      _guard(session);
      if (_task(taskId)['status'] != 'completed') {
        throw const PlayActionCancelled();
      }
      return;
    }
    await repository.mutate('/v1/tasks/$taskId/actions', {
      'action': approve ? 'approve' : 'return',
      'note': note,
      'task_version': task['version'],
    });
  });

  @override
  void dispose() {
    _disposed = true;
    repository.removeListener(_changed);
    super.dispose();
  }
}
