import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/push_registration.dart';

void main() {
  test(
    'immediate native registration is received and listener is removed',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      final result = await awaitPushRegistration(
        registrations: events.stream,
        register: () async => events.add('registered-installation'),
      );
      expect(result, 'registered-installation');
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'registration acknowledgement is required before accepting its target',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      final acknowledgement = Completer<void>();
      var finished = false;
      final pending =
          awaitPushRegistration(
            registrations: events.stream,
            register: () {
              events.add('registered-installation');
              return acknowledgement.future;
            },
          ).then((value) {
            finished = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      acknowledgement.complete();
      expect(await pending, 'registered-installation');
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'registration failure cancels a listener waiting for an event',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      await expectLater(
        awaitPushRegistration(
          registrations: events.stream,
          register: () => throw StateError('native registration failed'),
        ),
        throwsStateError,
      );
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'stream errors are handled even before registration acknowledgement',
    () async {
      final events = StreamController<String>.broadcast(sync: true);
      await expectLater(
        awaitPushRegistration(
          registrations: events.stream,
          register: () async =>
              events.addError(StateError('registration stream failed')),
        ),
        throwsStateError,
      );
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test('missing callback and acknowledgement have a bounded wait', () async {
    final events = StreamController<String>.broadcast(sync: true);
    await expectLater(
      awaitPushRegistration(
        registrations: events.stream,
        register: () => Completer<void>().future,
        timeout: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(events.hasListener, isFalse);
    await events.close();
  });

  test('empty targets are ignored', () async {
    final events = StreamController<String>.broadcast(sync: true);
    final result = await awaitPushRegistration(
      registrations: events.stream,
      register: () async {
        events.add('');
        events.add('registered-installation');
      },
    );
    expect(result, 'registered-installation');
    expect(events.hasListener, isFalse);
    await events.close();
  });
}
