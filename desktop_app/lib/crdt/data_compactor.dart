import '../services/database_helper.dart';

/// Periodically removes ancient tombstones to prevent SQLite bloat.
///
/// Tombstoned records (isDeleted = 1) older than [daysThreshold] days
/// are permanently removed. This is safe because all sync peers should
/// have received the tombstone within 90 days.
class DataCompactor {
  static Future<int> run({int daysThreshold = 90}) async {
    final db = DatabaseHelper.instance;
    return await db.compactTombstones(daysThreshold: daysThreshold);
  }
}
