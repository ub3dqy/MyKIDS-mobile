import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/family_screen.dart';

import 'support/messenger_fixture.dart';
import 'support/owned_temp.dart';
import 'voice_message_safety_test.dart' show VoicePlayer;

class PhotoFixture extends MessengerFixture {
  int uploads = 0, photos = 0;
  @override
  Future<Map<String, dynamic>> upload(
    String path,
    String contextType,
    String contextId,
  ) async {
    expectSync(await File(path).length(), greaterThan(0));
    expectSync(contextType, 'room');
    expectSync(contextId, 'private');
    uploads++;
    return {'id': 'synthetic-photo'};
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    bool offlineSubmission = false,
    List<String> files = const [],
  }) async {
    if (body['attachment_id'] == 'synthetic-photo') {
      photos++;
      return {'id': 'synthetic-photo-message'};
    }
    return super.mutate(
      path,
      body,
      method: method,
      offlineSubmission: offlineSubmission,
      files: files,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late PhotoFixture repo;
  late Completer<String?> selection;
  late String photo;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mykids-chat-photo-');
    photo = '${folder.path}/photo.png';
    await File(photo).writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6qN8AAAAASUVORK5CYII=',
      ),
    );
    repo = PhotoFixture();
    selection = Completer<String?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async {
        expectSync(call.method, 'pickImage');
        return selection.future;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (_) async => null,
    );
  });
  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
    repo.client.close();
    repo.dispose();
    await deleteOwnedTestTemp(folder);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

  for (final changedAccount in [false, true]) {
    testWidgets(
      'photo returning before foreground resumes ${changedAccount ? 'cannot cross accounts' : 'is sent to its original chat'}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatScreen(
              repository: repo,
              room: repo
                  .rows('rooms')
                  .firstWhere((r) => r['kind'] == 'private'),
              audioPlayer: VoicePlayer(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        try {
          await tester.tap(find.byTooltip('Фото'));
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          if (changedAccount) {
            repo.token = 'synthetic-replacement';
            repo.generation++;
            repo.notifyListeners();
          }
          selection.complete(photo);
          await settle(tester);
          expect(repo.uploads, changedAccount ? 0 : 1);
          expect(repo.photos, changedAccount ? 0 : 1);
        } finally {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
        }
      },
    );
  }
}
