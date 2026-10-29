import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _global;
const _key = 'mykids.engagement.approval.v1';
Future<String?> readPlayPreview() async {
  final storage = _global.getProperty<JSObject>('localStorage'.toJS);
  return storage.callMethod<JSString?>('getItem'.toJS, _key.toJS)?.toDart;
}

Future<void> writePlayPreview(String value) async {
  final storage = _global.getProperty<JSObject>('localStorage'.toJS);
  storage.callMethod<JSAny?>('setItem'.toJS, _key.toJS, value.toJS);
}
