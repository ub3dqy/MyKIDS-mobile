import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// These suites exercise HTTPS, databases and foreground synchronization on the
/// host. Android background jobs are exercised by their dedicated tests.
void configureLiveApiPlatform() {
  final previous = debugDefaultTargetPlatformOverride;
  setUp(() {
    debugDefaultTargetPlatformOverride = switch (Platform.operatingSystem) {
      'windows' => TargetPlatform.windows,
      'linux' => TargetPlatform.linux,
      'macos' => TargetPlatform.macOS,
      _ => previous,
    };
  });
  tearDown(() => debugDefaultTargetPlatformOverride = previous);
}
