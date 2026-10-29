import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mykids_family/design_preferences.dart';
import 'package:mykids_family/design_review.dart'
    show ReviewBackground, ReviewUpdates;
import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('normal settings persist all approved worlds on Android', (
    tester,
  ) async {
    // This test runs only on the newly created acceptance emulator.
    // No family credentials are written; only the visual preference is stored.
    await const FlutterSecureStorage().delete(
      key: DesignPreferences.storageKey,
    );
    await deviceDesignPreferences.load();
    expect(gameDesign.value!.id, 'blocks');
    final repo = DesignReviewRepository();
    final originalData = jsonEncode(repo.snapshot);
    final surface = GlobalKey();
    final captures = <String, String>{};
    final validated = <String>[];
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(String name) async {
      await settle();
      final bytes = await tester.runAsync(() async {
        final boundary =
            surface.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      });
      captures[name] = base64Encode(bytes!);
    }

    await tester.pumpWidget(
      MyKidsApp(
        repository: repo,
        createBackground: ReviewBackground.new,
        createUpdates: ReviewUpdates.new,
        presentation: (context, child) => RepaintBoundary(
          key: surface,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child,
          ),
        ),
      ),
    );
    await settle();
    for (final design in GameDesign.all) {
      await tester.tap(find.byTooltip('Настройки'));
      await settle();
      await tester.tap(find.byKey(const ValueKey('appearance-settings')));
      await settle();
      final option = find.byKey(ValueKey('design-option-${design.id}'));
      await tester.scrollUntilVisible(option, 250, maxScrolls: 15);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await settle();
      expect(gameDesign.value, same(design));
      expect(
        await const FlutterSecureStorage().read(
          key: DesignPreferences.storageKey,
        ),
        design.id,
      );
      await deviceDesignPreferences.load();
      expect(gameDesign.value, same(design));
      await capture('${design.id}-picker');
      await tester.binding.handlePopRoute();
      await settle();
      await capture('${design.id}-settings');
      for (final section in const {
        'Сегодня': 'today',
        'Календарь': 'calendar-day',
        'Задания': 'tasks',
        'Монеты': 'money',
        'Семья': 'chats',
      }.entries) {
        await tester.tap(find.widgetWithText(TextButton, section.key).last);
        await capture('${design.id}-${section.value}');
      }
      expect(jsonEncode(repo.snapshot), originalData);
      validated.add(design.id);
    }
    // Yellow makes the chosen theme visible even before login on a cold start
    // of the ordinary, signed main.dart APK installed over this test harness.
    await deviceDesignPreferences.select(GameDesign.byId('comic')!);
    binding.reportData = {
      'all_five_selected_in_real_settings': validated.length == 5,
      'stored_by_android_secure_storage': true,
      'family_example_unchanged': jsonEncode(repo.snapshot) == originalData,
      'worlds': validated,
      'cold_start_expected': 'comic',
      'captures': captures,
      'scope': 'Fresh Android emulator, production widgets and actual device preference storage; synthetic family in memory, no production family writes.',
    };
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    repo.client.close();
    repo.dispose();
  });
}
