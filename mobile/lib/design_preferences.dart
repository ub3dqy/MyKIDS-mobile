import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'design_system.dart';

/// A device preference, kept apart from the family's session and server data.
/// The approved palettes and artwork are resolved only by their stable IDs.
class DesignPreferences {
  static const storageKey = 'appearance.game_design.v1';
  final Future<String?> Function() read;
  final Future<void> Function(String id) write;
  Future<void> _writes = Future<void>.value();

  DesignPreferences({required this.read, required this.write});

  GameDesign get defaultDesign =>
      GameDesign.byId(const String.fromEnvironment('MYKIDS_DESIGN')) ??
      GameDesign.all.first;

  Future<void> load() async {
    String? saved;
    try {
      saved = await read();
    } catch (_) {
      // An optional visual preference must not prevent opening family data.
    }
    gameDesign.value = GameDesign.byId(saved ?? '') ?? defaultDesign;
  }

  Future<void> select(GameDesign design) {
    final approved = GameDesign.byId(design.id);
    if (approved == null) throw ArgumentError.value(design.id, 'design');
    final operation = _writes.then((_) async {
      await write(approved.id);
      // Apply only a successfully saved choice. A failed save keeps the
      // previous appearance, including when another selection follows it.
      gameDesign.value = approved;
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

const _designStorage = FlutterSecureStorage();
final deviceDesignPreferences = DesignPreferences(
  read: () => _designStorage.read(key: DesignPreferences.storageKey),
  write: (id) =>
      _designStorage.write(key: DesignPreferences.storageKey, value: id),
);
