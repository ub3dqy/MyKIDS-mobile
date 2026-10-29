import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykids_family/repository.dart';

void main() {
  test(
    'credentials are never sent to an insecure or credential-bearing URL',
    () async {
      var requests = 0;
      final repo = FamilyRepository(
        client: MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      for (final server in [
        'http://example.com',
        'https://user:secret@example.com',
        'https://example.com?token=secret',
      ]) {
        repo.endpoint = server;
        await expectLater(
          repo.request(
            '/v1/login',
            method: 'POST',
            body: {'password': 'secret'},
          ),
          throwsA(isA<ApiFailure>()),
        );
      }
      expect(requests, 0);
    },
  );
  test('money amounts remain integers in outgoing commands', () async {
    final repo = FamilyRepository(
      client: MockClient((request) async {
        expect(request.body, '{"amount":100}');
        expect(request.headers['Idempotency-Key'], 'fixed-operation');
        expect(request.followRedirects, false);
        return http.Response('{"id":"saved"}', 200);
      }),
    )..endpoint = 'https://family.example';
    expect(
      await repo.request(
        '/v1/redemptions',
        method: 'POST',
        body: {'amount': 100},
        key: 'fixed-operation',
      ),
      {'id': 'saved'},
    );
  });
}
