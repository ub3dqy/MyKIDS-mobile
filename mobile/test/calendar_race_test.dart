import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/calendar_screen.dart';
import 'package:mykids_family/repository.dart';

import 'calendar_test.dart' as fixture;
import 'field_layout_test.dart' show mountFields, revealField;

class CalendarRaceFixture extends FamilyRepository {
  final writes = <Map<String, dynamic>>[];
  final reply = Completer<Map<String, dynamic>>();
  CalendarRaceFixture() {
    token = 'synthetic';
    online = true;
    snapshot = fixture.snapshot([
      {
        ...fixture.event('Прогулка', '12:00', '13:00', kind: 'other'),
        'date': null,
        'weekdays': '[1]',
        'revision': 'a' * 64,
      },
    ])..['user'] = {'id': 'papa', 'role': 'parent'};
  }
  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) {
    writes.add({'path': path, 'method': method, 'body': body});
    return reply.future;
  }
}

void main() {
  for (final op in ['edit', 'replace', 'cancel', 'archive']) {
    testWidgets(
      'calendar $op binds opened revision and tolerates repeated taps',
      (tester) async {
        final repo = CalendarRaceFixture();
        addTearDown(() {
          repo.client.close();
          repo.dispose();
        });
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mountFields(
          tester,
          Scaffold(
            body: AnimatedBuilder(
              animation: repo,
              builder: (_, _) => CalendarScreen(
                repository: repo,
                initialDay: DateTime.utc(2026, 10, 12, 12),
                perform: (action) async {
                  await action();
                },
                openTasks: (_) {},
              ),
            ),
          ),
          scale: 1.2,
        );
        await revealField(tester, find.text('Прогулка'));
        await tester.tap(find.text('Прогулка'));
        await tester.pumpAndSettle();
        final label = {
          'edit': 'Изменить событие и повторения',
          'replace': 'Изменить только этот день',
          'cancel': 'Отменить только этот день',
          'archive': 'Удалить событие и повторения',
        }[op]!;
        await revealField(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        repo.snapshot!['schedules'] = [
          {
            ...repo.rows('schedules').single,
            'revision': 'b' * 64,
            'title': 'Новое название',
          },
        ];
        repo.notifyListeners();
        await tester.pumpAndSettle();
        final save = find.text(
          op == 'edit' || op == 'replace' ? 'Сохранить' : 'Подтвердить',
        );
        await revealField(tester, save);
        final point = tester.getCenter(save);
        await tester.tapAt(point);
        await tester.tapAt(point);
        await tester.pump();
        expect(repo.writes, hasLength(1));
        final body = repo.writes.single['body'] as Map;
        expect(body['expected_revision'], 'a' * 64);
        if (op == 'replace') {
          expect(
            (body['replacement'] as Map).containsKey('expected_revision'),
            false,
          );
        }
        expect(
          repo.writes.single['method'],
          op == 'edit'
              ? 'PUT'
              : op == 'archive'
              ? 'DELETE'
              : 'POST',
        );
        repo.reply.complete({'ok': true});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
