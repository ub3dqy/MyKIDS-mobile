import 'dart:convert';
import 'dart:io';

import 'repository.dart';
import 'schedule.dart';

/// Deliberately separate from the production entry point. Every value is a
/// synthetic example; no credentials, server or persistent family are used.
class DesignReviewRepository extends FamilyRepository {
  static const reviewInvitation = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
  int sequence = 100;
  final attachments = <String, File>{};
  final messages = <String, List<Map<String, dynamic>>>{};
  DesignReviewRepository() {
    endpoint = 'https://design-review.invalid';
    reset();
  }

  String get today => dateOnly(familyClock(snapshot));
  String instant(int hour, [int minute = 0]) =>
      '${today}T${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00+03:00';
  Map<String, dynamic> member(String id, String name, String role) => {
    'id': id,
    'name': name,
    'role': role,
    'active': 1,
    'create_tasks': 1,
    'view_tasks': 1,
    'review_tasks': 1,
  };

  void reset() {
    token = 'synthetic-design-review-only';
    variant = 'child';
    online = true;
    final day = dateOnly(DateTime.now());
    snapshot = {
      'user': member('child', 'Саша', 'child'),
      'family': {
        'id': 'review-family',
        'name': 'Наша семья',
        'timezone': 'Europe/Moscow',
        'quiet_start': '22:00',
        'quiet_end': '07:00',
        'day_start': '07:00',
        'day_end': '22:00',
      },
      'server_time': DateTime.now().toUtc().toIso8601String(),
      'balance': {'total': 125, 'available': 125, 'reserved': 0},
      'members': [
        member('parent', 'Мама', 'parent'),
        member('father', 'Папа', 'parent'),
        member('child', 'Саша', 'child'),
        member('relative', 'Бабушка', 'relative'),
      ],
      'subjects': [
        {'id': 'math', 'name': 'Математика'},
        {'id': 'russian', 'name': 'Русский язык'},
      ],
      'programs': [
        {
          'id': 'reading-program',
          'title': 'Читаю каждый день',
          'description': 'Маленькие шаги к любимым книгам',
        },
      ],
      'tasks': <Map<String, dynamic>>[],
      'task_recurrences': <Map<String, dynamic>>[],
      'submissions': <Map<String, dynamic>>[],
      'schedules': [
        {
          'id': 'school',
          'title': 'Школа',
          'weekdays': '[1,2,3,4,5,6,7]',
          'date': null,
          'start': '08:30',
          'end': '12:30',
          'kind': 'school',
          'color': 'blue',
          'note': 'Учебники, тетради и пенал',
          'place': 'Школа',
          'active': 1,
          'reminder_minutes': 30,
          'grade_subjects': 1,
          'activities': jsonEncode([
            {
              'id': '11111111111111111111111111111111',
              'title': 'Математика',
              'start': '08:30',
              'end': '09:15',
            },
            {
              'id': '22222222222222222222222222222222',
              'title': 'Русский язык',
              'start': '09:30',
              'end': '10:15',
            },
            {
              'id': '33333333333333333333333333333333',
              'title': 'Чтение',
              'start': '10:30',
              'end': '11:15',
            },
            {
              'id': '44444444444444444444444444444444',
              'title': 'Физкультура',
              'start': '11:30',
              'end': '12:15',
            },
          ]),
        },
        {
          'id': 'swim',
          'title': 'Плавание',
          'weekdays': '[1,2,3,4,5,6,7]',
          'date': null,
          'start': '16:00',
          'end': '16:45',
          'kind': 'extra',
          'color': 'teal',
          'note': 'Возьми шапочку, очки, полотенце и тапочки',
          'place': 'Бассейн',
          'active': 1,
          'reminder_minutes': 45,
          'activities': '[]',
        },
      ],
      'schedule_exceptions': <Map<String, dynamic>>[],
      'grades': [
        {
          'id': 'grade-math',
          'child_id': 'child',
          'subject_id': 'math',
          'value': 5,
          'grade': 5,
          'date': day,
          'note': 'Отличная работа!',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      'grade_rules': [
        {'grade': 5, 'amount': 15},
        {'grade': 4, 'amount': 5},
        {'grade': 3, 'amount': 0},
        {'grade': 2, 'amount': -5},
      ],
      'rewards': [
        {
          'id': 'cinema',
          'title': 'Семейный поход в кино',
          'description': 'Выбираем фильм вместе',
          'price': 200,
          'available': 1,
          'version': 1,
        },
        {
          'id': 'picnic',
          'title': 'Пикник всей семьёй',
          'description': 'Отличный день на свежем воздухе',
          'price': 100,
          'available': 1,
          'version': 1,
        },
        {
          'id': 'creative',
          'title': 'Набор для творчества',
          'description': 'Для твоих новых идей',
          'price': 300,
          'available': 1,
          'version': 1,
        },
      ],
      'goal': {'reward_id': 'cinema'},
      'ledger': [
        {
          'id': 'saved',
          'child_id': 'child',
          'source_type': 'task',
          'source_id': 'past',
          'requested': 120,
          'actual': 120,
          'reason': 'Твои прошлые старания',
          'created_at': DateTime.now()
              .subtract(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        },
        {
          'id': 'flowers-earned',
          'child_id': 'child',
          'source_type': 'task',
          'source_id': 'flowers',
          'requested': 5,
          'actual': 5,
          'reason': 'Полить цветы',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      'redemptions': <Map<String, dynamic>>[],
      'penalties': <Map<String, dynamic>>[],
      'calls': <Map<String, dynamic>>[
        {
          'id': 'past-call-mom',
          'room_id': 'parent',
          'caller_id': 'parent',
          'status': 'ended',
          'member_status': 'left',
          'video': 0,
          'created_at': '${day}T12:00:00+03:00',
          'ended_at': '${day}T12:03:00+03:00',
        },
        {
          'id': 'past-call-dad',
          'room_id': 'father',
          'caller_id': 'child',
          'status': 'ended',
          'member_status': 'left',
          'video': 1,
          'created_at': '${day}T11:00:00+03:00',
          'ended_at': '${day}T11:02:00+03:00',
        },
      ],
      'rooms': <Map<String, dynamic>>[],
      'assistant_rules': [
        {
          'id': 'pool-rule',
          'title': 'Перед плаванием',
          'keywords': ['плавание', 'бассейн'],
          'message': 'Приготовь шапочку, очки и полотенце',
          'minutes_before': 45,
          'enabled': true,
        },
      ],
      'history': <Map<String, dynamic>>[],
    };
    snapshot!['tasks'] = [
      task(
        'read',
        'Прочитать 10 страниц',
        'Выбери любимую книгу и расскажи, что тебе понравилось.',
        20,
        19,
      ),
      task(
        'bag',
        'Собрать рюкзак',
        'Посмотри уроки на завтра. Положи учебники, тетради и пенал.',
        10,
        20,
      ),
      {
        ...task(
          'flowers',
          'Полить цветы',
          'Немного воды для домашних цветов.',
          5,
          15,
        ),
        'status': 'completed',
        'awarded_reward': 5,
      },
    ];
    messages.clear();
    for (final id in ['parent', 'father', 'family']) {
      final name = id == 'parent'
          ? 'Мама'
          : id == 'father'
          ? 'Папа'
          : 'Наша семья';
      final text = id == 'parent'
          ? 'Не забудь шапочку для бассейна 💙'
          : id == 'father'
          ? 'Как прошёл твой день?'
          : 'Всем хорошего дня!';
      final list = <Map<String, dynamic>>[
        {
          'id': 'message-$id-1',
          'room_id': id,
          'sender_id': id == 'family' ? 'relative' : id,
          'sender_name': id == 'family' ? 'Бабушка' : name,
          'kind': 'text',
          'text': text,
          'attachment_id': null,
          'created_at': instant(15, 35),
          'receipts': <Map<String, dynamic>>[],
        },
        {
          'id': 'message-$id-2',
          'room_id': id,
          'sender_id': 'child',
          'sender_name': 'Саша',
          'kind': 'text',
          'text': 'Хорошо! Уже собираюсь.',
          'attachment_id': null,
          'created_at': instant(15, 36),
          'receipts': [
            {'user_id': id, 'state': 'read', 'status': 'read'},
          ],
        },
      ];
      messages[id] = list;
      (snapshot!['rooms'] as List).add({
        'id': id,
        'kind': id == 'family' ? 'family' : 'private',
        'title': name,
        'name': name,
        'contact': id == 'family' ? null : member(id, name, 'parent'),
        'can_call': id != 'family',
        'unread_count': id == 'parent' ? 1 : 0,
        'last_message': list.last,
      });
    }
    notifyListeners();
  }

  Map<String, dynamic> task(
    String id,
    String title,
    String description,
    int reward,
    int hour,
  ) => {
    'id': id,
    'child_id': 'child',
    'title': title,
    'description': description,
    'due_at': instant(hour),
    'planned_start': null,
    'planned_end': null,
    'reward': reward,
    'penalty': 0,
    'status': 'assigned',
    'author_id': 'parent',
    'reviewer_id': 'parent',
    'financial_approved': 1,
    'require_photo': 0,
    'min_photos': 0,
    'note': '',
    'version': 1,
    'kind': 'optional',
    'program_id': id == 'read' ? 'reading-program' : null,
    'subject_id': null,
    'recurrence_id': null,
  };

  void switchRole(String role) {
    if (!FamilyRepository.roles.contains(role)) return;
    variant = role;
    snapshot!['user'] = rows('members').firstWhere((m) => m['role'] == role);
    generation++;
    notifyListeners();
  }

  void setConnection(bool value) {
    online = value;
    notifyListeners();
  }

  void showNegative() {
    snapshot!['balance'] = {'total': -15, 'reserved': 0, 'available': -15};
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> upload(
    String path,
    String contextType,
    String contextId,
  ) async {
    final id = 'example-photo-${sequence++}';
    attachments[id] = File(path);
    return {'id': id, 'mime': 'image/jpeg', 'filename': 'Пример фотографии'};
  }

  @override
  Future<File> attachment(String id) async {
    final file = attachments[id];
    if (file == null) throw ApiFailure(404, 'Фотография не добавлена');
    return file;
  }

  void showEmpty() {
    for (final key in [
      'tasks',
      'schedules',
      'grades',
      'ledger',
      'rewards',
      'rooms',
      'submissions',
      'redemptions',
      'calls',
    ]) {
      snapshot![key] = <Map<String, dynamic>>[];
    }
    snapshot!['balance'] = {'total': 0, 'reserved': 0, 'available': 0};
    snapshot!['goal'] = null;
    notifyListeners();
  }

  @override
  Future<void> initialize([String? setupRole]) async {}
  @override
  Future<void> sync() async {}
  @override
  Future<void> reconnect() async {
    setConnection(true);
  }

  @override
  Future<List<Map<String, Object?>>> pending() async => [];
  @override
  Future<void> selectRole(String value) async {
    variant = value;
    notifyListeners();
  }

  @override
  Future<void> logout({bool remote = true}) async {
    token = null;
    snapshot = null;
    generation++;
    notifyListeners();
  }

  @override
  Future<void> login(
    String server,
    String username,
    String password, {
    String? invite,
    String? name,
  }) async {
    reset();
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/messages') && method == 'GET') {
      return {
        'messages': messages[path.split('/')[3]] ?? [],
        'has_more': false,
      };
    }
    if (path.endsWith('/receipt')) return {'ok': true};
    if (path == '/v1/snapshot') return snapshot!;
    if (path == '/v1/invites') {
      return {'token': reviewInvitation, 'role': body?['role']};
    }
    if (path.contains('/assistant')) {
      return {'rules': snapshot!['assistant_rules']};
    }
    if (path.contains('/math-answers')) {
      return {
        'available': false,
        'message': 'Для этого примера нет готовых ответов.',
      };
    }
    if (method != 'GET') return mutate(path, body ?? {}, method: method);
    throw ApiFailure(
      404,
      'В примере нет данных для этого запроса. Это не ошибка оформления.',
    );
  }

  void credit(int amount, String reason, String sourceId) {
    final balance = snapshot!['balance'] as Map;
    balance['total'] = (balance['total'] as num).toInt() + amount;
    balance['available'] =
        (balance['total'] as num).toInt() -
        (balance['reserved'] as num).toInt();
    (snapshot!['ledger'] as List).add({
      'id': 'ledger-${sequence++}',
      'child_id': 'child',
      'source_type': 'task',
      'source_id': sourceId,
      'actual': amount,
      'requested': amount,
      'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (!online) {
      throw ApiFailure(
        503,
        'Нет интернета. Вариант показывает сохранённые данные.',
      );
    }
    final parts = path.split('/');
    final collection = parts.length > 2 ? parts[2] : '';
    final id = parts.length > 3 ? parts[3] : null;
    Map<String, dynamic>? item(String name, String? id) =>
        rows(name).where((r) => r['id'] == id).firstOrNull;
    void replace(String name, Map<String, dynamic> value) {
      snapshot![name] = [
        for (final row in rows(name))
          if (row['id'] == value['id']) value else row,
      ];
    }

    var result = <String, dynamic>{
      'ok': true,
      'message': 'Сохранено в примере',
    };
    if (collection == 'rooms' && parts.last == 'messages') {
      final entry = {
        'id': 'message-${sequence++}',
        'room_id': id,
        'sender_id': userId,
        'sender_name': snapshot!['user']['name'],
        'text': body['text'] ?? '',
        'kind': body['kind'] ?? 'text',
        'attachment_id': body['attachment_id'],
        'attachment_mime': body['attachment_mime'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'receipts': <Map<String, dynamic>>[],
      };
      messages.putIfAbsent(id!, () => []).add(entry);
      final room = item('rooms', id);
      if (room != null) replace('rooms', {...room, 'last_message': entry});
      result = entry;
    } else if (collection == 'rooms' && parts.last == 'calls') {
      result = {
        'id': 'review-call-${sequence++}',
        'room_id': id,
        'video': body['video'] ?? false,
      };
    } else if (collection == 'messages' && parts.last == 'receipt') {
      result = {'ok': true};
    } else if (collection == 'tasks' && parts.last == 'photos') {
      final submission = item('submissions', body['submission_id'] as String?);
      if (submission == null) throw ApiFailure(404, 'Результат не найден');
      final ids = (jsonDecode(submission['attachment_ids'] as String) as List)
          .cast<String>();
      for (final path in files) {
        ids.add((await upload(path, 'task', id!))['id'] as String);
      }
      replace('submissions', {
        ...submission,
        'attachment_ids': jsonEncode(ids),
      });
      result = {
        'accepted': true,
        'message': 'Фотографии добавлены к результату',
      };
    } else if (collection == 'tasks' && parts.last == 'submissions') {
      final task = item('tasks', id);
      if (task == null) throw ApiFailure(404, 'Задание не найдено');
      final ids = <String>[
        ...(body['attachment_ids'] as List? ?? []).cast<String>(),
      ];
      for (final path in files) {
        ids.add((await upload(path, 'task', id!))['id'] as String);
      }
      final submission = {
        'id': 'submission-${sequence++}',
        'task_id': id,
        'child_id': 'child',
        'comment': body['note'] ?? body['comment'] ?? '',
        'note': body['note'] ?? body['comment'] ?? '',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'marked_at': DateTime.now().toUtc().toIso8601String(),
        'received_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
        'accepted': 1,
        'task_version': task['version'],
        'attachment_ids': jsonEncode(ids),
        'photos': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
      };
      (snapshot!['submissions'] as List).add(submission);
      replace('tasks', {
        ...task,
        'status': 'submitted',
        'version': (task['version'] as int) + 1,
      });
      result = {'accepted': true, 'message': 'Результат отправлен на проверку'};
    } else if (collection == 'tasks' && parts.last == 'actions') {
      final task = item('tasks', id);
      if (task == null) throw ApiFailure(404, 'Задание не найдено');
      final action = body['action'];
      if (action == 'approve' || action == 'complete') {
        if (task['status'] != 'completed') {
          credit(
            (task['reward'] as num).toInt(),
            'Выполнено: ${task['title']}',
            id!,
          );
        }
        replace('tasks', {
          ...task,
          'status': 'completed',
          'awarded_reward': task['reward'],
          'version': (task['version'] as int) + 1,
        });
      } else if (action == 'return') {
        replace('tasks', {
          ...task,
          'status': 'returned',
          'note': body['note'] ?? 'Попробуй ещё раз',
        });
      } else if (action == 'approve_financial') {
        replace('tasks', {...task, 'financial_approved': 1});
      } else if (action == 'cancel' || action == 'stop_repeat') {
        replace('tasks', {...task, 'status': 'cancelled'});
      } else if (action == 'not_completed') {
        replace('tasks', {...task, 'status': 'not_completed'});
      } else {
        throw ApiFailure(400, 'Для примера это действие пока недоступно');
      }
    } else if (collection == 'goal') {
      snapshot!['goal'] = body;
    } else if (collection == 'redemptions' && id == null) {
      final reward = item('rewards', body['reward_id'] as String?);
      final amount = (body['amount'] ?? reward?['price'] ?? 0) as num;
      final balance = snapshot!['balance'] as Map;
      if (amount <= 0 || amount > (balance['available'] as num)) {
        throw ApiFailure(400, 'Для этого желания пока не хватает монет');
      }
      balance['reserved'] = (balance['reserved'] as num) + amount;
      balance['available'] =
          (balance['total'] as num) - (balance['reserved'] as num);
      (snapshot!['redemptions'] as List).add({
        'id': 'request-${sequence++}',
        'child_id': 'child',
        'reward_id': reward?['id'],
        'title': reward?['title'] ?? 'Обмен монет на рубли',
        'amount': amount.toInt(),
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else if (collection == 'redemptions' && parts.last == 'actions') {
      final request = item('redemptions', id);
      if (request == null) throw ApiFailure(404, 'Заявка не найдена');
      final action = body['action'];
      if (action == 'claim') {
        replace('redemptions', {
          ...request,
          'status': 'claimed',
          'claimed_by': userId,
        });
      } else if (action == 'release') {
        replace('redemptions', {
          ...request,
          'status': 'pending',
          'claimed_by': null,
        });
      } else if (action == 'reject' || action == 'confirm') {
        if (['completed', 'rejected'].contains(request['status'])) {
          return {'ok': true, 'message': 'Эта просьба уже обработана'};
        }
        final balance = snapshot!['balance'] as Map;
        balance['reserved'] =
            (balance['reserved'] as num) - (request['amount'] as num);
        if (action == 'confirm') {
          credit(
            -(request['amount'] as num).toInt(),
            'Получено: ${request['title']}',
            id!,
          );
        }
        balance['available'] =
            (balance['total'] as num) - (balance['reserved'] as num);
        replace('redemptions', {
          ...request,
          'status': action == 'confirm' ? 'completed' : 'rejected',
        });
      }
    } else if (collection == 'family') {
      snapshot!['family'] = {...snapshot!['family'] as Map, ...body};
    } else if (collection == 'grade-rules') {
      snapshot!['grade_rules'] = [
        for (final e in (body['amounts'] as Map).entries)
          {'grade': e.key, 'amount': e.value},
      ];
    } else if (collection == 'invites') {
      result = {'token': reviewInvitation, 'role': body['role']};
    } else {
      final mapped = {
        'events': 'schedules',
        'schedules': 'schedules',
        'tasks': 'tasks',
        'rewards': 'rewards',
        'grades': 'grades',
        'programs': 'programs',
        'assistant': 'assistant_rules',
        'members': 'members',
      }[collection];
      if (mapped == null) {
        throw ApiFailure(
          400,
          'Для этого запроса нет примера. Оформление доступно для просмотра.',
        );
      }
      if (method == 'DELETE') {
        snapshot![mapped] = rows(mapped).where((r) => r['id'] != id).toList();
      } else if (id != null) {
        final old = item(mapped, id);
        if (old == null) throw ApiFailure(404, 'Запись не найдена');
        replace(mapped, {
          ...old,
          ...body,
          'version': (old['version'] as int? ?? 0) + 1,
        });
      } else {
        final newId = 'example-${sequence++}';
        final entry = mapped == 'tasks'
            ? {
                ...task(
                  newId,
                  body['title'] as String? ?? 'Новое задание',
                  body['description'] as String? ?? '',
                  (body['reward'] as num? ?? 0).toInt(),
                  19,
                ),
                ...body,
                'id': newId,
              }
            : {'id': newId, 'version': 1, 'active': 1, 'available': 1, ...body};
        (snapshot![mapped] as List).add(entry);
        result = {...result, 'id': newId};
      }
    }
    notifyListeners();
    return result;
  }
}
