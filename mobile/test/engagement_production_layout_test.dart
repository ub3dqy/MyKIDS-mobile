@Tags(['production-golden'])
library;

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
import 'package:mykids_family/design_review_control.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/engagement/engagement_pages.dart';
import 'package:mykids_family/engagement/engagement_scope.dart';
import 'package:mykids_family/engagement/preview_controller.dart';
import 'package:mykids_family/engagement/production_controller.dart';
import 'package:mykids_family/main.dart' as family;
import 'package:mykids_family/visuals.dart';

import 'engagement_layout_test.dart' as agreed;
import 'support/engagement_fixture.dart';

const reference = '../design/engagement-review-2026-10-21/public/screens';
const evidence = String.fromEnvironment(
  'MYKIDS_PARITY_EVIDENCE',
  defaultValue: '../docs/engagement-release-2026-10-21',
);
final comparisons = <Map<String, dynamic>>[];

// Replaying immutable approval images must not follow the host across midnight.
// Only the synthetic test repository is pinned; ordinary app dates are unchanged.
class ApprovedDayReviewRepository extends EngagementReviewRepository {
  @override
  String get today => '2026-10-21';
  @override
  void reset() {
    super.reset();
    final current = DateTime.now();
    final day = current.toIso8601String().substring(0, 10);
    final delta = DateTime(
      current.year,
      current.month,
      current.day,
    ).difference(DateTime(2026, 10, 21)).inDays;
    String normalizeDate(String item) {
      if (item.startsWith(day)) return item.replaceFirst(day, '2026-10-21');
      final parsed = item.contains('T') ? DateTime.tryParse(item) : null;
      if (parsed != null &&
          parsed.toLocal().toIso8601String().startsWith(day)) {
        return parsed.subtract(Duration(days: delta)).toUtc().toIso8601String();
      }
      return item;
    }

    void normalize(dynamic value) {
      if (value is Map) {
        for (final key in value.keys.toList()) {
          final item = value[key];
          if (item is String) {
            value[key] = normalizeDate(item);
          } else {
            normalize(item);
          }
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          final item = value[i];
          if (item is String) {
            value[i] = normalizeDate(item);
          } else {
            normalize(item);
          }
        }
      }
    }

    normalize(snapshot);
    normalize(messages);
    snapshot!['server_time'] = '2026-10-21T13:41:00Z';
  }
}

void main() {
  setUpAll(() async {
    for (final font in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'MyKidsNunito': 'assets/designs/Nunito.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    final assets = await AssetManifest.loadFromAssetBundle(rootBundle);
    await precacheRasterArtwork(
      assets.listAssets().where(
        (p) => p.endsWith('.png') && !p.contains('engagement-room-'),
      ),
    );
  });
  tearDownAll(() {
    Directory(evidence).createSync(recursive: true);
    final reportName =
        comparisons.length == agreed.cases.length * GameDesign.all.length
        ? 'pixel-comparison.json'
        : 'pixel-comparison-subset.json';
    File('$evidence/$reportName').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'source': 'Production controller with actual agreed screen widgets, font and artwork',
        'reference_rewritten': false,
        'comparisons': comparisons,
        'total': comparisons.length,
        'all_exact': comparisons.every((r) => r['different_pixels'] == 0),
        'all_match_within_raster_rounding': comparisons.every(
          (r) =>
              (r['max_channel_delta'] as int) <= 1 &&
              (r['different_pixels'] as int) <= 12,
        ),
        'rounding_limit': 'At most 12 shadow pixels may differ by one RGB level; geometry, text and artwork may not differ.',
      }),
    );
    gameDesign.value = null;
  });
  for (final design in GameDesign.all) {
    for (final entry in agreed.cases.entries) {
      testWidgets(
        '${design.id}/${entry.key}: production adapter matches immutable approval pixels',
        (tester) async {
          debugDisableShadows = false;
          FlutterSecureStorage.setMockInitialValues({});
          final fixture = PreviewEngagementController(
            ApprovedDayReviewRepository(),
            save: (_) async {},
          );
          final spec = entry.value;
          await agreed.prepare(fixture, spec.fixture, spec.role);
          final repo = ProductionFixtureRepository(fixture);
          await repo.saveCalendarPosition(DateTime(2026, 10, 21), 'День');
          final c = ProductionEngagementController(repo);
          final pages = ReviewPageSelection(), surface = GlobalKey();
          try {
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
                  repository: repo,
                  pageSelection: pages,
                  createBackground: ReviewBackground.new,
                  createUpdates: ReviewUpdates.new,
                  designPreferences: DesignPreferences(
                    read: () async => design.id,
                    write: (_) async {},
                  ),
                  now: () {
                    return DateTime(
                      2026,
                      10,
                      21,
                      spec.page == 'today' ? 11 : 16,
                      spec.page == 'today' ? 13 : 41,
                    );
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
            await agreed.artwork(tester);
            final context = tester.element(find.byType(Scaffold).last);
            if (spec.page == 'hero-name') renameHeroDialog(context);
            if (spec.page == 'room-items') roomItemsSheet(context, 0);
            if (spec.page == 'praise') praiseDialog(context, 'picnic');
            await tester.pump();
            await agreed.artwork(tester);
            if (spec.bottom) {
              for (var i = 0; i < 5; i++) {
                await tester.drag(
                  find.byType(ListView).last,
                  const Offset(0, -550),
                );
                await tester.pump(const Duration(milliseconds: 50));
              }
              await agreed.artwork(tester);
            }
            expect(tester.takeException(), isNull);
            final boundary =
                surface.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final actual = await boundary.toImage(pixelRatio: 2);
              final codec = await ui.instantiateImageCodec(
                await File('$reference/${design.id}/${entry.key}.png')
                    .readAsBytes(),
              );
              final expected = (await codec.getNextFrame()).image;
              try {
                expect(actual.width, expected.width);
                expect(actual.height, expected.height);
                final a = (await actual.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List();
                final b = (await expected.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List();
                var different = 0, maxDelta = 0;
                for (var i = 0; i < a.length; i += 4) {
                  for (var channel = 0; channel < 4; channel++) {
                    final delta = (a[i + channel] - b[i + channel]).abs();
                    if (delta > maxDelta) maxDelta = delta;
                  }
                  if (a[i] != b[i] ||
                      a[i + 1] != b[i + 1] ||
                      a[i + 2] != b[i + 2] ||
                      a[i + 3] != b[i + 3]) {
                    different++;
                  }
                }
                comparisons.add({
                  'theme': design.id,
                  'state': entry.key,
                  'different_pixels': different,
                  'max_channel_delta': maxDelta,
                  'total_pixels': actual.width * actual.height,
                });
                if (different > 0) {
                  final file = File(
                    '$evidence/pixel-diffs/${design.id}-${entry.key}.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(
                    (await actual.toByteData(format: ui.ImageByteFormat.png))!
                        .buffer
                        .asUint8List(),
                  );
                }
                expect(
                  different <= 12 && maxDelta <= 1,
                  isTrue,
                  reason:
                      '${design.id}/${entry.key} differs from the agreed immutable screenshot',
                );
              } finally {
                actual.dispose();
                expected.dispose();
                codec.dispose();
              }
            });
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            debugDisableShadows = true;
            pages.dispose();
            c.dispose();
            repo.client.close();
            repo.dispose();
            fixture.dispose();
          }
        },
      );
    }
  }
}
