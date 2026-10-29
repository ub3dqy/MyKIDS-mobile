import 'dart:io';

import 'package:mykids_family/repository.dart';

/// Artificial conversations only. No HTTP requests or family accounts.
class MessengerFixture extends FamilyRepository {
  final sent = <String>[];
  bool failSend = false;
  bool earlierLoaded = false;
  int uploadedBytes = 0;
  String? openedRoom;
  final history = <Map<String, dynamic>>[
    {
      'id': 'hello',
      'sender_id': 'parent',
      'text': 'Как прошёл день?',
      'created_at': '2026-10-12T10:00:00Z',
      'receipts': <Map<String, dynamic>>[],
    },
    {
      'id': 'reply',
      'sender_id': 'child',
      'text': 'Хорошо! Уже дома.',
      'created_at': '2026-10-12T10:01:00Z',
      'receipts': [
        {
          'user_id': 'parent',
          'read_at': '2026-10-12T10:01:00Z',
          'delivered_at': '2026-10-12T10:01:00Z',
        },
      ],
    },
    {
      'id': 'voice',
      'sender_id': 'parent',
      'text': '',
      'attachment_id': 'voice-file',
      'attachment_mime': 'audio/wav',
      'created_at': '2026-10-12T10:02:00Z',
      'receipts': <Map<String, dynamic>>[],
    },
    {
      'id': 'later',
      'sender_id': 'parent',
      'text': 'Отлично. Скоро увидимся!',
      'created_at': '2026-10-12T10:03:00Z',
      'receipts': <Map<String, dynamic>>[],
    },
  ];
  MessengerFixture({String role = 'child'}) {
    variant = role;
    token = 'synthetic-messenger-session';
    online = true;
    snapshot = {
      'user': {'id': 'child', 'role': role, 'name': 'Проверка'},
      'family': {
        'timezone': 'Europe/Moscow',
        'day_start': '07:00',
        'day_end': '22:00',
        'quiet_start': '00:00',
        'quiet_end': '00:00',
      },
      'server_time': '2026-10-12T10:00:00Z',
      'balance': {'available': 125, 'total': 125, 'reserved': 0},
      'members': [
        {'id': 'parent', 'name': 'Папа', 'role': 'parent', 'active': 1},
        {'id': 'child', 'name': 'Ребёнок', 'role': 'child', 'active': 1},
      ],
      'rooms': [
        {
          'id': 'family',
          'kind': 'family',
          'can_call': false,
          'contact': null,
          'title': 'Вся семья',
          'unread_count': 3,
          'last_message': {
            'sender_id': 'parent',
            'text': 'Отлично. Скоро увидимся!',
            'created_at': '2026-10-12T10:03:00Z',
          },
        },
        {
          'id': 'private',
          'kind': 'private',
          'can_call': true,
          'contact': {
            'id': 'parent',
            'name': 'Папа',
            'role': 'parent',
            'active': 1,
          },
          'title': 'Папа и ребёнок',
          'unread_count': 0,
          'last_message': null,
        },
      ],
      'calls': [
        {
          'id': 'past-call',
          'room_id': 'family',
          'caller_id': 'parent',
          'status': 'ended',
          'member_status': 'left',
          'video': 1,
          'created_at': '2026-10-12T09:40:00Z',
        },
      ],
    };
  }

  @override
  Future<void> sync() async {
    if (openedRoom != null) {
      for (final room in snapshot!['rooms'] as List) {
        if (room['id'] == openedRoom) {
          room['unread_count'] = history
              .where(
                (m) =>
                    m['sender_id'] != userId &&
                    !(m['receipts'] as List).any(
                      (r) => r['user_id'] == userId && r['read_at'] != null,
                    ),
              )
              .length;
        }
      }
    }
    notifyListeners();
  }

  @override
  Future<List<Map<String, Object?>>> pending() async => [];

