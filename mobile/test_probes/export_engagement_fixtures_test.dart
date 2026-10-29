import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/engagement/preview_controller.dart';

import '../test/engagement_layout_test.dart' as agreed;

void main() {
  test('export the agreed synthetic states for an isolated real API and downloaded APK', () async {
    final states = <String, dynamic>{};
    for (final fixture in {
      'initial',
      'pending',
      'returned',
      'ready',
      'family',
      'disabled',
    }) {
      final c = PreviewEngagementController(
        EngagementReviewRepository(),
        save: (_) async {},
      );
      try {
        await agreed.prepare(c, fixture, 'child');
        states[fixture] = {
          'snapshot': c.repository.snapshot,
          'state': c.state.toJson(),
          'messages': c.repository.messages,
          'confirmed_total': c.completedCount,
        };
      } finally {
        c.dispose();
      }
    }
    final file = File('../output/private/engagement-fixtures.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(states),
    );
    expect(states.length, 6);
  });
}
