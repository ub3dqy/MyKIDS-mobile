import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _key = 'mykids.engagement.approval.v1';
Future<String?> readPlayPreview() => _storage.read(key: _key);
Future<void> writePlayPreview(String value) =>
    _storage.write(key: _key, value: value);
