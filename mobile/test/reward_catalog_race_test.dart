import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/money_screen.dart';

import 'reward_sync_test.dart' show RewardFixture;
import 'field_layout_test.dart' show mountFields, revealField;

class CatalogueFixture extends RewardFixture {
  final writes = <Map<String, dynamic>>[];
  final reply = Completer<Map<String, dynamic>>();
  CatalogueFixture() : super('parent') {
    (snapshot!['rewards'] as List).single['revision'] = 'a' * 64;
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
  for (final op in ['edit', 'delete']) {
    testWidgets(
      'reward $op captures opened revision and tolerates repeated taps',
      (tester) async {
        final repo = CatalogueFixture();
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
              builder: (_, _) => MoneyScreen(
                repository: repo,
                perform: (action) async {
                  await action();
                },
              ),
            ),
          ),
          scale: 1.2,
        );
        await revealField(tester, find.text('Конструктор · 25 монет'));
        await tester.tap(find.text('Конструктор · 25 монет'));
        await tester.pumpAndSettle();
        final label = op == 'edit' ? 'Изменить награду' : 'Удалить награду';
        await revealField(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        repo.change(title: 'Другое название', price: 60);
        (repo.snapshot!['rewards'] as List).single['revision'] = 'b' * 64;
        await tester.pumpAndSettle();
        final button = find.text(op == 'edit' ? 'Сохранить' : 'Удалить');
        await revealField(tester, button);
        final point = tester.getCenter(button);
        await tester.tapAt(point);
        await tester.tapAt(point);
        // Dispatch follows the dialog's completed closing transition.
        await tester.pumpAndSettle();
        expect(repo.writes, hasLength(1));
        expect(
          (repo.writes.single['body'] as Map)['expected_revision'],
          'a' * 64,
        );
        expect(repo.writes.single['method'], op == 'edit' ? 'PUT' : 'DELETE');
        repo.reply.complete({'ok': true});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
