import 'dart:convert';

import 'package:mykids_family/design_review_repository.dart';
import 'package:mykids_family/engagement/preview_controller.dart';

/// Captured server DTOs for the exact agreed synthetic family; never in lib/.
class ProductionFixtureRepository extends DesignReviewRepository {
  final Map<String, dynamic> play;
  ProductionFixtureRepository(PreviewEngagementController preview)
    : play = {
        'child_id': 'child',
        'state': preview.state.toJson(),
        'revision': 1,
        'confirmed_total': preview.completedCount,
        'mission_tasks': <dynamic>[],
      } {
    snapshot = jsonDecode(
      jsonEncode(preview.repository.snapshot),
    ) as Map<String, dynamic>;
    variant = preview.role;
    publish();
  }
  void publish() {
    snapshot = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    snapshot!['engagement'] = [jsonDecode(jsonEncode(play))];
    notifyListeners();
  }
}
