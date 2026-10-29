import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/forms.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';

class SwitchableClient extends http.BaseClient {
  final http.Client real = http.Client();
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('simulated offline');
    return real.send(request);
  }

  @override
  void close() => real.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'child completes a task offline, restarts storage and synchronizes once',
    (tester) async {
      final connection = SwitchableClient();
      final repo = FamilyRepository(client: connection);
      await repo.initialize('child');
      await repo.login(
        'http://10.0.2.2:8765',
        'testkid',
        'emulator-only-12345',
      );
      await tester.pumpWidget(MyKidsApp(repository: repo));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Тестовый ребёнок'), findsOneWidget);
      expect(find.text('Сегодня'), findsWidgets);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await File('${Directory.systemTemp.path}/mykids-child-home.png')
          .writeAsBytes(await binding.takeScreenshot('child-home'));
      await tester.tap(find.text('Задания').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Проверочное задание'), findsOneWidget);
      final task = repo.rows('tasks').first;
      connection.offline = true;
      await repo.sync();
      expect(repo.online, false);
      await repo.mutate('/v1/tasks/${task['id']}/submissions', {
        'task_version': task['version'],
        'marked_at': DateTime.now().toUtc().toIso8601String(),
        'note': 'Проверка без интернета',
        'attachment_ids': <String>[],
      }, offlineSubmission: true);
      expect(await repo.pending(), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await repo.db!.close();
      final restarted = FamilyRepository();
      await restarted.initialize('child');
      expect(restarted.rows('tasks'), isNotEmpty);
      await restarted.sync();
      expect(await restarted.pending(), isEmpty);
      expect(restarted.rows('tasks').first['status'], 'submitted');
      expect(restarted.snapshot!['balance']['total'], 0);
      await restarted.sync();
      expect(restarted.rows('submissions'), hasLength(1));
      await tester.pumpWidget(MyKidsApp(repository: restarted));
      await tester.pump(const Duration(seconds: 2));
      final navigation = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigation.push(
        MaterialPageRoute<void>(
          builder: (_) => const FamilyForm(
            title: 'Семейные данные',
            fields: [FamilyField('note', 'Заметка', initial: 'Личные данные')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Семейные данные'), findsOneWidget);
      await restarted.logout();
      await tester.pumpAndSettle();
      expect(find.text('Семейные данные'), findsNothing);
      expect(find.text('Войдите в свою семью'), findsOneWidget);
      expect(await restarted.db!.query('cache'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await restarted.db!.close();
      connection.close();
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'offline_result_survives_restart': true,
        'one_submission_after_repeated_sync': true,
        'no_reward_before_approval': true,
        'logout_removes_private_routes_and_cache': true,
        'physical_phones_tested': false,
      };
    },
  );
}
