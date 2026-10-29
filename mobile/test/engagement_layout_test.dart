import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/design_preferences.dart';
import 'package:mykids_family/design_review.dart'
    show ReviewBackground, ReviewUpdates;
import 'package:mykids_family/design_review_control.dart'
    show ReviewPageSelection;
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/visuals.dart';
import 'package:mykids_family/main.dart' as family;
import 'package:mykids_family/engagement/engagement_pages.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/preview_controller.dart';

const captureRoot = String.fromEnvironment('PLAY_CAPTURE_DIR');
final captures = <Map<String, dynamic>>[];
const cases =
    <
      String,
      ({String page, String fixture, String role, bool large, bool bottom})
    >{
      'today': (
        page: 'today',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'hero': (
        page: 'hero',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'heroes': (
        page: 'heroes',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'heroes-bottom': (
        page: 'heroes',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: true,
      ),
      'hero-name': (
        page: 'hero-name',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'wardrobe': (
        page: 'wardrobe',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'wardrobe-unlocked': (
        page: 'wardrobe',
        fixture: 'ready',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'room': (
        page: 'room',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'room-items': (
        page: 'room-items',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'room-items-bottom': (
        page: 'room-items',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: true,
      ),
      'collection': (
        page: 'collection',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'collection-bottom': (
        page: 'collection',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: true,
      ),
      'adventure': (
        page: 'adventure',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'task': (
        page: 'task',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'task-submitted': (
        page: 'task',
        fixture: 'pending',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'task-returned': (
        page: 'task',
        fixture: 'returned',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'adventure-done': (
        page: 'adventure-done',
        fixture: 'ready',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'missions': (
        page: 'missions',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'mission': (
        page: 'mission',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'mission-bottom': (
        page: 'mission',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: true,
      ),
      'mission-done': (
        page: 'mission-done',
        fixture: 'family',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'parent-review-empty': (
        page: 'parent-review',
        fixture: 'initial',
        role: 'parent',
        large: false,
        bottom: false,
      ),
      'parent-review-waiting': (
        page: 'parent-review',
        fixture: 'pending',
        role: 'parent',
        large: false,
        bottom: false,
      ),
      'mission-create': (
        page: 'mission-create',
        fixture: 'initial',
        role: 'parent',
        large: false,
        bottom: false,
      ),
      'mission-create-bottom': (
        page: 'mission-create',
        fixture: 'initial',
        role: 'parent',
        large: false,
        bottom: true,
      ),
      'parent-controls': (
        page: 'parent-controls',
        fixture: 'initial',
        role: 'parent',
        large: false,
        bottom: false,
      ),
      'adventure-setup': (
        page: 'adventure-setup',
        fixture: 'initial',
        role: 'parent',
        large: false,
        bottom: false,
      ),
      'praise': (
        page: 'praise',
        fixture: 'initial',
        role: 'parent',
        large: false,
        bottom: false,
      ),
      'hero-disabled': (
        page: 'hero',
        fixture: 'disabled',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'calendar': (
        page: 'calendar',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'tasks': (
        page: 'tasks',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'money': (
        page: 'money',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'family': (
        page: 'family',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'settings': (
        page: 'settings',
        fixture: 'initial',
        role: 'child',
        large: false,
        bottom: false,
      ),
      'today-large-text': (
        page: 'today',
        fixture: 'initial',
        role: 'child',
        large: true,
        bottom: false,
      ),
      'hero-large-text': (
        page: 'hero',
        fixture: 'family',
        role: 'child',
        large: true,
        bottom: false,
      ),
      'adventure-large-text': (
        page: 'adventure',
        fixture: 'initial',
        role: 'child',
        large: true,
        bottom: false,
      ),
      'mission-create-large-text': (
        page: 'mission-create',
        fixture: 'initial',
        role: 'parent',
        large: true,
        bottom: true,
      ),
    };

Future<void> prepare(
  PreviewEngagementController c,
  String fixture,
  String role,
) async {
  if (['pending', 'returned', 'ready', 'family'].contains(fixture)) {
    await c.submit(
      'read',
      'Прочитал 10 страниц. Больше всего понравился герой книги.',
    );
  }
  if (fixture == 'returned') {
    await c.switchRole('parent');
    await c.review(
      'read',
      approve: false,
      note: 'Расскажи ещё немного о главном герое.',
    );
  }
  if (['ready', 'family'].contains(fixture)) {
    await c.switchRole('parent');
    await c.review('read', approve: true);
    await c.switchRole('child');
    await c.submit('bag', 'Всё для уроков уже в рюкзаке.');
    await c.switchRole('parent');
    await c.review('bag', approve: true);
    await c.switchRole('child');
    await c.claimAdventure();
    await c.wear('headphones');
    await c.wear('cape');
    await c.place('lamp', 0);
    await c.place('desk', 1);
  }
  if (fixture == 'family') {
    await c.switchRole('parent');
    await c.markOwnStep('picnic', 'picnic-parent');
    await c.sendPraise('picnic', 'Горжусь тобой!');
    await c.switchRole('relative');
    await c.markOwnStep('picnic', 'picnic-relative');
    await c.switchRole('child');
    await c.claimMission('picnic');
    await c.place('trophy', 2);
  }
  if (fixture == 'disabled') {
    await c.switchRole('parent');
    await c.setEnabled('hero', false);
  }
  await c.switchRole(role);
}

Future<void> artwork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final futures = tester
        .widgetList<FutureBuilder<ui.Image>>(
          find.byWidgetPredicate(
            (w) => w is FutureBuilder<ui.Image>,
            skipOffstage: false,
          ),
        )
        .map((w) => w.future)
        .whereType<Future<ui.Image>>()
        .toList();
    final images = tester
        .widgetList<Image>(find.byType(Image, skipOffstage: false))
        .toList();
    await tester.runAsync(() async {
      await Future.wait(futures);
      if (images.isNotEmpty) {
        final context = tester.element(
          find.byType(Image, skipOffstage: false).first,
        );
        await Future.wait(
          images.map((image) => precacheImage(image.image, context)),
        );
      }
    });
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final assets = await AssetManifest.loadFromAssetBundle(rootBundle);
    await precacheRasterArtwork(
      assets.listAssets().where(
        (p) => p.endsWith('.png') && !p.contains('engagement-room-'),
      ),
    );
    await (FontLoader(
      'MyKidsNunito',
    )..addFont(rootBundle.load('assets/designs/Nunito.ttf'))).load();
    if (captureRoot.isNotEmpty) {
      final root = Directory(captureRoot).absolute;
      expect(
        root.path.replaceAll('\\', '/'),
        endsWith('design/engagement-review-2026-10-21/public/screens'),
      );
      expect(
        File('${root.parent.path}/approval.json').existsSync(),
        isFalse,
        reason:
            'A frozen approval must be preserved; create a new review version.',
      );
      root.createSync(recursive: true);
    }
  });
  tearDownAll(() {
    if (captureRoot.isNotEmpty) {
      expect(captures.length, cases.length * GameDesign.all.length);
      File('$captureRoot/manifest.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'source': 'actual shared Flutter widgets',
          'base_viewport': [412, 915],
          'large_text_viewport': [360, 800],
          'original_approved_materials_replaced': false,
          'screens': captures,
        }),
      );
    }
    gameDesign.value = null;
  });
  for (final design in GameDesign.all) {
    for (final entry in cases.entries) {
      testWidgets(
        '${design.id}/${entry.key}: real shared widgets, no clipped layout',
        (tester) async {
          debugDisableShadows = false;
          FlutterSecureStorage.setMockInitialValues({});
          final spec = entry.value;
          final c = PreviewEngagementController(
            EngagementReviewRepository(),
            save: (_) async {},
          );
          final surface = GlobalKey(), pages = ReviewPageSelection();
          try {
            await prepare(c, spec.fixture, spec.role);
            c.designId = design.id;
            gameDesign.value = design;
            tester.view.physicalSize = spec.large
                ? const Size(360, 800)
                : const Size(412, 915);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            Widget wrap(BuildContext context, Widget child) => EngagementScope(
              controller: c,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(spec.large ? 1.5 : 1),
                ),
                child: RepaintBoundary(key: surface, child: child),
              ),
            );
            const original = {
              'today': 0,
              'calendar': 1,
              'tasks': 2,
              'money': 3,
              'family': 4,
              'settings': 5,
            };
            final page = switch (spec.page) {
              'hero-name' => const HeroPage(),
              'room-items' => const RoomPage(),
              'praise' => const MissionPage(missionId: 'picnic'),
              _ =>
                original.containsKey(spec.page)
                    ? const SizedBox()
                    : engagementPage(spec.page),
            };
            if (original.containsKey(spec.page)) {
              await tester.pumpWidget(
                family.MyKidsApp(
                  repository: c.repository,
                  pageSelection: pages,
                  createBackground: ReviewBackground.new,
                  createUpdates: ReviewUpdates.new,
                  designPreferences: DesignPreferences(
                    read: () async => design.id,
                    write: c.chooseDesign,
                  ),
                  now: () {
                    final d = DateTime.now();
                    return DateTime(d.year, d.month, d.day, 16, 41);
                  },
                  presentation: (context, child) => wrap(context, child),
                ),
              );
              await tester.pump();
              pages.select(original[spec.page]!);
              await tester.pump();
            } else {
              await tester.pumpWidget(
                MaterialApp(
                  theme: design.theme(c.role == 'child'),
                  locale: const Locale('ru'),
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  supportedLocales: const [Locale('ru')],
                  builder: (context, child) => wrap(context, child!),
                  home: const SizedBox.shrink(),
                ),
              );
              tester
                  .state<NavigatorState>(find.byType(Navigator))
                  .push<void>(MaterialPageRoute(builder: (_) => page));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
            }
            await artwork(tester);
            final context =
                surface.currentContext!
                    .findAncestorStateOfType<NavigatorState>()
                    ?.context ??
                tester.element(find.byType(Scaffold).last);
            if (spec.page == 'hero-name') renameHeroDialog(context);
            if (spec.page == 'room-items') roomItemsSheet(context, 0);
            if (spec.page == 'praise') praiseDialog(context, 'picnic');
            await tester.pump();
            await artwork(tester);
            if (spec.bottom) {
              final list = find.byType(ListView).last;
              for (var attempt = 0; attempt < 5; attempt++) {
                await tester.drag(list, const Offset(0, -550));
                await tester.pump(const Duration(milliseconds: 50));
              }
              await artwork(tester);
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${design.id}/${entry.key}',
            );
            expect(find.textContaining('Сохранено в примере'), findsNothing);
            if (entry.key == 'hero-disabled') {
              expect(
                find.textContaining('Твои открытия сохранены'),
                findsOneWidget,
              );
            }
            if (captureRoot.isNotEmpty) {
              final boundary =
                  surface.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 2);
                try {
                  final bytes = (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!.buffer.asUint8List();
                  final file = File(
                    '$captureRoot/${design.id}/${entry.key}.png',
                  );
                  file.parent.createSync(recursive: true);
                  await file.writeAsBytes(bytes);
                } finally {
                  image.dispose();
                }
              });
              captures.add({
                'theme': design.id,
                'theme_name': design.name,
                'id': entry.key,
                'page': spec.page,
                'role': spec.role,
                'fixture': spec.fixture,
                'large_text': spec.large,
                'bottom': spec.bottom,
                'file': '${design.id}/${entry.key}.png',
                'status': 'captured',
                'texts': tester
                    .widgetList<Text>(find.byType(Text))
                    .map((t) => t.data)
                    .whereType<String>()
                    .toSet()
                    .toList(),
              });
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            debugDisableShadows = true;
            pages.dispose();
            c.dispose();
          }
        },
      );
    }
  }
}
