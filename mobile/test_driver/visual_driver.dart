import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final folder = Directory('../docs/screenshots');
  await folder.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^(child|parent|relative)-today$').hasMatch(name)) {
        return false;
      }
      await File('${folder.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
  );
}
