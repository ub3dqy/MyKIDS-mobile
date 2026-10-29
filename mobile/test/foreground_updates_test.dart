import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';

class ForegroundRepository extends FamilyRepository {
  final release = Completer<void>();
  int confirmedRefreshes = 0;
  ForegroundRepository() {
    token = 'synthetic-session';
    snapshot = {
      'user': {'id': 'child', 'role': 'child'},
    };
  }
  @override
  Future<void> refreshAfterChange() async {
    confirmedRefreshes++;
    await release.future;
    notifyListeners();
  }
}

class ForegroundServices extends BackgroundServices {
  int alarmRefreshes = 0;
  ForegroundServices(super.repository);
  @override
  Future<void> reminders() async => alarmRefreshes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForegroundRepository repo;
  late ForegroundServices services;
  setUp(() {
    repo = ForegroundRepository();
    services = ForegroundServices(repo);
  });
  tearDown(() {
    if (!repo.release.isCompleted) repo.release.complete();
    if (!services.disposed) services.dispose();
    repo.client.close();
    repo.dispose();
  });
  test(
    'calendar event refreshes the observed foreground repository before alarms',
    () async {
      var changes = 0;
      repo.addListener(() => changes++);
      final update = services.handleForegroundMessage(
        const RemoteMessage(
          data: {'kind': 'calendar', 'entity_id': 'synthetic-task'},
        ),
      );
      expect(repo.confirmedRefreshes, 1);
      expect(services.alarmRefreshes, 0);
      repo.release.complete();
      await update;
      expect(changes, 1);
      expect(services.alarmRefreshes, 1);
    },
  );
  for (final kind in ['call', 'call_state']) {
    test('$kind also refreshes after an in-flight snapshot', () async {
      repo.release.complete();
      await services.handleForegroundMessage(
        RemoteMessage(data: {'kind': kind}),
      );
      expect(repo.confirmedRefreshes, 1);
      expect(services.alarmRefreshes, 0);
    });
  }
  test('an event received after logout or disposal does not refresh', () async {
    repo.token = null;
    await services.handleForegroundMessage(
      const RemoteMessage(data: {'kind': 'calendar'}),
    );
    repo.token = 'synthetic-session';
    services.dispose();
    await services.handleForegroundMessage(
      const RemoteMessage(data: {'kind': 'calendar'}),
    );
    expect(repo.confirmedRefreshes, 0);
  });
  for (final change in ['account', 'generation', 'dispose']) {
    test(
      'a $change change during refresh prevents old reminder work',
      () async {
        final update = services.handleForegroundMessage(
          const RemoteMessage(data: {'kind': 'calendar'}),
        );
        if (change == 'account') repo.token = 'another-session';
        if (change == 'generation') repo.generation++;
        if (change == 'dispose') services.dispose();
        repo.release.complete();
        await update;
        expect(services.alarmRefreshes, 0);
      },
    );
  }
}
