import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite/sqflite.dart';

class _Client extends MockClient {
  bool closed = false;
  _Client() : super((_) async => http.Response('', 200));
  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _Database extends Fake implements Database {
  bool closed = false;
  Exception? closeError;
  @override
  Future<void> close() async {
    closed = true;
    if (closeError != null) throw closeError!;
  }
}

class _Repository extends FamilyRepository {
  final _Database connection = _Database();
  final _Client transport;
  Exception? initializeError;
  Exception? syncError;
  bool successful = true;
  int syncCalls = 0;
  List<Map<String, Object?>> queued = [];
  @override
  Future<List<Map<String, Object?>>> pending() async => queued;
  _Repository(this.transport) : super(client: transport) {
    token = 'synthetic-background-session';
    db = connection;
  }
  @override
  Future<void> initialize([String? setupRole]) async {
    if (initializeError != null) throw initializeError!;
  }

  @override
  Future<void> sync() async {
    syncCalls++;
    if (syncError != null) throw syncError!;
    online = successful;
  }
}

void main() {
  _Repository repository() => _Repository(_Client());
  Future<void> ready() async {}
  Future<bool> run(_Repository repo) => runBackgroundSync(
    repo,
    prepareNotifications: ready,
    updateReminders: ready,
  );
  void closed(_Repository repo) {
    expect(repo.connection.closed, isTrue);
    expect(repo.transport.closed, isTrue);
  }

  test(
    'busy initialization retries instead of failing dependent refreshes',
    () async {
      final repo = repository()
        ..initializeError = PlatformException(
          code: 'sqlite_error',
          message: 'database is locked',
        );
      expect(await run(repo), isFalse);
      expect(repo.syncCalls, 0);
      closed(repo);
    },
  );

  test(
    'a transient refresh failure retries and closes both resources',
    () async {
      final repo = repository()
        ..syncError = const FormatException('temporary saved data');
      expect(await run(repo), isFalse);
      closed(repo);
    },
  );

  test(
    'a reminder platform failure retries after the snapshot was saved',
    () async {
      final repo = repository();
      expect(
        await runBackgroundSync(
          repo,
          prepareNotifications: ready,
          updateReminders: () async =>
              throw PlatformException(code: 'temporarily_unavailable'),
        ),
        isFalse,
      );
      expect(repo.online, isTrue);
      closed(repo);
      final next = repository();
      expect(await run(next), isTrue);
      closed(next);
    },
  );

  test(
    'a signed-out installation finishes without network or reminders',
    () async {
      final repo = repository()..token = null;
      var prepared = false;
      expect(
        await runBackgroundSync(
          repo,
          prepareNotifications: () async {
            prepared = true;
          },
          updateReminders: () async =>
              fail('Signed-out reminders must not run'),
        ),
        isTrue,
      );
      expect(prepared, isFalse);
      expect(repo.syncCalls, 0);
      closed(repo);
    },
  );

  test('offline refresh remains retryable', () async {
    final repo = repository()..successful = false;
    expect(await run(repo), isFalse);
    closed(repo);
  });

  test(
    'database cleanup failure still closes the client and retries',
    () async {
      final repo = repository()
        ..connection.closeError = PlatformException(code: 'sqlite_error');
      expect(await run(repo), isFalse);
      closed(repo);
    },
  );

  test('successful refresh completes and releases resources', () async {
    final repo = repository();
    expect(await run(repo), isTrue);
    expect(repo.syncCalls, 1);
    closed(repo);
  });
  test(
    'a fresh snapshot cannot finish work while a command is pending',
    () async {
      final repo = repository()
        ..queued = [
          {'state': 'pending'},
        ];
      expect(await run(repo), isFalse);
      closed(repo);
    },
  );
  test('a permanently rejected command does not retry forever', () async {
    final repo = repository()
      ..queued = [
        {'state': 'failed'},
      ];
    expect(await run(repo), isTrue);
    closed(repo);
  });
}
