import 'package:uuid/uuid.dart';
import '../services/database_helper.dart';

/// Manages this clinic's unique node identifier.
///
/// The node ID is generated once on first launch and persisted in the
/// SQLite `meta` table so it survives across restarts.
class NodeId {
  static String? _cachedId;

  /// Returns this node's unique ID (generates + persists on first call).
  static Future<String> get() async {
    if (_cachedId != null) return _cachedId!;

    final db = DatabaseHelper.instance;
    final existing = await db.getMeta('nodeId');
    if (existing != null) {
      _cachedId = existing;
      return _cachedId!;
    }

    _cachedId = const Uuid().v4();
    await db.setMeta('nodeId', _cachedId!);
    return _cachedId!;
  }

  /// Reset cached ID (useful in tests).
  static void reset() => _cachedId = null;
}
