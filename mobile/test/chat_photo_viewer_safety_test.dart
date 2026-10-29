import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/family_screen.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/visuals.dart';
import 'package:mykids_family/task_photo_viewer.dart';

import 'support/messenger_fixture.dart';
import 'task_photo_viewer_test.dart' show photoTransform;
import 'voice_message_safety_test.dart' show VoicePlayer;

class ChatPhotoViewerFixture extends MessengerFixture {
  Completer<File>? download;
  int attachmentRequests = 0;
  ChatPhotoViewerFixture() {
    history.clear();
    history.add({
      'id': 'photo-message',
      'sender_id': 'parent',
      'text': '',
      'attachment_id': 'photo',
      'attachment_mime': 'image/png',
      'created_at': '2026-10-12T10:00:00Z',
      'receipts': <Map<String, dynamic>>[],
    });
  }
  @override
  Future<File> attachment(String id) async {
    expectSync(id, 'photo');
    attachmentRequests++;
    return download?.future ??
        File('assets/generated/calendar-task.png').absolute;
  }
}

class PhotoPushObserver extends NavigatorObserver {
  final VoidCallback onPhotoPush;
  PhotoPushObserver(this.onPhotoPush);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) onPhotoPush();
  }
}

Future<void> mountChatPhoto(
  WidgetTester tester,
  ChatPhotoViewerFixture repo, {
  bool pushed = false,
  GameDesign? design,
  NavigatorObserver? observer,
}) async {
  gameDesign.value = design;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (_) async => null,
  );
  addTearDown(() async {
    if (repo.download?.isCompleted == false) {
      repo.download!.complete(
        File('assets/generated/calendar-task.png').absolute,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
    repo.client.close();
    repo.dispose();
    gameDesign.value = null;
  });
  final chat = ChatScreen(
    repository: repo,
    room: repo.rows('rooms').firstWhere((r) => r['id'] == 'private'),
    audioPlayer: VoicePlayer(),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: familyTheme(false),
      navigatorObservers: [?observer],
      home: pushed ? const Scaffold(body: Text('Семья')) : chat,
    ),
  );
  if (pushed) {
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute<void>(builder: (_) => chat)),
    );
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text('Открыть фото'));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> waitForChatPhoto(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    if (images.any((image) => image.image != null)) {
      // The file can finish while the full-screen route is still sliding in.
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  fail('The actual chat photo did not finish loading');
}

void main() {
  testWidgets('photo keeps its owner before the new route is first built', (
    tester,
  ) async {
    final repo = ChatPhotoViewerFixture();
    var switched = false;
    await mountChatPhoto(
      tester,
      repo,
      observer: PhotoPushObserver(() {
        switched = true;
        repo.generation++;
        repo.token = 'owner-changed-during-navigation';
        repo.notifyListeners();
      }),
    );
    for (var i = 0; i < 30 && !switched; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(switched, true);
    await tester.pumpAndSettle();
    expect(find.byType(TaskPhotoViewer, skipOffstage: false), findsNothing);
    expect(find.byType(Image, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final design in GameDesign.all) {
    testWidgets(
      '${design.id}: photo title stays readable on its dark background',
      (tester) async {
        final repo = ChatPhotoViewerFixture();
        await mountChatPhoto(tester, repo, design: design);
        await waitForChatPhoto(tester);
        final title = find.text('Фото 1 из 1');
        final text = tester.widget<Text>(title);
        final color = DefaultTextStyle.of(tester.element(title)).style
            .merge(text.style)
            .color!;
        final contrast =
            (color.computeLuminance() + .05) /
            (Colors.black.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final pushed in [false, true]) {
    testWidgets(
      'transient logout keeps the screen covering a chat photo; pushed=$pushed',
      (tester) async {
        final repo = ChatPhotoViewerFixture();
        await mountChatPhoto(tester, repo, pushed: pushed);
        await waitForChatPhoto(tester);
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Экран поверх фото')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        repo.token = null;
        repo.generation++;
        repo.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('Экран поверх фото'), findsOneWidget);
        expect(find.byType(Image, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'chat photo opens a readable zoomable full-screen viewer and returns to the chat',
    (tester) async {
      final repo = ChatPhotoViewerFixture();
      await mountChatPhoto(tester, repo);
      await waitForChatPhoto(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Увеличить'));
      await tester.pumpAndSettle();
      expect(photoTransform(tester).value.getMaxScaleOnAxis(), greaterThan(1));
      await tester.tap(find.byTooltip('Закрыть фотографию'));
      await tester.pumpAndSettle();
      expect(find.text('Открыть фото'), findsOneWidget);
      expect(repo.attachmentRequests, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visible chat photo cannot remain after switching accounts', (
    tester,
  ) async {
    final repo = ChatPhotoViewerFixture();
    await mountChatPhoto(tester, repo);
    await waitForChatPhoto(tester);
    expect(find.byType(Image), findsOneWidget);
    repo.generation++;
    repo.token = 'different-photo-owner';
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an old photo route is removed without closing the screen covering it',
    (tester) async {
      final repo = ChatPhotoViewerFixture();
      await mountChatPhoto(tester, repo);
      await waitForChatPhoto(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Другой экран')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.generation++;
      repo.token = 'different-photo-owner';
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Другой экран'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the same owner can keep viewing a downloaded photo after going offline',
    (tester) async {
      final repo = ChatPhotoViewerFixture();
      await mountChatPhoto(tester, repo);
      await waitForChatPhoto(tester);
      repo.online = false;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(repo.attachmentRequests, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
