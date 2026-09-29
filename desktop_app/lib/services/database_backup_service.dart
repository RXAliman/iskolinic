import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/app_config.dart';

/// Information about a single database backup.
class BackupInfo {
  final File file;
  final DateTime createdAt;
  final int sizeBytes;
  final String appVersion;

  BackupInfo({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
    required this.appVersion,
  });

  String get fileName => p.basename(file.path);

  /// Human-readable size (e.g., "12.3 MB").
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Service that manages automatic and manual database backups.
///
/// Backups are stored in a `backups/` subdirectory alongside the database.
/// The naming convention is: `clinic_backup_<version>_<timestamp>.db`
///
/// **Strategy:** Backups are only created from known-good databases:
/// - After successful app initialization (not before — avoids backing up
///   corrupted databases during repeated failed restarts).
/// - Periodically while the app is running (every 2 hours by default).
///
/// Usage:
/// - Call [createBackup] after the app initializes successfully.
/// - Call [startPeriodicBackup] to enable automatic runtime backups.
/// - Call [restoreBackup] to replace the current database with a backup.
/// - Call [listBackups] to get all available backups.
class DatabaseBackupService {
  DatabaseBackupService._();

  /// Maximum number of backups to retain. Older backups are pruned automatically.
  static const int maxBackups = 10;

  static Timer? _periodicTimer;

  /// Returns the directory where backups are stored.
  static Future<Directory> _backupDir() async {
    final appDir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(appDir.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Returns the path to the live database file.
  static Future<String> _dbPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, AppConfig.databaseName);
  }

  /// Creates a backup of the current database file.
  ///
  /// Should only be called after verifying the database is healthy (e.g.,
  /// after successful app initialization). This avoids backing up corrupted
  /// databases that would push out known-good backups during rotation.
  ///
  /// Returns the [BackupInfo] of the created backup, or `null` if no backup
  /// was needed (e.g., first launch or file doesn't exist).
  static Future<BackupInfo?> createBackup(String appVersion) async {
    try {
      final dbPath = await _dbPath();
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        debugPrint('DatabaseBackupService: No existing database to back up.');
        return null;
      }

      final backupDir = await _backupDir();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final sanitizedVersion = appVersion.replaceAll('.', '_');
      final backupFileName =
          'clinic_backup_v${sanitizedVersion}_$timestamp.db';
      final backupPath = p.join(backupDir.path, backupFileName);

      // Copy the database file to the backup directory
      final backupFile = await dbFile.copy(backupPath);
      final stat = await backupFile.stat();

      debugPrint(
        'DatabaseBackupService: Backup created at $backupPath '
        '(${stat.size} bytes)',
      );

      // Prune old backups beyond the limit
      await _pruneOldBackups();

      return BackupInfo(
        file: backupFile,
        createdAt: stat.changed,
        sizeBytes: stat.size,
        appVersion: appVersion,
      );
    } catch (e) {
      debugPrint('DatabaseBackupService: Error creating backup: $e');
      return null;
    }
  }

  /// Starts periodic backups that run every [interval] (default: 2 hours).
  ///
  /// Should be called after the app initializes successfully. Each periodic
  /// backup is a file-copy of the live database, same as [createBackup].
  /// Old backups are automatically pruned beyond [maxBackups].
  static void startPeriodicBackup(
    String appVersion, {
    Duration interval = const Duration(hours: 2),
  }) {
    stopPeriodicBackup();
    _periodicTimer = Timer.periodic(interval, (_) async {
      debugPrint('DatabaseBackupService: Running periodic backup...');
      await createBackup(appVersion);
    });
    debugPrint(
      'DatabaseBackupService: Periodic backup scheduled '
      '(every ${interval.inMinutes} min)',
    );
  }

  /// Stops periodic backups.
  static void stopPeriodicBackup() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Lists all available backups, sorted newest-first.
  static Future<List<BackupInfo>> listBackups() async {
    try {
      final backupDir = await _backupDir();

      if (!await backupDir.exists()) return [];

      final entries = await backupDir
          .list()
          .where((e) => e is File && e.path.endsWith('.db'))
          .cast<File>()
          .toList();

      final backups = <BackupInfo>[];
      for (final file in entries) {
        final stat = await file.stat();
        final version = _extractVersion(p.basename(file.path));
        backups.add(BackupInfo(
          file: file,
          createdAt: stat.changed,
          sizeBytes: stat.size,
          appVersion: version,
        ));
      }

      // Sort newest first
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } catch (e) {
      debugPrint('DatabaseBackupService: Error listing backups: $e');
      return [];
    }
  }

  /// Restores a backup by replacing the current database file.
  ///
  /// **Important:** The database connection must be closed before calling this.
  /// After restoring, the app should be restarted to reinitialize the database.
  ///
  /// Returns `true` if the restore was successful.
  static Future<bool> restoreBackup(BackupInfo backup) async {
    try {
      final dbPath = await _dbPath();
      final dbFile = File(dbPath);

      // Safety: create a backup of the current state before restoring
      // (so the user can undo the restore if needed)
      final currentVersion = _extractVersion(p.basename(backup.file.path));
      await createBackup('pre_restore_$currentVersion');

      // Replace the current database with the backup
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await backup.file.copy(dbPath);

      debugPrint(
        'DatabaseBackupService: Restored backup from ${backup.fileName}',
      );
      return true;
    } catch (e) {
      debugPrint('DatabaseBackupService: Error restoring backup: $e');
      return false;
    }
  }

  /// Deletes a specific backup.
  static Future<bool> deleteBackup(BackupInfo backup) async {
    try {
      if (await backup.file.exists()) {
        await backup.file.delete();
        debugPrint(
          'DatabaseBackupService: Deleted backup ${backup.fileName}',
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('DatabaseBackupService: Error deleting backup: $e');
      return false;
    }
  }

  /// Removes old backups beyond [maxBackups], keeping the newest ones.
  static Future<void> _pruneOldBackups() async {
    try {
      final backups = await listBackups();
      if (backups.length <= maxBackups) return;

      final toDelete = backups.sublist(maxBackups);
      for (final backup in toDelete) {
        await backup.file.delete();
        debugPrint(
          'DatabaseBackupService: Pruned old backup ${backup.fileName}',
        );
      }
    } catch (e) {
      debugPrint('DatabaseBackupService: Error pruning backups: $e');
    }
  }

  /// Extracts the version string from a backup filename.
  ///
  /// Example: `clinic_backup_v1_0_2_2026-05-15T11-00-00.db` → `1.0.2`
  static String _extractVersion(String fileName) {
    final match = RegExp(r'clinic_backup_v([\d_]+)_\d{4}').firstMatch(fileName);
    if (match != null) {
      return match.group(1)!.replaceAll('_', '.');
    }
    return 'Unknown';
  }
}
