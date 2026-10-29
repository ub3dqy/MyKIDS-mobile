import 'dart:io';

import 'package:path/path.dart' as p;

/// Remove only the caller's MyKIDS scratch folder after its database closes.
Future<void> deleteOwnedTestTemp(Directory folder) async {
  final root = await Directory.systemTemp.resolveSymbolicLinks();
  final target = await folder.resolveSymbolicLinks();
  if (!p.isWithin(root, target) || !p.basename(target).startsWith('mykids-')) {
    throw StateError('Refusing cleanup outside the owned test directory');
  }
  for (var attempt = 0; ; attempt++) {
    try {
      await folder.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      // Windows can retain just-closed SQLite sidecar handles briefly.
      // Persistent failures still fail the test and retain their diagnostic.
      if (!Platform.isWindows ||
          !{5, 32, 145}.contains(error.osError?.errorCode) ||
          attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}
