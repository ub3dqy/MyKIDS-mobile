import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/repository.dart';

import 'field_layout_test.dart' show mountFields;
import 'support/messenger_fixture.dart';

class ReadFixture extends MessengerFixture {
  final readRequests = <Map<String, dynamic>>[];
  bool failReads = false;
  bool malformedReceipt = false;
  Completer<void>? holdRead;
  int refreshes = 0;
  ReadFixture({
    String actorRole = 'parent',
    String kind = 'private',
    int count = 2,
    bool longMessages = false,
  }) : super(role: actorRole) {
    snapshot!['user'] = {
      'id': actorRole,
      'role': actorRole,
      'name': 'Проверка',
    };
    snapshot!['rooms'] = [
      {
        'id': 'reading',
        'kind': kind,
        'title': 'Вся семья',
        'contact': kind == 'private'
            ? {
                'id': actorRole == 'child' ? 'parent' : 'child',
                'name': 'Степан',
              }
            : null,
        'can_call': false,
        'unread_count': count,
        'last_message': null,
      },
      {
        'id': 'other',
        'kind': 'family',
        'title': 'Другой чат',
        'can_call': false,
        'unread_count': 7,
        'last_message': null,
      },
    ];
    history.clear();
    for (var i = 0; i < count; i++) {
      addIncoming('incoming-$i', longMessages: longMessages, notify: false);
    }
  }
  Map<String, dynamic> get readingRoom =>
      (snapshot!['rooms'] as List).first as Map<String, dynamic>;
  int get unread => readingRoom['unread_count'] as int;
  void addIncoming(String id, {bool longMessages = false, bool notify = true}) {
    history.add({
      'id': id,
      'sender_id': userId == 'child' ? 'parent' : 'child',
      'text': longMessages
          ? List.filled(20, 'Длинное сообщение $id').join('\n')
          : '',
      'attachment_id': longMessages ? null : 'photo-$id',
      'attachment_mime': longMessages ? null : 'image/jpeg',
      'created_at': DateTime.utc(
        2026,
        10,
        15,
        10,
        0,
        history.length,
      ).toIso8601String(),
      'receipts': <Map<String, dynamic>>[],
    });
    if (notify) {
      readingRoom['unread_count'] = unread + 1;
      notifyListeners();
    }
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
      return {'messages': jsonDecode(jsonEncode(history)), 'has_more': false};
    }
    if (path.endsWith('/receipt') && body?['status'] == 'read') {
      readRequests.add({'id': path.split('/')[3], 'user': userId, 'key': key});
      if (failReads) throw ApiFailure(503, 'Нет связи');
      if (malformedReceipt) return {'message': 'Incomplete reply'};
      await holdRead?.future;
    }
    return super.request(
      path,
      method: method,
      body: body,
      key: key,
      query: query,
    );
  }

  @override
  Future<void> sync() async {
    refreshes++;
    await super.sync();
  }
}

Future<void> showReadChat(
  WidgetTester tester,
  ReadFixture repo, {
  Size? size = const Size(360, 800),
}) async {
  await mountFields(
    tester,
    ChatScreen(repository: repo, room: repo.rows('rooms').first),
    scale: 1.2,
    screenSize: size,
  );
}

Future<void> settleReads(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void resumeReadApp(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.inactive) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void closeReadFixture(WidgetTester tester, ReadFixture repo) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    repo.client.close();
    repo.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    resumeReadApp(tester);
  });
}

