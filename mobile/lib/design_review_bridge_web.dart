import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get reviewGlobal;

/// Controls only synthetic data in the separately built review application.
/// No bridge is imported by the production entry point.
void installReviewBridge(
  Future<Map<String, dynamic>> Function(Map<String, String>) handler,
) {
  reviewGlobal.setProperty(
    'mykidsReviewCommand'.toJS,
    ((JSString input) {
      final values = jsonDecode(input.toDart) as Map<String, dynamic>;
      return handler(
        values.map((key, value) => MapEntry(key, value.toString())),
      ).then((result) => jsonEncode(result).toJS).toJS;
    }).toJS,
  );
}
