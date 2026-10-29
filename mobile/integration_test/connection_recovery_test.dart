import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/background.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/main.dart' show TodayScreen;
import 'package:mykids_family/money_screen.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite/sqflite.dart';

import '../test/field_layout_test.dart' show mountFields, revealField;

// Faults affect only this client's transport. Every successful action and
// snapshot goes through the real loopback API and its normal database.
class RecoveryTransport extends http.BaseClient {
  final inner = http.Client();
  bool offline = false, rejectWrites = false, holdNextSnapshot = false;
  String? dropReply;
  Completer<void>? held;
  final droppedKeys = <String>[], replayKeys = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw const SocketException('Synthetic connection loss');
    if (holdNextSnapshot && request.url.path == '/v1/snapshot') {
      holdNextSnapshot = false;
      held!.complete();
      await (request as http.Abortable).abortTrigger;
      throw http.RequestAbortedException(request.url);
    }
    if (rejectWrites && request.method != 'GET') {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"detail":"Temporary failure"}')),
        503,
      );
    }
    final key = request.headers['Idempotency-Key'];
    if (key != null && droppedKeys.contains(key)) replayKeys.add(key);
    final response = await inner.send(request);
    if (dropReply == request.url.path && request.method == 'POST') {
      dropReply = null;
      await response.stream.drain<void>();
      if (response.statusCode != 200 || key == null) {
        throw StateError('Expected accepted command');
      }
      droppedKeys.add(key);
      throw const SocketException('Reply lost after server commit');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

class RecoveryForeground extends BackgroundServices {
  RecoveryForeground(super.repository);
  @override
  Future<void> registerDevice() async {}
  @override
  Future<void> reminders() async {}
}

Future<FamilyRepository> recoveryConnect(
  String name,
  RecoveryTransport transport,
) async {
  final repo = FamilyRepository(client: transport)
    ..endpoint = 'http://127.0.0.1:19076';
  final login = await repo.request(
    '/v1/login',
    method: 'POST',
    body: {'username': name, 'password': 'synthetic-family-only-123'},
  );
  repo.token = login['token'] as String;
  repo.db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE cache (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE identity (id INTEGER PRIMARY KEY, tag TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE outbox (id TEXT PRIMARY KEY, path TEXT NOT NULL, method TEXT NOT NULL, body TEXT NOT NULL, files TEXT NOT NULL, state TEXT NOT NULL, error TEXT, lease_until INTEGER NOT NULL DEFAULT 0, auth_tag TEXT NOT NULL, lease_owner TEXT NOT NULL DEFAULT \'\')',
      );
    },
  );
  await repo.db!.insert('identity', {'id': 1, 'tag': repo.sessionTag});
  await repo.sync();
  return repo;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('all three sessions recover data and money without restart', (
    tester,
  ) async {
    await binding.convertFlutterSurfaceToImage();
    final clients = <String, FamilyRepository>{};
    final transports = <String, RecoveryTransport>{};
    final services = <String, RecoveryForeground>{};
    final changes = <String, StreamController<List<ConnectivityResult>>>{};
    final cases = <String>[];
    var page = 0;
    late StateSetter select;
    String now() => DateTime.now().toUtc().toIso8601String();
    String tomorrow() =>
        DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String();
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 160 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
      await tester.pumpAndSettle();
    }

    Future<void> show(int next) async {
      select(() => page = next);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await binding.takeScreenshot('reconnect-$name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(tester.takeException(), isNull);
    }

    Future<void> lose(String name) async {
      transports[name]!.offline = true;
      changes[name]!.add([ConnectivityResult.none]);
      await until(() => !clients[name]!.online);
    }

    Future<void> restore(String name) async {
      transports[name]!.offline = false;
      changes[name]!.add([ConnectivityResult.mobile]);
      await until(() => clients[name]!.online && !clients[name]!.syncing);
    }

    Future<void> verifyAll(int total, {int reserved = 0}) async {
      for (final repo in clients.values) {
        await repo.sync();
        final current = await repo.request('/v1/snapshot');
        for (final field in [
          'tasks',
          'rooms',
          'redemptions',
          'penalties',
          'grades',
          'rewards',
          'schedules',
          'schedule_exceptions',
          'goal',
        ]) {
          expect(
            repo.snapshot![field],
            current[field],
            reason: '${repo.userId}: $field',
          );
        }
        final b = repo.snapshot!['balance'];
        expect(
          (b['total'], b['reserved'], b['available']),
          (total, reserved, total - reserved),
        );
      }
    }

    Future<String> task(
      FamilyRepository actor,
      String title,
      int reward,
    ) async =>
        ((await actor.mutate('/v1/tasks', {
                      'title': title,
                      'due_at': tomorrow(),
                      'is_required': false,
                      'reward': reward,
                    }))['ids']
                    as List)
                .single
            as String;
    try {
      for (final name in ['papa', 'mama', 'kid']) {
        transports[name] = RecoveryTransport();
        clients[name] = await recoveryConnect(name, transports[name]!);
        services[name] = RecoveryForeground(clients[name]!);
        changes[name] = StreamController<List<ConnectivityResult>>();
        services[name]!.watchConnectivity(changes: changes[name]!.stream);
      }
      final identities = {
        for (final e in clients.entries) e.key: e.value.sessionTag,
      };
      final papa = clients['papa']!,
          mama = clients['mama']!,
          kid = clients['kid']!;
      final seed = await task(papa, 'Начальные монеты', 500);
      await kid.mutate('/v1/tasks/$seed/submissions', {
        'task_version': 1,
        'marked_at': now(),
      });
      await papa.mutate('/v1/tasks/$seed/actions', {'action': 'approve'});
      await verifyAll(500);
      await papa.mutate('/v1/grade-rules', {
        'amounts': {'5': 20, '4': 10, '2': -7},
      }, method: 'PUT');
      await mountFields(
        tester,
        StatefulBuilder(
          builder: (_, state) {
            select = state;
            return Scaffold(
              body: AnimatedBuilder(
                animation: Listenable.merge(clients.values.toList()),
                builder: (_, _) => IndexedStack(
                  index: page,
                  children: [
                    for (final repo in clients.values)
                      MoneyScreen(
                        repository: repo,
                        perform: (a) async {
                          await a();
                        },
                      ),
                    for (final repo in clients.values)
                      TodayScreen(repository: repo, openPage: (_) {}),
                    for (final repo in clients.values)
                      FamilyScreen(
                        repository: repo,
                        perform: (a) async {
                          await a();
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        scale: 1.2,
        screenSize: null,
      );
      var total = 500;
      for (final name in ['papa', 'mama', 'kid']) {
        final observer = clients[name]!;
        final actor = name == 'papa' ? mama : papa;
        final subject = (await actor.mutate('/v1/subjects', {
          'name': 'Предмет $name',
        }))['id'];
        final earn = await task(actor, 'Проверка для $name', 50);
        await kid.mutate('/v1/tasks/$earn/submissions', {
          'task_version': 1,
          'marked_at': now(),
        });
        final reward = (await actor.mutate('/v1/rewards', {
          'title': 'Награда для $name',
          'price': 25,
        }))['id'];
        final request = (await kid.mutate('/v1/redemptions', {
          'reward_id': reward,
          'expected_price': 25,
        }))['id'];
        await actor.mutate('/v1/redemptions/$request/actions', {
          'action': 'claim',
        });
        final late =
            ((await actor.mutate('/v1/tasks', {
                      'title': 'Просроченное для $name',
                      'due_at': DateTime.now()
                          .toUtc()
                          .subtract(const Duration(days: 2))
                          .toIso8601String(),
                      'is_required': true,
                      'penalty': 7,
                    }))['ids']
                    as List)
                .single;
        await actor.sync();
        final fine = actor
            .rows('penalties')
            .singleWhere((r) => r['source_id'] == late)['id'];
        final queued = name == 'kid'
            ? await task(actor, 'Работа без интернета', 0)
            : null;
        await verifyAll(total, reserved: 25);
        final before = jsonEncode(observer.snapshot!['balance']);
        await lose(name);
        if (name == 'kid') {
          await observer.mutate('/v1/tasks/$queued/submissions', {
            'task_version': 1,
            'marked_at': now(),
          }, offlineSubmission: true);
        } else {
          await observer.mutate('/v1/schedules', {
            'title': 'Сохранённое событие $name',
            'date': '2026-10-16',
            'start': '18:00',
            'end': '18:30',
          }, offlineSubmission: true);
        }
        final queuedKey = (await observer.pending()).single['id'];
        await actor.mutate('/v1/tasks/$earn/actions', {'action': 'approve'});
        await actor.mutate('/v1/redemptions/$request/actions', {
          'action': 'confirm',
        });
        await actor.mutate('/v1/penalties/$fine/approve', {});
        final grade = (await actor.mutate('/v1/grades', {
          'subject_id': subject,
          'date': '2026-10-16',
          'grade': 5,
          'note': name,
        }))['id'];
        await actor.mutate('/v1/grades/$grade', {
          'subject_id': subject,
          'date': '2026-10-16',
          'grade': 4,
          'note': name,
        }, method: 'PUT');
        final correction = actor
            .rows('penalties')
            .singleWhere(
              (r) => r['source_id'] == grade && r['status'] == 'pending',
            )['id'];
        await actor.mutate('/v1/penalties/$correction/approve', {});
        await actor.mutate('/v1/rewards/$reward', {
          'title': 'Новая цена $name',
          'price': 60,
        }, method: 'PUT');
        final event = (await actor.mutate('/v1/schedules', {
          'title': 'Событие $name',
          'date': '2026-10-16',
          'start': '19:00',
          'end': '19:30',
        }))['id'];
        await actor.mutate('/v1/schedules/$event', {
          'title': 'Изменённое событие $name',
          'date': '2026-10-16',
          'start': '20:00',
          'end': '20:30',
        }, method: 'PUT');
        await actor.mutate('/v1/schedules/$event', {}, method: 'DELETE');
        final cancelled = await task(actor, 'Отменяемое задание $name', 0);
        await actor.mutate('/v1/tasks/$cancelled/actions', {
          'action': 'cancel',
        });
        final room = actor
            .rows('rooms')
            .singleWhere(
              (r) =>
                  r['kind'] == 'private' &&
                  (r['contact'] as Map?)?['id'] == observer.userId,
            )['id'];
        await actor.mutate('/v1/rooms/$room/messages', {
          'text': 'Сообщение во время обрыва $name',
        });
        expect(jsonEncode(observer.snapshot!['balance']), before);
        cases.add('${name}_offline_preserves_cache');
        // A connection event without Internet must not claim recovery.
        changes[name]!.add([ConnectivityResult.wifi]);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        expect(observer.online, isFalse);
        cases.add('${name}_radio_without_internet');
        await restore(name);
        await until(
          () => observer
              .rows('grades')
              .any((r) => r['id'] == grade && r['grade'] == 4),
        );
        total += 28;
        expect(observer.snapshot!['balance']['total'], total);
        expect(await observer.pending(), isEmpty);
        expect(
          observer
              .rows('rewards')
              .singleWhere((r) => r['id'] == reward)['price'],
          60,
        );
        expect(
          observer
              .rows('rooms')
              .singleWhere((r) => r['id'] == room)['unread_count'],
          1,
        );
        expect(
          observer.rows('tasks').singleWhere((r) => r['id'] == earn)['status'],
          'completed',
        );
        expect(
          observer
              .rows('redemptions')
              .singleWhere((r) => r['id'] == request)['status'],
          'confirmed',
        );
        expect(
          observer
              .rows('penalties')
              .singleWhere((r) => r['id'] == fine)['status'],
          'applied',
        );
        expect(
          observer
              .rows('schedules')
              .any((r) => r['id'] == event && r['active'] == 1),
          isFalse,
        );
        expect(
          (await observer.db!.query(
            'outbox',
            where: 'id=?',
            whereArgs: [queuedKey],
          )),
          isEmpty,
        );
        cases.add('${name}_all_changes_recovered');
        if (name == 'kid') {
          expect(
            observer
                .rows('tasks')
                .singleWhere((r) => r['id'] == queued)['status'],
            'submitted',
          );
          await actor.mutate('/v1/tasks/$queued/actions', {
            'action': 'approve',
          });
        } else {
          expect(
            observer
                .rows('schedules')
                .any((r) => r['title'] == 'Сохранённое событие $name'),
            isTrue,
          );
        }
        cases.add('${name}_offline_action_sent');
        await verifyAll(total);
        final index = ['papa', 'mama', 'kid'].indexOf(name);
        await show(index);
        await revealField(
          tester,
          find.text(
            name == 'kid'
                ? 'Всего: $total · в заявках: 0'
                : 'Всего: $total · в заявках: 0 · доступно: $total',
          ),
        );
        await capture('$name-money');
        await show(index + 3);
        if (name != 'kid') {
          await revealField(tester, find.text('Результатов на проверке: 0'));
        }
        // Open the recovered conversation and let its real visible-message
        // receipts clear the badge, then return to the retained family list.
        await show(index + 6);
        final tile = find.widgetWithText(
          ListTile,
          actor.snapshot!['user']['name'] as String,
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await until(
          () =>
              observer
                  .rows('rooms')
                  .singleWhere((r) => r['id'] == room)['unread_count'] ==
              0,
        );
        cases.add('${name}_read_counter_cleared');
        await tester.tap(find.byTooltip('Назад'));
        await tester.pumpAndSettle();
      }
      for (final name in ['papa', 'mama']) {
        final actor = clients[name]!, transport = transports[name]!;
        final request = (await kid.mutate('/v1/redemptions', {
          'amount': 10,
        }))['id'];
        await actor.mutate('/v1/redemptions/$request/actions', {
          'action': 'claim',
        });
        transport.dropReply = '/v1/redemptions/$request/actions';
        final result = await actor.mutate('/v1/redemptions/$request/actions', {
          'action': 'confirm',
        });
        expect(result['queued'], isTrue);
        await restore(name);
        total -= 10;
        await verifyAll(total);
        for (final repo in clients.values) {
          expect(
            repo.rows('ledger').where((r) => r['source_id'] == request).length,
            1,
          );
        }
        expect(
          transport.replayKeys.contains(transport.droppedKeys.single),
          isTrue,
        );
        cases.add('${name}_lost_ack_no_double_debit');
      }
      // A temporary failure sending a saved action cannot hide newer money.
      await lose('mama');
      await mama.mutate('/v1/schedules', {
        'title': 'Повтор после ошибки',
        'date': '2026-10-16',
        'start': '17:00',
        'end': '17:30',
      }, offlineSubmission: true);
      transports['mama']!.rejectWrites = true;
      final newer = await task(papa, 'Ещё одна награда', 5);
      await kid.mutate('/v1/tasks/$newer/submissions', {
        'task_version': 1,
        'marked_at': now(),
      });
      await papa.mutate('/v1/tasks/$newer/actions', {'action': 'approve'});
      total += 5;
      await restore('mama');
      expect(mama.snapshot!['balance']['total'], total);
      expect((await mama.pending()).single['state'], 'pending');
      cases.add('temporary_outbox_failure_does_not_block_money');
      transports['mama']!.rejectWrites = false;
      await mama.sync();
      expect(await mama.pending(), isEmpty);
      expect(
        mama
            .rows('schedules')
            .where((r) => r['title'] == 'Повтор после ошибки')
            .length,
        1,
      );
      cases.add('temporary_outbox_retry_once');
      transports['kid']!
        ..holdNextSnapshot = true
        ..held = Completer<void>();
      final held = kid.sync();
      await transports['kid']!.held!.future;
      changes['kid']!.add([ConnectivityResult.wifi]);
      await until(() => kid.online && !kid.syncing);
      await held.timeout(const Duration(seconds: 2));
      expect(kid.snapshot!['balance']['total'], total);
      cases.add('old_transport_aborted_on_reconnect');
      for (final name in clients.keys) {
        await lose(name);
      }
      for (final name in clients.keys) {
        await restore(name);
      }
      await verifyAll(total);
      cases.add('all_three_disconnect_and_recover');
      for (final e in clients.entries) {
        expect(e.value.sessionTag, identities[e.key]);
        expect(await e.value.pending(), isEmpty);
      }
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'real_local_api': true,
        'independent_client_sessions': 3,
        'clients_restarted': false,
        'cases': cases,
        'idempotent_money_retry_verified': true,
        'transport_fault_injection': true,
        'radio_events_simulated': true,
        'physical_devices_tested': false,
        'fcm_transport_tested': false,
        'mobile_source_version': '0.1.37',
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final service in services.values) {
        service.dispose();
      }
      for (final change in changes.values) {
        await change.close();
      }
      for (final repo in clients.values) {
        await repo.sync();
        await repo.db?.close();
        repo.client.close();
        repo.dispose();
      }
    }
  });
}