void main() {
  for (final role in ['parent', 'child', 'relative']) {
    for (final kind in ['private', 'family']) {
      testWidgets(
        '$role reads two photos automatically in $kind chat and badge stays cleared',
        (tester) async {
          final repo = ReadFixture(actorRole: role, kind: kind);
          closeReadFixture(tester, repo);
          await mountFields(
            tester,
            Scaffold(
              body: FamilyScreen(repository: repo, perform: (_) async {}),
            ),
            scale: 1.2,
          );
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 2')),
            findsOneWidget,
          );
          await tester.tap(
            find.text(kind == 'private' ? 'Степан' : 'Вся семья'),
          );
          await settleReads(tester);
          expect(repo.unread, 0);
          expect(repo.readRequests.map((r) => r['id']).toSet(), {
            'incoming-0',
            'incoming-1',
          });
          expect(find.byTooltip('Отметить прочитанным'), findsNothing);
          await tester.tap(find.byTooltip('Назад'));
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 2')),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 7')),
            findsOneWidget,
          );
          repo.addIncoming('new-unread');
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 1')),
            findsOneWidget,
          );
          expect(repo.readRequests.length, 2);
          await tester.tap(
            find.text(kind == 'private' ? 'Степан' : 'Вся семья'),
          );
          await settleReads(tester);
          expect(repo.unread, 0);
          expect(repo.readRequests.length, 3);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'receipt failure keeps the badge and retries without duplicate successful reads',
    (tester) async {
      final repo = ReadFixture()..failReads = true;
      closeReadFixture(tester, repo);
      await showReadChat(tester, repo);
      await settleReads(tester);
      expect(repo.unread, 2);
      repo.failReads = false;
      await tester.pump(const Duration(seconds: 5));
      await settleReads(tester);
      expect(repo.unread, 0);
      final successfulCount = repo.readRequests.length;
      await tester.pump(const Duration(seconds: 10));
      await settleReads(tester);
      expect(repo.readRequests.length, successfulCount);
    },
  );
  testWidgets('background and covered chat do not read messages', (
    tester,
  ) async {
    final repo = ReadFixture();
    closeReadFixture(tester, repo);
    await showReadChat(tester, repo);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settleReads(tester);
    expect(repo.readRequests, isEmpty);
    resumeReadApp(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Другая страница')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settleReads(tester);
    expect(repo.readRequests, isEmpty);
    navigator.pop();
    await tester.pumpAndSettle();
    await settleReads(tester);
    expect(repo.unread, 0);
  });
  testWidgets(
    'unseen messages stay unread while scrolling history and new visible messages are read',
    (tester) async {
      final repo = ReadFixture(count: 30, longMessages: true);
      closeReadFixture(tester, repo);
      await showReadChat(tester, repo);
      await settleReads(tester);
      expect(repo.readRequests.map((r) => r['id']), contains('incoming-29'));
      expect(
        repo.readRequests.map((r) => r['id']),
        isNot(contains('incoming-0')),
      );
      expect(repo.unread, greaterThan(0));
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(1800);
      await tester.pump();
      await settleReads(tester);
      repo.addIncoming('new-while-scrolled', longMessages: true);
      await tester.pump(const Duration(seconds: 5));
      await settleReads(tester);
      expect(
        repo.readRequests.map((r) => r['id']),
        isNot(contains('new-while-scrolled')),
      );
      scroll.position.jumpTo(0);
      await tester.pump();
      await settleReads(tester);
      expect(
        repo.readRequests.map((r) => r['id']),
        contains('new-while-scrolled'),
      );
    },
  );
  for (final change in ['token', 'endpoint', 'generation']) {
    testWidgets('changed $change cancels pending automatic receipts', (
      tester,
    ) async {
      final repo = ReadFixture();
      closeReadFixture(tester, repo);
      await showReadChat(tester, repo);
      switch (change) {
        case 'token':
          repo.token = 'another-session';
        case 'endpoint':
          repo.endpoint = 'https://another.invalid';
        case 'generation':
          repo.generation++;
      }
      await settleReads(tester);
      expect(repo.readRequests, isEmpty);
    });
  }
  testWidgets(
    'session change during receipt stops the next message and snapshot update',
    (tester) async {
      final repo = ReadFixture()..holdRead = Completer<void>();
      closeReadFixture(tester, repo);
      await showReadChat(tester, repo);
      await tester.pump(const Duration(milliseconds: 250));
      expect(repo.readRequests.length, 1);
      repo.token = 'another-session';
      repo.holdRead!.complete();
      await settleReads(tester);
      expect(repo.readRequests.length, 1);
      expect(repo.refreshes, 0);
    },
  );
  testWidgets('changing rooms in a retained screen cancels automatic reads', (
    tester,
  ) async {
    final repo = ReadFixture();
    closeReadFixture(tester, repo);
    await showReadChat(tester, repo);
    await mountFields(
      tester,
      ChatScreen(repository: repo, room: repo.rows('rooms').last),
      scale: 1.2,
    );
    await settleReads(tester);
    expect(repo.readRequests, isEmpty);
  });
  testWidgets('own messages never produce read receipts', (tester) async {
    final repo = ReadFixture();
    closeReadFixture(tester, repo);
    for (final message in repo.history) {
      message['sender_id'] = repo.userId;
    }
    repo.readingRoom['unread_count'] = 0;
    await showReadChat(tester, repo);
    await settleReads(tester);
    expect(repo.readRequests, isEmpty);
    expect(repo.unread, 0);
  });
  testWidgets('incomplete acknowledgement does not clear unread messages', (
    tester,
  ) async {
    final repo = ReadFixture()..malformedReceipt = true;
    closeReadFixture(tester, repo);
    await showReadChat(tester, repo);
    await settleReads(tester);
    expect(repo.unread, 2);
    expect(find.byTooltip('Отметить прочитанным'), findsNWidgets(2));
  });
  testWidgets(
    'going back during a slow receipt still confirms all viewed photos',
    (tester) async {
      final repo = ReadFixture()..holdRead = Completer<void>();
      closeReadFixture(tester, repo);
      await mountFields(
        tester,
        Scaffold(
          body: FamilyScreen(repository: repo, perform: (_) async {}),
        ),
        scale: 1.2,
      );
      await tester.tap(find.text('Степан'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      expect(repo.readRequests.length, 1);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      repo.holdRead!.complete();
      await settleReads(tester);
      expect(repo.readRequests.length, 2);
      expect(repo.unread, 0);
      expect(
        find.bySemanticsLabel(RegExp('Непрочитанных сообщений: 2')),
        findsNothing,
      );
    },
  );
}
