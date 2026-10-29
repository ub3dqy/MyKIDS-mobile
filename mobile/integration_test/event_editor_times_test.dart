import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/event_editor_times_test.dart'
    show mountTimingEditor, timingEvent, tapTiming, firstLessonId;

import 'dart:convert';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'calendar editor time reconciliation, ten minute break and native safe areas',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('editor-$name');
      }

      Map<String, dynamic>? saved;
      await mountTimingEditor(
        tester,
        {...timingEvent(), 'date': null, 'weekdays': '[1]'},
        (value) => saved = value,
        native: true,
        scale: 1.2,
      );
      final save = find.byKey(const ValueKey('event-save'));
      final navigation =
          tester.view.viewPadding.bottom / tester.view.devicePixelRatio;
      expect(navigation, greaterThan(0));
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        tester.getRect(save).bottom,
        lessThanOrEqualTo(screenHeight - navigation),
      );
      await tester.ensureVisible(find.text('Сбросить ограничение').last);
      await tester.pumpAndSettle();
      await capture('save-navigation');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      saved = null;
      await mountTimingEditor(
        tester,
        timingEvent(outside: true),
        (value) => saved = value,
        native: true,
        scale: 1.2,
      );
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(find.text('Время не совпадает'), findsOneWidget);
      await capture('time-conflict');
      await tapTiming(
        tester,
        find.byKey(const ValueKey('event-use-lesson-times')),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('event-start')));
      await tester.pumpAndSettle();
      await capture('expanded-event');
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(saved!['start'], '08:00');
      expect(saved!['end'], '14:00');
      final reconciled = saved!;
      await tester.pumpWidget(const SizedBox.shrink());
      await mountTimingEditor(
        tester,
        {
          ...timingEvent(),
          'start': '08:00',
          'activities': jsonEncode([
            {
              'id': firstLessonId,
              'title': 'Занятие 1',
              'start': '08:00',
              'end': '09:00',
            },
          ]),
        },
        (_) {},
        native: true,
        scale: 1.2,
      );
      await tapTiming(tester, find.text('Добавить занятие'));
      await tester.ensureVisible(
        find.byKey(const ValueKey('activity-start-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Начало: 09:10'), findsOneWidget);
      await capture('next-lesson');
      await tester.pumpWidget(const SizedBox.shrink());
      await mountTimingEditor(
        tester,
        timingEvent(overlap: true),
        (_) {},
        native: true,
        scale: 1.2,
      );
      await tapTiming(tester, find.byKey(const ValueKey('event-save')));
      expect(find.text('Занятия пересекаются'), findsOneWidget);
      await capture('overlap-warning');
      await tester.pumpWidget(const SizedBox.shrink());
      await mountTimingEditor(
        tester,
        timingEvent(),
        (_) {},
        native: true,
        scale: 2,
      );
      await tapTiming(tester, find.byKey(const ValueKey('event-title')));
      for (
        var attempt = 0;
        attempt < 40 && tester.view.viewInsets.bottom == 0;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();
      final keyboard =
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(keyboard, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('event-save'))).bottom,
        lessThanOrEqualTo(screenHeight - keyboard),
      );
      await capture('keyboard-save');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      binding.reportData = {
        ...?binding.reportData,
        'synthetic_only': true,
        'saved_event': reconciled,
        'navigation_padding_dp': navigation,
        'native_keyboard_height_dp': keyboard,
        'next_lesson_start': '09:10',
        'outside_time_resolved': true,
        'overlap_blocked': true,
        'large_text_scale': 2,
        'physical_device_tested': false,
      };
    },
  );
}
