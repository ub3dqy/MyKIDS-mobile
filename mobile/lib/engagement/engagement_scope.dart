import 'package:flutter/material.dart';

import 'engagement_model.dart';

/// Absent in the published app until the new designs are approved and connected.
class EngagementScope extends InheritedNotifier<EngagementController> {
  const EngagementScope({
    super.key,
    required EngagementController controller,
    required super.child,
  }) : super(notifier: controller);
  static EngagementController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EngagementScope>()?.notifier;
  static EngagementController of(BuildContext context) => maybeOf(context)!;
}
