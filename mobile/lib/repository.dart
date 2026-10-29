import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:family_runtime/family_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'calendar_position.dart';
import 'outbox_sync.dart';

class ApiFailure implements Exception {
  final int status;
  final String message;
  final Map<String, String> fields;
  ApiFailure(this.status, this.message, {this.fields = const {}});
  @override
  String toString() => message;
}

/// The command is durable; another save would create a second command.
class QueuedCommandFailure extends ApiFailure {
  final String commandId;
  QueuedCommandFailure(super.status, super.message, {required this.commandId});
}

class _SessionChanged extends ApiFailure {
  _SessionChanged() : super(401, 'Семейный доступ изменён');
}

class _Session {
  final String? token;
  final String endpoint, tag;
  final int generation;
  _Session(FamilyRepository repo)
    : token = repo.token,
      endpoint = repo.endpoint,
      tag = repo.sessionTag,
      generation = repo.generation;
  bool matches(FamilyRepository repo) =>
      token != null &&
      token == repo.token &&
      endpoint == repo.endpoint &&
      generation == repo.generation;
}

class FamilyRepository extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  final http.Client client;
  final Duration requestTimeout;
  Database? db;
  String? token;
  String endpoint = '';
  // Initial setup preference only; permissions always come from the server.
  String variant = '';
  static const roles = ['child', 'parent', 'relative'];
  Map<String, dynamic>? snapshot;
  bool online = false;
  bool syncing = false;
  Future<void>? _syncInFlight;
  _Session? _syncOwner;
  int _counterRevision = 0;
  final _requests = <Completer<void>>{};
  int generation = 0;
  CalendarPosition? _calendarPosition;
  (String, String, int)? _calendarPositionOwner;
  Future<void>? _calendarWrites;
  CalendarPosition? get calendarPosition =>
      _calendarPositionOwner == (endpoint, sessionTag, generation)
      ? _calendarPosition
      : null;
  String? _processIdentity;
  String get sessionTag =>
      token == null ? '' : sha256.convert(utf8.encode(token!)).toString();
  FamilyRepository({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
  }) : client = client ?? http.Client();

  Future<T> _database<T>(Future<T> Function() operation) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      try {
        return await operation();
      } on DatabaseException catch (error) {
        final code = error.getResultCode();
        final busy =
            code == 5 ||
            code == 6 ||
            error.toString().contains('database is locked');
        if (!busy || DateTime.now().isAfter(deadline)) rethrow;
        // Never block the SQLite worker while another connection awaits a
        // platform callback and still needs that worker to commit its changes.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _checkSession(_Session session) async {
    final identity = await db!.query('identity', where: 'id=1');
    if (!session.matches(this) ||
        identity.isEmpty ||
        identity.single['tag'] != session.tag) {
      throw _SessionChanged();
    }
  }

  bool get signedIn => token != null;

  Future<void> guardDeviceUpdate(Future<void> Function() action) async {
    // Rendering fixtures have no persistent database. Real sessions do.
    if (db == null) {
      await action();
      return;
    }
    final epoch = generation, tag = sessionTag;
    await _database(
      () => db!.transaction((transaction) async {
        final identity = await transaction.query('identity', where: 'id=1');
        if (epoch != generation || tag != sessionTag) return;
        final owns = identity.isEmpty
            ? !signedIn
            : identity.single['tag'] == tag;
        if (!owns && (signedIn || await storage.read(key: 'session') != null)) {
          return;
        }
        // Login/logout use the same lock, including their secure-storage writes.
        // An old background plan therefore cannot overwrite a newer one.
        await action();
      }),
    );
  }

  String get role => snapshot?['user']?['role'] as String? ?? variant;
  String get userId => snapshot?['user']?['id'] as String? ?? '';
  List<Map<String, dynamic>> rows(String name) =>
      (snapshot?[name] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> selectRole(String value) async {
    if (signedIn || (value.isNotEmpty && !roles.contains(value))) {
      throw ApiFailure(400, 'Роль можно выбрать перед входом');
    }
    await storage.write(key: 'setup_role', value: value);
    variant = value;
    notifyListeners();
  }

  Future<void> initialize([String? setupRole]) async {
    _processIdentity = await familyOutboxOwner();
    final savedRole = setupRole ?? await storage.read(key: 'setup_role');
    variant = roles.contains(savedRole) ? savedRole! : '';
    endpoint =
        await storage.read(key: 'endpoint') ??
        const String.fromEnvironment(
          'API_URL',
          defaultValue: 'https://api.xn--80ajzgig.online',
        );
    token = await storage.read(key: 'session');
    // Read this before the first app frame, including when opening offline.
    try {
      _calendarPosition = CalendarPosition.decode(
        await storage.read(key: CalendarPosition.storageKey),
        endpoint,
        sessionTag,
      );
    } catch (_) {
      // An optional view preference must not prevent access to saved family data.
      _calendarPosition = null;
    }
    _calendarPositionOwner = (endpoint, sessionTag, generation);
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'family.sqlite'),
      singleInstance: false,
      version: 3,
      onConfigure: (database) async {
        await database.rawQuery('PRAGMA journal_mode=WAL');
        // A completed offline action must survive power loss, not only app death.
        // execute() uses Android's primary writer connection, unlike a read query.
        await database.execute('PRAGMA synchronous=FULL');
        await database.rawQuery('PRAGMA busy_timeout=0');
      },
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE cache (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
        );
        await database.execute(
          "CREATE TABLE outbox (id TEXT PRIMARY KEY, path TEXT NOT NULL, method TEXT NOT NULL, body TEXT NOT NULL, files TEXT NOT NULL, state TEXT NOT NULL, error TEXT, lease_until INTEGER NOT NULL DEFAULT 0, auth_tag TEXT NOT NULL, lease_owner TEXT NOT NULL DEFAULT '')",
        );
        await database.execute(
          'CREATE TABLE identity (id INTEGER PRIMARY KEY, tag TEXT NOT NULL)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE outbox ADD COLUMN lease_until INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            "ALTER TABLE outbox ADD COLUMN auth_tag TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'CREATE TABLE identity (id INTEGER PRIMARY KEY, tag TEXT NOT NULL)',
          );
          await database.insert('identity', {'id': 1, 'tag': sessionTag});
          await database.update('outbox', {'auth_tag': sessionTag});
        }
        if (oldVersion < 3) {
          await database.execute(
            "ALTER TABLE outbox ADD COLUMN lease_owner TEXT NOT NULL DEFAULT ''",
          );
          // Android stops the old application process during package upgrade.
          // Previous releases did not record an owner for interrupted sends.
          await database.update('outbox', {'lease_until': 0});
        }
      },
    );
    final cached = await _database(
      () => db!.transaction((transaction) async {
        final identity = await transaction.query('identity', where: 'id=1');
        if (identity.isEmpty || identity.single['tag'] != sessionTag) {
          return <Map<String, Object?>>[];
        }
        return transaction.query('cache', limit: 1);
      }),
    );
    if (cached.isNotEmpty && token != null) {
      try {
        final decoded = jsonDecode(cached.first['data'] as String);
        if (decoded is! Map<String, dynamic> ||
            decoded['user'] is! Map ||
            !roles.contains(decoded['user']['role'])) {
          throw const FormatException('Invalid saved snapshot');
        }
        snapshot = decoded;
      } on FormatException {
        // Cache is replaceable. Keep credentials, queued commands and photos.
        await _database(
          () => db!.transaction((transaction) async {
            final identity = await transaction.query('identity', where: 'id=1');
            if (identity.isNotEmpty && identity.single['tag'] == sessionTag) {
              await transaction.delete(
                'cache',
                where: 'id=? AND data=?',
                whereArgs: [cached.first['id'], cached.first['data']],
              );
            }
          }),
        );
        return;
      }
    }
  }

  Uri uri(String path, [Map<String, String>? query]) {
    return _uriAt(endpoint, path, query);
  }

  Future<void> saveCalendarPosition(DateTime day, String mode) {
    if (!signedIn) return Future<void>.value();
    final position = CalendarPosition(day, mode);
    final session = _Session(this);
    _calendarPosition = position;
    _calendarPositionOwner = (endpoint, sessionTag, generation);
    // Rendering fixtures have no database or persistent family identity.
    if (db == null) return Future<void>.value();
    final pending = (_calendarWrites ?? Future<void>.value()).then((_) async {
      if (!session.matches(this)) return;
      await guardDeviceUpdate(() async {
        if (!session.matches(this)) return;
        await storage.write(
          key: CalendarPosition.storageKey,
          value: position.encode(session.endpoint, session.tag),
        );
      });
    });
    // Preserve write order, while allowing a later choice to retry a failed save.
    _calendarWrites = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> flushCalendarPosition() =>
      _calendarWrites ?? Future<void>.value();

  Uri _uriAt(String server, String path, [Map<String, String>? query]) {
    final base = Uri.parse(server);
    final permittedHttp =
        kDebugMode &&
        const bool.fromEnvironment('ALLOW_LOCAL_HTTP') &&
        ['127.0.0.1', 'localhost', '10.0.2.2'].contains(base.host);
    if (base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.query.isNotEmpty ||
        base.fragment.isNotEmpty ||
        (base.scheme != 'https' && !permittedHttp)) {
      throw ApiFailure(400, 'Нужен защищённый адрес семейного сервера');
    }
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, uri(path, query));
    request.followRedirects = false;
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (key != null) request.headers['Idempotency-Key'] = key;
    if (body != null) request.body = jsonEncode(body);
    return _performRequest(request);
  }

  void _requireCurrent(_Session session) {
    if (!session.matches(this)) {
      throw _SessionChanged();
    }
  }

  Future<Map<String, dynamic>> _performRequest(
    http.Request request, {
    _Session? session,
  }) async {
    if (session != null) {
      _requireCurrent(session);
    }
    final response = await _send(request, requestTimeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiFailure(502, 'Семейный сервер временно недоступен');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is Map) {
        throw ApiFailure(
          response.statusCode,
          detail['message'] as String? ?? 'Не удалось сохранить изменения',
          fields: {
            for (final entry in (detail['fields'] as Map? ?? {}).entries)
              entry.key.toString(): entry.value.toString(),
          },
        );
      }
      if (detail is List) {
        final fields = <String, String>{};
        for (final item in detail.whereType<Map>()) {
          final location = (item['loc'] as List? ?? [])
              .where((p) => p != 'body')
              .join('.');
          final ctx = item['ctx'] as Map? ?? {};
          final message = item['type'] == 'string_too_short'
              ? '${location == 'password' ? 'Пароль' : 'Поле'}: минимум ${ctx['min_length']} символов'
              : item['type'] == 'string_pattern_mismatch' &&
                    location == 'username'
              ? 'Логин: используйте латинские буквы, цифры, точку, дефис или подчёркивание'
              : 'Поле «$location»: ${item['msg'] ?? 'проверьте значение'}';
          fields[location] = message;
        }
        throw ApiFailure(
          response.statusCode,
          fields.values.join('\n'),
          fields: fields,
        );
      }
      throw ApiFailure(
        response.statusCode,
        detail is String ? detail : 'Проверьте введённые данные',
      );
    }
    if (decoded is! Map) {
      throw ApiFailure(502, 'Семейный сервер вернул неполные данные');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<http.Response> _send(http.BaseRequest source, Duration timeout) async {
    final abort = Completer<void>();
    _requests.add(abort);
    final http.BaseRequest request;
    if (source is http.MultipartRequest) {
      request =
          http.AbortableMultipartRequest(
              source.method,
              source.url,
              abortTrigger: abort.future,
            )
            ..fields.addAll(source.fields)
            ..files.addAll(source.files);
    } else {
      request = http.AbortableRequest(
        source.method,
        source.url,
        abortTrigger: abort.future,
      )..bodyBytes = (source as http.Request).bodyBytes;
    }
    request
      ..headers.addAll(source.headers)
      ..followRedirects = false;
    try {
      return await http.Response.fromStream(
        await client.send(request).timeout(timeout),
      ).timeout(timeout);
    } finally {
      // Cancel a timed-out transport as well as its Future. Retrying an outbox
      // command still uses its original key if the server accepted it already.
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
    }
  }

  void connectionLost() {
    _counterRevision++;
    for (final abort in _requests.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    online = false;
    notifyListeners();
  }

  Future<void> reconnect() async {
    if (!signedIn) return;
    // Release requests held by the previous Wi-Fi/mobile connection before
    // waiting for its sync. The HTTP client itself remains usable.
    for (final abort in _requests.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    await refreshAfterChange();
  }

  Future<void> login(
    String server,
    String username,
    String password, {
    String? invite,
    String? name,
  }) async {
    final epoch = generation + 1;
    await logout(remote: false);
    if (generation != epoch) throw _SessionChanged();
    final target = server.trim().replaceAll(RegExp(r'/$'), '');
    endpoint = target;
    final result = await request(
      invite == null ? '/v1/login' : '/v1/invites/accept',
      method: 'POST',
      body: {
        'username': username.trim(),
        'password': password,
        if (invite != null) 'token': invite.trim(),
        if (invite != null) 'name': name?.trim() ?? '',
      },
    );
    // A cancelled request can still finish in some transports. Never accept its
    // credentials, or send them to the endpoint of a later sign-in attempt.
    if (generation != epoch || endpoint != target || token != null) {
      throw _SessionChanged();
    }
    token = result['token'] as String;
    final session = _Session(this);
    try {
      final fresh = await request('/v1/snapshot');
      _requireCurrent(session);
      if (!roles.contains(fresh['user']?['role'])) {
        throw ApiFailure(403, 'Не удалось подтвердить семейную роль');
      }
      final role = fresh['user']['role'] as String;
      // Background logout and foreground login share this write lock, so an
      // old storage deletion cannot erase the newer credentials.
      await _database(
        () => db!.transaction((transaction) async {
          _requireCurrent(session);
          await storage.write(key: 'setup_role', value: role);
          await storage.write(key: 'endpoint', value: session.endpoint);
          await storage.write(key: 'session', value: session.token);
          _requireCurrent(session);
          await transaction.insert('identity', {
            'id': 1,
            'tag': session.tag,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await _storeCache(transaction, fresh);
        }),
      );
      _requireCurrent(session);
      variant = role;
      snapshot = fresh;
      online = true;
      notifyListeners();
    } catch (_) {
      if (session.matches(this)) await logout();
      rethrow;
    }
  }

  Future<bool> cancelLogin() async {
    // Once the authenticated snapshot is published, use the normal logout flow.
    if (snapshot != null) return false;
    final epoch = generation + 1;
    for (final abort in _requests.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    await logout(remote: false);
    return generation == epoch && token == null;
  }

  Future<void> cache(Map<String, dynamic> data) async {
    await _cacheFor(data, _Session(this));
  }

  Future<bool> _cacheFor(
    Map<String, dynamic> data,
    _Session session, {
    bool recover = false,
  }) async {
    return _database(
      () => db!.transaction((transaction) async {
        final identity = await transaction.query('identity', where: 'id=1');
        if (!session.matches(this)) return false;
        if (identity.isEmpty) {
          // Secure storage can survive a process stop before the login's SQLite
          // commit. Recover only after an authenticated snapshot and while the
          // exact same credentials are still stored; never replace another tag.
          if (!recover ||
              await storage.read(key: 'session') != session.token ||
              !session.matches(this)) {
            return false;
          }
          await transaction.insert('identity', {'id': 1, 'tag': session.tag});
        } else if (identity.single['tag'] != session.tag) {
          return false;
        }
        await _storeCache(transaction, data);
        return true;
      }),
    );
  }

  Future<void> _storeCache(
    DatabaseExecutor connection,
    Map<String, dynamic> data,
  ) async {
    await connection.insert('cache', {
      'id': 1,
      'data': jsonEncode(data),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> logout({bool remote = true}) async {
    generation++;
    _calendarPosition = null;
    _calendarPositionOwner = null;
    final epoch = generation;
    final oldToken = token;
    final oldTag = sessionTag;
    if (remote && token != null) {
      try {
        await request('/v1/logout', method: 'POST');
      } catch (_) {
        /* Local logout remains available offline. */
      }
    }
    if (epoch != generation || oldToken != token) return;
    token = null;
    snapshot = null;
    online = false;
    var removeFiles = false;
    if (db != null) {
      await _database(
        () => db!.transaction((transaction) async {
          final identity = await transaction.query('identity', where: 'id=1');
          if (identity.isNotEmpty && identity.single['tag'] != oldTag) return;
          if (await storage.read(key: 'session') == oldToken &&
              epoch == generation &&
              token == null) {
            await storage.delete(key: 'session');
            await storage.delete(key: CalendarPosition.storageKey);
          }
          await transaction.delete('identity');
          await transaction.delete('cache');
          await transaction.delete('outbox');
          removeFiles = true;
        }),
      );
    }
    final attachmentRoot = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'attachments'),
    );
    if (removeFiles && await attachmentRoot.exists()) {
      // Another account can already be writing its files while this logout
      // waits for platform storage. Delete only the captured session folder.
      if (oldTag.isNotEmpty) {
        final folder = Directory(p.join(attachmentRoot.path, oldTag));
        if (await folder.exists()) {
          await folder.delete(recursive: true);
        }
      }
      // Earlier releases stored files directly here. New sessions use only
      // subfolders, so removing these legacy files cannot remove new photos.
      await for (final entry in attachmentRoot.list(followLinks: false)) {
        if (entry is File) {
          await entry.delete();
        }
      }
    }
    notifyListeners();
  }

  Future<String> keepFile(String source) async {
    final session = _Session(this);
    await _checkSession(session);
    final folder = Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'attachments',
        session.tag,
      ),
    );
    await _checkSession(session);
    await folder.create(recursive: true);
    final file = await File(source)
        .copy(p.join(folder.path, const Uuid().v4() + p.extension(source)));
    try {
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
    } catch (_) {
      await file.delete().catchError((_) => file);
      rethrow;
    }
    return (await _verifyOwnedFile(file, session)).path;
  }

  Future<File> _verifyOwnedFile(File file, _Session session) async {
    try {
      await _checkSession(session);
      return file;
    } catch (_) {
      await file.delete().catchError((_) => file);
      rethrow;
    }
  }

  static bool _callCommand(String path) =>
      RegExp(r'^/v1/(calls/[^/]+/actions|rooms/[^/]+/calls)$').hasMatch(path);

  Future<List<Map<String, Object?>>> pending() async {
    final session = _Session(this);
    return _database(
      () => db!.transaction((transaction) async {
        final identity = await transaction.query('identity', where: 'id=1');
        if (!session.matches(this) ||
            identity.isEmpty ||
            identity.single['tag'] != session.tag) {
          // Sync still needs to authenticate and recover an interrupted login,
          // or clear an expired session. Never read or edit another identity.
          return <Map<String, Object?>>[];
        }
        final rows = await transaction.query(
          'outbox',
          where: 'auth_tag=?',
          whereArgs: [session.tag],
          orderBy: 'rowid',
        );
        final result = <Map<String, Object?>>[];
        for (final row in rows) {
          // Rejected call controls cannot be corrected after a conversation.
          // Retire legacy failures, while preserving retryable disconnects and
          // every task, message and financial command.
          if (row['state'] == 'failed' && _callCommand(row['path'] as String)) {
            await transaction.delete(
              'outbox',
              where: 'id=? AND auth_tag=?',
              whereArgs: [row['id'], session.tag],
            );
          } else {
            result.add(row);
          }
        }
        return result;
      }),
    );
  }

  Future<void> _rejectOutbox(
    String id,
    String path,
    ApiFailure error,
    _Session session,
  ) => _database(
    () => _callCommand(path)
        ? db!.delete(
            'outbox',
            where: 'id=? AND auth_tag=?',
            whereArgs: [id, session.tag],
          )
        : db!.update(
            'outbox',
            {'state': 'failed', 'error': error.message},
            where: 'id=? AND auth_tag=?',
            whereArgs: [id, session.tag],
          ),
  );

  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (!signedIn) throw ApiFailure(401, 'Войдите в приложение');
    if (!online && !offlineSubmission) {
      throw ApiFailure(503, 'Для этого действия нужен интернет');
    }
    final session = _Session(this);
    final id = const Uuid().v4();
    await _database(
      () => db!.transaction((transaction) async {
        final identity = await transaction.query('identity', where: 'id=1');
        if (!session.matches(this) ||
            identity.isEmpty ||
            identity.single['tag'] != session.tag) {
          throw _SessionChanged();
        }
        await transaction.insert('outbox', {
          'id': id,
          'path': path,
          'method': method,
          'body': jsonEncode(body),
          'files': jsonEncode(files),
          'state': 'pending',
          'auth_tag': session.tag,
        });
      }),
    );
    if (!online && offlineSubmission) {
      await queueOutboxSync();
      notifyListeners();
      return {
        'queued': true,
        'message': 'Сохранено. Отправим после подключения',
      };
    }
    try {
      final result = await sendOutbox(
        (await db!.query('outbox', where: 'id=?', whereArgs: [id])).single,
      );
      await _checkSession(session);
      _requireCurrent(session);
      await refreshAfterChange();
      _requireCurrent(session);
      if (result['queued'] == true) await queueOutboxSync();
      return result;
    } on ApiFailure catch (error) {
      if (!session.matches(this)) rethrow;
      await _checkSession(session);
      _requireCurrent(session);
      if (error.status == 401) {
        await logout(remote: false);
        rethrow;
      }
      if (error.status < 500) {
        await _rejectOutbox(id, path, error, session);
        final reviewChanged =
            error.status == 409 &&
            path.startsWith('/v1/tasks/') &&
            path.endsWith('/actions') &&
            const [
              'approve',
              'complete',
              'return',
              'not_completed',
            ].contains(body['action']);
        final redemptionChanged =
            (error.status == 409 && path == '/v1/redemptions') ||
            ((error.status == 403 || error.status == 409) &&
                path.startsWith('/v1/redemptions/') &&
                path.endsWith('/actions'));
        final penaltyChanged =
            error.status == 409 &&
            path.startsWith('/v1/penalties/') &&
            (path.endsWith('/approve') || path.endsWith('/waive'));
        final gradeChanged =
            (error.status == 409 || error.status == 404) &&
            (path == '/v1/grades' || path.startsWith('/v1/grades/'));
        final taskChanged =
            error.status == 409 &&
            path.startsWith('/v1/tasks/') &&
            (method == 'PUT' ||
                path.endsWith('/plan') ||
                (path.endsWith('/actions') &&
                    const [
                      'cancel',
                      'reschedule',
                      'stop_repeat',
                      'approve_finances',
                    ].contains(body['action'])));
        final calendarChanged =
            (error.status == 409 || error.status == 404) &&
            path.startsWith('/v1/schedules/');
        final rewardChanged =
            (error.status == 409 || error.status == 404) &&
            (path.startsWith('/v1/rewards/') ||
                ((path == '/v1/redemptions' || path == '/v1/goal') &&
                    body['reward_id'] != null));
        final permissionsChanged =
            error.status == 409 && path.startsWith('/v1/members/');
        if (reviewChanged ||
            redemptionChanged ||
            penaltyChanged ||
            gradeChanged ||
            taskChanged ||
            calendarChanged ||
            rewardChanged ||
            permissionsChanged) {
          // Another family member may have changed the result or payout owner.
          // Refresh before showing the original error;
          // ownership checks stay on the server, and rejected actions stay failed.
          _requireCurrent(session);
          await refreshAfterChange();
          _requireCurrent(session);
        }
      }
      if (error.status >= 500) {
        await queueOutboxSync();
        if (method == 'POST' &&
            RegExp(r'^/v1/rooms/[^/]+/messages$').hasMatch(path)) {
          // The message is already durably queued. Leaving its composer draft
          // after a temporary server failure lets a second tap create a duplicate.
          // Financial commands retain the explicit uncertainty error below.
          _requireCurrent(session);
          online = false;
          notifyListeners();
          return {
            'queued': true,
            'message': 'Сообщение сохранено. Отправим после подключения',
          };
        }
        _requireCurrent(session);
        throw QueuedCommandFailure(error.status, error.message, commandId: id);
      }
      rethrow;
    } on TlsException {
      if (session.matches(this)) online = false;
    } on SocketException {
      if (session.matches(this)) online = false;
    } on TimeoutException {
      if (session.matches(this)) online = false;
    } on http.ClientException {
      if (session.matches(this)) online = false;
    }
    await _checkSession(session);
    await queueOutboxSync();
    notifyListeners();
    return {
      'queued': true,
      'message': path.startsWith('/v1/members/')
          ? 'Связь оборвалась. Изменение доступа ещё не подтверждено. Проверим после подключения'
          : path.startsWith('/v1/tasks/') &&
                body['action'] == 'approve_finances'
          ? 'Связь оборвалась. Согласование условий ещё не подтверждено. Проверим после подключения'
          : offlineSubmission
          ? 'Сохранено. Отправим после подключения'
          : 'Связь оборвалась. Действие сохранено для сверки; не повторяйте выдачу',
    };
  }

  Future<Map<String, dynamic>> sendOutbox(Map<String, Object?> row) async {
    final session = _Session(this);
    final previousOwner = row['lease_owner'] as String? ?? '';
    final alive = previousOwner.isEmpty
        ? null
        : await familyOutboxOwnerAlive(previousOwner);
    final abandonedOwner =
        alive == false ||
            (alive == null &&
                _processIdentity != null &&
                previousOwner.isNotEmpty &&
                previousOwner != _processIdentity)
        ? previousOwner
        : null;
    final acquired = await _database(
      () => db!.transaction((transaction) async {
        final identity = await transaction.query('identity', where: 'id=1');
        if (identity.isEmpty ||
            !session.matches(this) ||
            identity.single['tag'] != session.tag ||
            row['auth_tag'] != session.tag) {
          throw _SessionChanged();
        }
        final lease = DateTime.now().millisecondsSinceEpoch;
        final owner = _processIdentity;
        final count = await transaction.update(
          'outbox',
          {'lease_until': lease + 300000, 'lease_owner': owner ?? ''},
          where:
              'id=? AND auth_tag=? AND state=? AND (lease_until<=?'
              '${abandonedOwner == null ? '' : " OR lease_owner=?"})',
          whereArgs: [
            row['id'],
            session.tag,
            'pending',
            lease,
            ?abandonedOwner,
          ],
        );
        if (count != 1) return null;
        // Another sender may have already uploaded the photos before a retry.
        return (await transaction.query(
          'outbox',
          where: 'id=?',
          whereArgs: [row['id']],
        )).single;
      }),
    );
    if (acquired == null) {
      return {'queued': true, 'message': 'Действие уже отправляется'};
    }
    try {
      await _checkSession(session);
      return await _sendAcquired(acquired, session);
    } finally {
      await _database(
        () => db!.update(
          'outbox',
          {'lease_until': 0, 'lease_owner': ''},
          where: 'id=? AND auth_tag=? AND lease_owner=?',
          whereArgs: [row['id'], row['auth_tag'], _processIdentity ?? ''],
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _sendAcquired(
    Map<String, Object?> row,
    _Session session,
  ) async {
    final body = Map<String, dynamic>.from(
      jsonDecode(row['body'] as String) as Map,
    );
    final files = (jsonDecode(row['files'] as String) as List).cast<String>();
    if (files.isNotEmpty) {
      final taskId = (row['path'] as String).split('/')[3];
      final ids = <String>[];
      for (final path in files) {
        await _checkSession(session);
        ids.add((await _upload(path, 'task', taskId, session))['id'] as String);
        await _checkSession(session);
      }
      body['attachment_ids'] = ids;
      // Persist uploaded IDs before the command. Retry must send the identical payload.
      final saved = await _database(
        () => db!.update(
          'outbox',
          {'body': jsonEncode(body), 'files': '[]'},
          where: 'id=? AND auth_tag=? AND lease_owner=?',
          whereArgs: [row['id'], session.tag, row['lease_owner']],
        ),
      );
      if (saved == 0) return {'queued': true};
    }
    await _checkSession(session);
    final owned = await db!.query(
      'outbox',
      columns: ['id'],
      where: 'id=? AND auth_tag=? AND lease_owner=?',
      whereArgs: [row['id'], session.tag, row['lease_owner']],
    );
    if (owned.isEmpty) return {'queued': true};
    final command = http.Request(
      row['method'] as String,
      _uriAt(session.endpoint, row['path'] as String),
    );
    command.followRedirects = false;
    command.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.token}',
      'Idempotency-Key': row['id'] as String,
    });
    command.body = jsonEncode(body);
    final result = await _performRequest(command, session: session);
    await _checkSession(session);
    final removed = await _database(
      () => db!.delete(
        'outbox',
        where: 'id=? AND auth_tag=? AND lease_owner=?',
        whereArgs: [row['id'], session.tag, row['lease_owner']],
      ),
    );
    if (removed == 1) {
      for (final path in files) {
        await File(path).delete().catchError((_) => File(path));
      }
    }
    return result;
  }

  Future<void> refreshAfterChange() async {
    final session = _Session(this);
    _counterRevision++;
    final active = _syncOwner?.matches(this) == true ? _syncInFlight : null;
    if (active != null) await active;
    if (session.matches(this)) await sync();
  }

  Future<void> sync() {
    if (!signedIn) return Future<void>.value();
    final active = _syncInFlight;
    if (active != null && _syncOwner?.matches(this) == true) return active;
    final session = _Session(this);
    _syncOwner = session;
    syncing = true;
    late final Future<void> pendingSync;
    pendingSync = _syncOnce(session).whenComplete(() {
      if (identical(_syncInFlight, pendingSync)) {
        _syncInFlight = null;
        _syncOwner = null;
        syncing = false;
      }
      notifyListeners();
    });
    _syncInFlight = pendingSync;
    return pendingSync;
  }

  Future<void> _syncOnce(_Session session) async {
    final epoch = session.generation;
    try {
      for (final row in await pending()) {
        if (epoch != generation) return;
        if (row['state'] == 'failed') continue;
        try {
          final result = await sendOutbox(row);
          if (result['queued'] == true) break;
        } on ApiFailure catch (error) {
          if (error.status == 401) rethrow;
          if (error.status >= 500) break;
          await _rejectOutbox(
            row['id'] as String,
            row['path'] as String,
            error,
            session,
          );
        } on FileSystemException {
          await _rejectOutbox(
            row['id'] as String,
            row['path'] as String,
            ApiFailure(
              422,
              'Файл задания недоступен. Прикрепите фото повторно',
            ),
            session,
          );
        } on TlsException {
          break;
        } on SocketException {
          break;
        } on TimeoutException {
          break;
        } on http.ClientException {
          break;
        }
      }
      final revision = _counterRevision;
      final fresh = await request('/v1/snapshot');
      _requireCurrent(session);
      if (revision != _counterRevision) return;
      if (!roles.contains(fresh['user']?['role'])) {
        throw ApiFailure(401, 'Изменён семейный доступ');
      }
      if (!await _cacheFor(fresh, session, recover: true)) return;
      _requireCurrent(session);
      if (revision != _counterRevision) return;
      snapshot = fresh;
      online = true;
    } on ApiFailure catch (error) {
      if (!session.matches(this)) return;
      if (error is _SessionChanged) return;
      // A background connection can retain old credentials after another
      // connection has logged in. It must not alter the newer identity.
      final identity = await db!.query('identity', where: 'id=1');
      if (!session.matches(this) ||
          (identity.isNotEmpty && identity.single['tag'] != session.tag)) {
        return;
      }
      online = false;
      if (error.status == 401 || error.status == 403) {
        await logout(remote: false);
      }
    } on TlsException {
      if (session.matches(this)) online = false;
    } on SocketException {
      if (session.matches(this)) online = false;
    } on TimeoutException {
      if (session.matches(this)) online = false;
    } on http.ClientException {
      if (session.matches(this)) online = false;
    }
  }

  Future<Map<String, dynamic>> upload(
    String path,
    String contextType,
    String contextId,
  ) async {
    return _upload(path, contextType, contextId, _Session(this));
  }

  Future<Map<String, dynamic>> _upload(
    String path,
    String contextType,
    String contextId,
    _Session session,
  ) async {
    await _checkSession(session);
    final request = http.MultipartRequest(
      'POST',
      _uriAt(session.endpoint, '/v1/attachments', {
        'context_type': contextType,
        'context_id': contextId,
      }),
    );
    request.followRedirects = false;
    request.headers['Authorization'] = 'Bearer ${session.token}';
    request.files.add(await http.MultipartFile.fromPath('file', path));
    await _checkSession(session);
    _requireCurrent(session);
    final response = await _send(request, const Duration(seconds: 45));
    await _checkSession(session);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    if (response.statusCode != 200) {
      throw ApiFailure(
        response.statusCode,
        decoded['detail'] is String
            ? decoded['detail'] as String
            : 'Не удалось отправить файл',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<File> attachment(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(id)) {
      throw ApiFailure(400, 'Неверный номер вложения');
    }
    final session = _Session(this);
    await _checkSession(session);
    final folder = Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'attachments',
        session.tag,
      ),
    );
    final file = File(p.join(folder.path, id));
    Future<File?> saved() async {
      await _checkSession(session);
      if (!await file.exists() || await file.length() == 0) return null;
      await _checkSession(session);
      return file;
    }

    if (!online) {
      final cached = await saved();
      if (cached != null) return cached;
    }
    File? partial;
    try {
      final request = http.Request(
        'GET',
        _uriAt(session.endpoint, '/v1/attachments/$id'),
      );
      request.followRedirects = false;
      request.headers['Authorization'] = 'Bearer ${session.token}';
      _requireCurrent(session);
      final response = await _send(request, const Duration(seconds: 25));
      if (response.statusCode != 200) {
        await _checkSession(session);
        if (response.statusCode == 401) {
          await logout(remote: false);
        } else if ((response.statusCode == 403 || response.statusCode == 404) &&
            await file.exists()) {
          // A known denial must also apply to the next offline opening.
          await file.delete();
        }
        throw ApiFailure(response.statusCode, 'Вложение недоступно');
      }
      if (response.bodyBytes.isEmpty) {
        throw ApiFailure(502, 'Семейный сервер вернул пустое вложение');
      }
      await _checkSession(session);
      await folder.create(recursive: true);
      partial = File(p.join(folder.path, '$id.${const Uuid().v4()}.part'));
      await partial.writeAsBytes(response.bodyBytes, flush: true);
      await _checkSession(session);
      final complete = await partial.rename(file.path);
      partial = null;
      return await _verifyOwnedFile(complete, session);
    } catch (error) {
      final temporary =
          error is SocketException ||
          error is TlsException ||
          error is TimeoutException ||
          error is http.ClientException ||
          (error is ApiFailure && error.status >= 500);
      if (temporary) {
        final cached = await saved();
        if (cached != null) return cached;
      }
      rethrow;
    } finally {
      final staged = partial;
      if (staged != null) {
        await staged.delete().catchError((_) => staged);
      }
    }
  }
}
