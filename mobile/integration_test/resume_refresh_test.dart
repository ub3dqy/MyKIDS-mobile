import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/main.dart';
import 'package:mykids_family/repository.dart';
import 'package:sqflite/sqflite.dart';

import '../test/resume_refresh_test.dart'
    show ResumeBackground, NoResumeUpdates;

class ResumeTransport extends http.BaseClient {
  final inner = http.Client();
  bool holdNext = false;
  Completer<void>? started;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (holdNext && request.url.path == '/v1/snapshot') {
      holdNext = false;
      started!.complete();
      await (request as http.Abortable).abortTrigger;
      throw http.RequestAbortedException(request.url);
    }
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

class ResumeRepository extends FamilyRepository {
  int returns = 0;
  ResumeRepository(ResumeTransport transport) : super(client: transport);
  @override
  Future<void> reconnect() {
    returns++;
    return super.reconnect();
  }
}

class LifecycleLog with WidgetsBindingObserver {
  final states = <String>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      states.add(state.name);
}

Future<ResumeRepository> connectResume(
  String name,
  ResumeTransport transport,
) async {
  final repo = ResumeRepository(transport)..endpoint = 'http://127.0.0.1:19076';
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
  testWidgets(
    'real Android Home and screen wake refresh each retained family session',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      final clients = <String, ResumeRepository>{},
          transports = <String, ResumeTransport>{};
      final control = http.Client();
      final log = LifecycleLog();
      WidgetsBinding.instance.addObserver(log);
      final cases = <String>[], proofs = <Map<String, dynamic>>[];
      String now() => DateTime.now().toUtc().toIso8601String();
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200 && !ready(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        expect(ready(), isTrue);
        await tester.pump();
      }

      Future<void> dismissSuccess() async {
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Здорово!').evaluate().isNotEmpty) {
            await tester.tap(find.text('Здорово!'));
          }
        }
        await tester.pumpAndSettle();
      }

      Future<void> nav(String title) async {
        await dismissSuccess();
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
      }

