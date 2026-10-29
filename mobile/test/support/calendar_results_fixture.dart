import 'dart:convert';

import 'package:mykids_family/repository.dart';

const mathIdentity = '11111111111111111111111111111111';
const russianIdentity = '22222222222222222222222222222222';

class ResultsFixture extends FamilyRepository {
  final changes = <Map<String, dynamic>>[];
  ResultsFixture({String role = 'parent'}) {
    variant = role;
    token = 'synthetic-results-session';
    online = true;
    snapshot = {
      'user': {'id': role, 'role': role, 'review_tasks': 1, 'view_tasks': 1},
      'family': {'timezone': 'Europe/Moscow'},
      'members': [
        {'id': 'parent', 'name': 'Папа', 'role': 'parent'},
        {'id': 'relative', 'name': 'Бабушка', 'role': 'relative'},
        {'id': 'child', 'name': 'Стёпа', 'role': 'child'},
      ],
      'subjects': [
        {'id': 'old-subject', 'name': 'Прежний предмет'},
      ],
      'schedule_exceptions': <Map<String, dynamic>>[],
      'schedules': [schoolEvent()],
      'grades': <Map<String, dynamic>>[],
      'tasks': [familyTask()],
      'submissions': <Map<String, dynamic>>[],
      'programs': <Map<String, dynamic>>[],
    };
  }

  static Map<String, dynamic> schoolEvent() => {
    'id': 'school',
    'title': 'Школа',
    'date': null,
    'weekdays': '[1,2]',
    'start': '09:00',
    'end': '14:00',
    'kind': 'school',
    'color': 'blue',
    'note': 'Взять учебники',
    'active': 1,
    'activities': jsonEncode([
      {
        'id': mathIdentity,
        'title': 'Математика',
        'start': '09:00',
        'end': '10:00',
      },
      {
        'id': russianIdentity,
        'title': 'Русский язык',
        'start': '10:20',
        'end': '11:00',
      },
    ]),
  };

  static Map<String, dynamic> familyTask() => {
    'id': 'help',
    'title': 'Помочь бабушке',
    'description': 'Полить цветы',
    'due_at': '2026-10-12T17:00:00Z',
    'planned_start': null,
    'planned_end': null,
    'status': 'assigned',
    'subject_id': null,
    'author_id': 'relative',
    'reviewer_id': 'relative',
    'reward': 70,
    'penalty': 0,
    'financial_approved': 1,
    'require_photo': 0,
    'version': 3,
  };

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    changes.add({
      'path': path,
      'method': method,
      'body': Map<String, dynamic>.from(body),
      'offline': offlineSubmission,
    });
    if (path == '/v1/grades') {
      snapshot!['grades'] = [
        {'id': 'saved-grade', ...body, 'event_title': 'Математика'},
      ];
    }
    if (path.endsWith('/submissions')) {
      (snapshot!['tasks'] as List).first['status'] = 'submitted';
    }
    if (body['action'] == 'complete') {
      (snapshot!['tasks'] as List).first['status'] = 'completed';
    }
    notifyListeners();
    return {'ok': true};
  }
}
