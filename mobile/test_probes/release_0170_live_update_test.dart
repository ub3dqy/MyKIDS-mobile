import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mykids_family/updates.dart';

void main() {
  // Create real HTTPS clients before the widget binding's HTTP test override.
  // Only native installed-app metadata is synthetic; no family login is used.
  final clients = {
    for (final role in ['child', 'papa', 'mama']) role: http.Client(),
  };
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const signer =
      '2d09cc67a8bba22f5bd7ff5138347702ab767e81cce3bb87941bc9d28997db24';
  final manifest = Uri.parse(
    'https://api.xn--80ajzgig.online/downloads/latest.json',
  );
  setUp(() {
    messenger.setMockMethodCallHandler(nativeUpdates, (call) async {
      if (call.method != 'appInfo') {
        throw StateError('This check must not download or install on a phone');
      }
      return {
        'package': 'ru.mykids.mykids_family.parent',
        'versionCode': 70,
        'signerSha256': signer,
        'updateDirectory': '/unused-synthetic-update-directory',
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(nativeUpdates, null));
  tearDownAll(() {
    for (final client in clients.values) {
      client.close();
    }
  });
  for (final actor in ['child', 'papa', 'mama']) {
    test('live 0.1.70+71 update offer for $actor', () async {
      final updates = AppUpdates(client: clients[actor]);
      try {
        final offer = await updates.check(
          manifest,
          actor == 'child' ? 'child' : 'parent',
        );
        expect(offer, isNotNull);
        expect(offer!.version, '0.1.70');
        expect(offer.versionCode, 71);
        expect(offer.role, 'family');
        expect(offer.package, 'ru.mykids.mykids_family.parent');
        expect(offer.certificate, signer);
        expect(offer.bytes, 137669965);
        expect(offer.sha, '1f956826f1c33cbceb841058bad2acc8fab1d4441e00096c75c45ce81904067b');
        expect(
          offer.url.toString(),
          'https://api.xn--80ajzgig.online/downloads/MyKIDS-0.1.70.apk',
        );
      } finally {
        updates.dispose();
      }
    });
  }
}