  @override
  Future<Map<String, dynamic>> upload(
    String path,
    String contextType,
    String contextId,
  ) async {
    uploadedBytes = await File(path).length();
    return {'id': 'synthetic-recording'};
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/messages')) {
      openedRoom = path.split('/')[3];
      if (query?['before_id'] != null) {
        earlierLoaded = true;
        return {
          'messages': [
            {
              'id': 'older',
              'sender_id': 'parent',
              'text': 'Вчерашнее сообщение',
              'created_at': '2026-10-11T10:00:00Z',
              'receipts': <Map<String, dynamic>>[],
            },
          ],
          'has_more': false,
        };
      }
      return {'messages': history, 'has_more': !earlierLoaded};
    }
    if (path.endsWith('/receipt')) {
      final id = path.split('/')[3];
      final message = history.where((m) => m['id'] == id).firstOrNull;
      if (message != null) {
        final receipts = message['receipts'] as List;
        final receipt = receipts
            .where((r) => r['user_id'] == userId)
            .firstOrNull;
        final value = receipt ?? <String, dynamic>{'user_id': userId};
        value['delivered_at'] = '2026-10-12T11:00:00Z';
        if (body?['status'] == 'read') {
          value['read_at'] = '2026-10-12T11:00:00Z';
        }
        if (receipt == null) receipts.add(value);
      }
      return {'ok': true};
    }
    if (path == '/v1/devices') return {'ok': true};
    throw StateError('Unexpected synthetic request: $path');
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (failSend) {
      throw ApiFailure(503, 'Не удалось отправить. Попробуйте ещё раз.');
    }
    if (path.endsWith('/messages')) {
      if (body['attachment_id'] != null) {
        history.add({
          'id': 'recorded-voice',
          'sender_id': userId,
          'text': '',
          'attachment_id': body['attachment_id'],
          'attachment_mime': 'audio/wav',
          'created_at': '2026-10-12T12:00:00Z',
          'receipts': <Map<String, dynamic>>[],
        });
        return {'ok': true};
      }
      final value = body['text'] as String;
      sent.add(value);
      history.add({
        'id': 'sent-${sent.length}',
        'sender_id': userId,
        'text': value,
        'created_at': '2026-10-12T11:00:00Z',
        'receipts': <Map<String, dynamic>>[],
      });
    } else if (path.endsWith('/receipt')) {
      final id = path.split('/')[3];
      final message = history.firstWhere((m) => m['id'] == id);
      (message['receipts'] as List).add({
        'user_id': userId,
        'read_at': '2026-10-12T11:00:00Z',
        'delivered_at': '2026-10-12T11:00:00Z',
      });
    } else {
      throw StateError('Unexpected synthetic mutation: $path');
    }
    return {'ok': true};
  }
}

class ContactsFixture extends MessengerFixture {
  final String actorId;
  ContactsFixture({this.actorId = 'papa'})
    : super(
        role: actorId == 'stepa'
            ? 'child'
            : actorId == 'papa' || actorId == 'mama'
            ? 'parent'
            : 'relative',
      ) {
    final members = <Map<String, dynamic>>[
      {'id': 'papa', 'name': 'Папа', 'role': 'parent', 'active': 1},
      {'id': 'stepa', 'name': 'Стёпа', 'role': 'child', 'active': 1},
      {'id': 'mama', 'name': 'Мама', 'role': 'parent', 'active': 1},
      {'id': 'grandma1', 'name': 'Бабушка 1', 'role': 'relative', 'active': 1},
      {'id': 'grandpa1', 'name': 'Дедушка 1', 'role': 'relative', 'active': 1},
      {'id': 'grandma2', 'name': 'Бабушка 2', 'role': 'relative', 'active': 1},
      {'id': 'grandpa2', 'name': 'Дедушка 2', 'role': 'relative', 'active': 1},
    ];
    snapshot!['user'] = members.firstWhere((m) => m['id'] == actorId);
    snapshot!['members'] = members;
    snapshot!['calls'] = <Map<String, dynamic>>[];
    snapshot!['rooms'] = <Map<String, dynamic>>[
      {
        'id': 'family',
        'kind': 'family',
        'title': 'Вся семья',
        'can_call': false,
        'contact': null,
        'unread_count': 0,
        'last_message': null,
      },
      for (final member in members)
        if (member['id'] != actorId)
          {
            'id': 'private-${member['id']}',
            'kind': 'private',
            'title': 'Личная переписка',
            'can_call': true,
            'contact': member,
            'unread_count': 0,
            'last_message': null,
          },
    ];
    history.clear();
  }
  void addContact(Map<String, dynamic> contact) {
    (snapshot!['members'] as List).add(contact);
    (snapshot!['rooms'] as List).add({
      'id': 'private-${contact['id']}',
      'kind': 'private',
      'title': 'Личная переписка',
      'can_call': true,
      'contact': contact,
      'unread_count': 0,
      'last_message': null,
    });
    notifyListeners();
  }

  void deactivateContact(String id) {
    ((snapshot!['members'] as List).firstWhere((m) => m['id'] == id)
            as Map)['active'] =
        0;
    notifyListeners();
  }
}