      Future<Map<String, dynamic>> cycle(
        String mode,
        List<Map<String, dynamic>> commands,
      ) async {
        final response = await control
            .post(
              Uri.parse('http://127.0.0.1:19076/test/lifecycle'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'mode': mode, 'commands': commands}),
            )
            .timeout(const Duration(seconds: 40));
        expect(response.statusCode, 200, reason: response.body);
        final result =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final proof = Map<String, dynamic>.from(result['proof'] as Map);
        proofs.add(proof);
        expect(proof['same_android_process'], isTrue);
        expect(proof['background_verified'], isTrue);
        if (mode == 'lock') expect(proof['screen_sleep_verified'], isTrue);
        return result;
      }

      Map<String, dynamic> command(
        String actor,
        String path,
        Map<String, dynamic> body, {
        String method = 'POST',
      }) => {'actor': actor, 'path': path, 'body': body, 'method': method};
      try {
        for (final name in ['papa', 'mama', 'kid']) {
          transports[name] = ResumeTransport();
          clients[name] = await connectResume(name, transports[name]!);
        }
        final identities = {
          for (final e in clients.entries) e.key: e.value.sessionTag,
        };
        final papa = clients['papa']!, kid = clients['kid']!;
        final seed =
            ((await papa.mutate('/v1/tasks', {
                      'title': 'Начальные монеты',
                      'due_at': DateTime.now()
                          .toUtc()
                          .add(const Duration(days: 1))
                          .toIso8601String(),
                      'reward': 500,
                      'is_required': false,
                    }))['ids']
                    as List)
                .single;
        await kid.mutate('/v1/tasks/$seed/submissions', {
          'task_version': 1,
          'marked_at': now(),
        });
        await papa.mutate('/v1/tasks/$seed/actions', {'action': 'approve'});
        await papa.mutate('/v1/grade-rules', {
          'amounts': {'5': 20},
        }, method: 'PUT');
        var total = 500;
        for (final name in ['papa', 'mama', 'kid']) {
          final observer = clients[name]!,
              actorName = name == 'papa' ? 'mama' : 'papa';
          final actor = clients[actorName]!;
          final work =
              ((await actor.mutate('/v1/tasks', {
                        'title': 'Проверка возврата $name',
                        'due_at': DateTime.now()
                            .toUtc()
                            .add(const Duration(days: 1))
                            .toIso8601String(),
                        'reward': 50,
                        'is_required': false,
                      }))['ids']
                      as List)
                  .single;
          await kid.mutate('/v1/tasks/$work/submissions', {
            'task_version': 1,
            'marked_at': now(),
          });
          final reward = (await actor.mutate('/v1/rewards', {
            'title': 'Награда $name',
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
                        'title': 'Просроченное $name',
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
          final subject = (await actor.mutate('/v1/subjects', {
            'name': 'Предмет $name',
          }))['id'];
          final event = (await actor.mutate('/v1/schedules', {
            'title': 'Кружок $name',
            'date': '2026-10-16',
            'start': '19:00',
            'end': '19:30',
          }))['id'];
          await observer.sync();
          await actor.sync();
          final room = actor
              .rows('rooms')
              .singleWhere(
                (r) =>
                    r['kind'] == 'private' &&
                    (r['contact'] as Map?)?['id'] == observer.userId,
              )['id'];
          final appKey = GlobalKey();
          await tester.pumpWidget(
            MyKidsApp(
              key: appKey,
              repository: observer,
              createBackground: ResumeBackground.new,
              createUpdates: NoResumeUpdates.new,
              now: () => DateTime.utc(2026, 10, 16, 12),
            ),
          );
          await tester.pumpAndSettle();
          await until(() => !observer.syncing);
          final state = appKey.currentState;
          final beforeReturns = observer.returns;
          final beforeEvents = log.states.length;
          transports[name]!
            ..holdNext = true
            ..started = Completer<void>();
          final old = observer.sync();
          await transports[name]!.started!.future;
          await cycle('home', [
            command(actorName, '/v1/tasks/$work/actions', {
              'action': 'approve',
            }),
            command(actorName, '/v1/rewards/$reward', {
              'title': 'Обновлённая награда $name',
              'price': 60,
            }, method: 'PUT'),
            command(actorName, '/v1/schedules/$event', {
              'title': 'Изменённый кружок $name',
              'date': '2026-10-16',
              'start': '20:00',
              'end': '20:30',
            }, method: 'PUT'),
            command(actorName, '/v1/rooms/$room/messages', {
              'text': 'Пока приложение свёрнуто $name',
            }),
          ]);
          total += 50;
          await until(
            () =>
                observer.snapshot!['balance']['total'] == total &&
                !observer.syncing,
          );
          await old.timeout(const Duration(seconds: 2));
          expect(observer.returns, greaterThan(beforeReturns));
          expect(identical(appKey.currentState, state), isTrue);
          final events = log.states.sublist(beforeEvents);
          expect(events, contains('paused'));
          expect(events.last, 'resumed');
          expect(
            observer
                .rows('tasks')
                .singleWhere((r) => r['id'] == work)['status'],
            'completed',
          );
          expect(
            observer
                .rows('rewards')
                .singleWhere((r) => r['id'] == reward)['price'],
            60,
          );
          expect(
            observer
                .rows('schedules')
                .singleWhere((r) => r['id'] == event)['title'],
            'Изменённый кружок $name',
          );
          cases.add('${name}_home_resume');
          cases.add('${name}_old_request_replaced');
          await dismissSuccess();
          if (name != 'kid') {
            expect(find.text('Результатов на проверке: 0'), findsOneWidget);
          }
          await nav('Семья');
          await tester.tap(
            find.widgetWithText(
              ListTile,
              actor.snapshot!['user']['name'] as String,
            ),
          );
          await until(
            () =>
                observer
                    .rows('rooms')
                    .singleWhere((r) => r['id'] == room)['unread_count'] ==
                0,
          );
          final beforeLock = observer.returns;
          await cycle('lock', [
            command(actorName, '/v1/redemptions/$request/actions', {
              'action': 'confirm',
            }),
            command(actorName, '/v1/penalties/$fine/approve', {}),
            command(actorName, '/v1/grades', {
              'subject_id': subject,
              'date': '2026-10-16',
              'grade': 5,
            }),
            command(actorName, '/v1/rewards/$reward', {}, method: 'DELETE'),
            command(actorName, '/v1/schedules/$event', {}, method: 'DELETE'),
            command(actorName, '/v1/rooms/$room/messages', {
              'text': 'После разблокировки $name',
            }),
          ]);
          total -= 12;
          await until(
            () =>
                observer.snapshot!['balance']['total'] == total &&
                !observer.syncing &&
                find.text('После разблокировки $name').evaluate().isNotEmpty &&
                observer
                        .rows('rooms')
                        .singleWhere((r) => r['id'] == room)['unread_count'] ==
                    0,
          );
          expect(observer.returns, greaterThan(beforeLock));
          expect(identical(appKey.currentState, state), isTrue);
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
            observer.rows('rewards').any((r) => r['id'] == reward),
            isFalse,
          );
          cases.add('${name}_screen_wake_chat_and_money');
          await tester.tap(find.byTooltip('Назад'));
          await tester.pump();
          await nav('Монеты');
          expect(
            find.text(
              name == 'kid'
                  ? 'Всего: $total · в заявках: 0'
                  : 'Всего: $total · в заявках: 0 · доступно: $total',
            ),
            findsOneWidget,
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pump();
          await binding.takeScreenshot('resume-$name');
          await tester.pumpWidget(const SizedBox.shrink());
        }
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
          'same_flutter_state_during_each_return': true,
          'android_home_and_sleep_commands': true,
          'lifecycle_events_from_android': true,
          'proofs': proofs,
          'cases': cases,
          'physical_devices_tested': false,
          'secure_pin_unlock_tested': false,
          'fcm_transport_tested': false,
          'mobile_source_version': '0.1.38',
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        WidgetsBinding.instance.removeObserver(log);
        control.close();
        for (final repo in clients.values) {
          await repo.sync();
          await repo.db?.close();
          repo.client.close();
          repo.dispose();
        }
      }
    },
  );
}
