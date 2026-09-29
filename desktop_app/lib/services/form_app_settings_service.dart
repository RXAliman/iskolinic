import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages form app customization assets on the desktop side.
///
/// Stores files in: `<appDocDir>/form_app_assets/`
///   - `logo.<ext>`
///   - `background.<ext>`
///   - `videos/0.<ext>`, `videos/1.<ext>`, etc.
///
/// Persists configuration (file names, hashes) in [SharedPreferences].
/// This is completely outside CRDT synchronization.
class FormAppSettingsService {
  static final FormAppSettingsService instance =
      FormAppSettingsService._internal();
  factory FormAppSettingsService() => instance;
  FormAppSettingsService._internal();

  static const String _prefKeyLogo = 'form_app_logo';
  static const String _prefKeyBackground = 'form_app_background';
  static const String _prefKeyVideos = 'form_app_videos';

  late Directory _assetsDir;
  late Directory _videosDir;
  bool _initialized = false;

  String? _logoFileName;
  String? _logoHash;
  String? _backgroundFileName;
  String? _backgroundHash;
  List<_VideoEntry> _videos = [];

  bool get initialized => _initialized;
  bool get hasCustomLogo => _logoFileName != null;
  bool get hasCustomBackground => _backgroundFileName != null;
  bool get hasCustomVideos => _videos.isNotEmpty;
  int get videoCount => _videos.length;

  /// Initialize the service: ensure directories exist and load persisted config.
  Future<void> init() async {
    if (_initialized) return;

    final docDir = await getApplicationDocumentsDirectory();
    _assetsDir = Directory(p.join(docDir.path, 'ISKOLINIC/form_app_assets'));
    _videosDir = Directory(p.join(_assetsDir.path, 'videos'));

    if (!await _assetsDir.exists()) {
      await _assetsDir.create(recursive: true);
    }
    if (!await _videosDir.exists()) {
      await _videosDir.create(recursive: true);
    }

    await _loadConfig();
    _initialized = true;
  }

  // ── Logo ───────────────────────────────────────────────────────────────

  /// Set a custom logo from the given file path.
  /// Copies the file into the managed assets directory.
  Future<void> setLogo(String sourcePath) async {
    await _ensureInit();
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final ext = p.extension(sourcePath).toLowerCase();
    final targetName = 'logo$ext';
    final targetPath = p.join(_assetsDir.path, targetName);

    // Remove old logo if different extension
    await _removeLogoFile();

    await sourceFile.copy(targetPath);
    _logoFileName = targetName;
    _logoHash = await _computeFileHash(File(targetPath));
    await _saveConfig();
  }

  /// Remove the custom logo (revert to default bundled asset).
  Future<void> clearLogo() async {
    await _ensureInit();
    await _removeLogoFile();
    _logoFileName = null;
    _logoHash = null;
    await _saveConfig();
  }

  /// Returns the absolute file path of the custom logo, or null if not set.
  String? get logoFilePath {
    if (_logoFileName == null) return null;
    return p.join(_assetsDir.path, _logoFileName!);
  }

  // ── Background ─────────────────────────────────────────────────────────

  /// Set a custom background image from the given file path.
  Future<void> setBackground(String sourcePath) async {
    await _ensureInit();
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final ext = p.extension(sourcePath).toLowerCase();
    final targetName = 'background$ext';
    final targetPath = p.join(_assetsDir.path, targetName);

    await _removeBackgroundFile();

    await sourceFile.copy(targetPath);
    _backgroundFileName = targetName;
    _backgroundHash = await _computeFileHash(File(targetPath));
    await _saveConfig();
  }

  /// Remove the custom background (revert to default bundled asset).
  Future<void> clearBackground() async {
    await _ensureInit();
    await _removeBackgroundFile();
    _backgroundFileName = null;
    _backgroundHash = null;
    await _saveConfig();
  }

  /// Returns the absolute file path of the custom background, or null.
  String? get backgroundFilePath {
    if (_backgroundFileName == null) return null;
    return p.join(_assetsDir.path, _backgroundFileName!);
  }

  // ── Videos ─────────────────────────────────────────────────────────────

  /// Add one or more videos to the playlist.
  Future<void> addVideos(List<String> sourcePaths) async {
    await _ensureInit();
    for (final sourcePath in sourcePaths) {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) continue;

      final ext = p.extension(sourcePath).toLowerCase();
      final index = _videos.length;
      final targetName = '$index$ext';
      final targetPath = p.join(_videosDir.path, targetName);

      await sourceFile.copy(targetPath);
      final hash = await _computeFileHash(File(targetPath));

      _videos.add(
        _VideoEntry(
          fileName: targetName,
          hash: hash,
          originalName: p.basename(sourcePath),
        ),
      );
    }
    await _saveConfig();
  }

  /// Remove a video at the given index and reindex the remaining videos.
  Future<void> removeVideo(int index) async {
    await _ensureInit();
    if (index < 0 || index >= _videos.length) return;

    // Delete the file
    final filePath = p.join(_videosDir.path, _videos[index].fileName);
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    _videos.removeAt(index);

    // Reindex remaining videos
    await _reindexVideos();
    await _saveConfig();
  }

  /// Reorder a video from oldIndex to newIndex.
  Future<void> reorderVideo(int oldIndex, int newIndex) async {
    await _ensureInit();
    if (oldIndex < 0 || oldIndex >= _videos.length) return;
    if (newIndex < 0 || newIndex > _videos.length) return;

    if (oldIndex == newIndex) return;

    final item = _videos.removeAt(oldIndex);
    // If moving down the list, we need to adjust the index because the item was removed.
    // However, Flutter's ReorderableListView already handles this index adjustment before calling onReorder,
    // so we can just insert it at newIndex (with a safety bounds check).
    final insertIndex = newIndex > _videos.length ? _videos.length : newIndex;
    _videos.insert(insertIndex, item);

    await _reindexVideos();
    await _saveConfig();
  }

  /// Remove all custom videos.
  Future<void> clearAllVideos() async {
    await _ensureInit();
    for (final entry in _videos) {
      final file = File(p.join(_videosDir.path, entry.fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }
    _videos.clear();
    await _saveConfig();
  }

  /// Returns the absolute file path of a video at the given index, or null.
  String? getVideoFilePath(int index) {
    if (index < 0 || index >= _videos.length) return null;
    return p.join(_videosDir.path, _videos[index].fileName);
  }

  /// Returns the original filename of a video at the given index.
  String? getVideoOriginalName(int index) {
    if (index < 0 || index >= _videos.length) return null;
    return _videos[index].originalName;
  }

  /// Returns a list of all video original names.
  List<String> get videoOriginalNames =>
      _videos.map((v) => v.originalName).toList();

  /// Returns the hash of a video at the given index.
  String? getVideoHash(int index) {
    if (index < 0 || index >= _videos.length) return null;
    return _videos[index].hash;
  }

  // ── Config for HTTP serving ────────────────────────────────────────────

  /// Returns a JSON-serializable map describing the current form app config.
  /// Used by the HTTP server to send to the input app.
  Map<String, dynamic> getConfig() {
    return {
      'logo': _logoFileName != null
          ? {'filename': _logoFileName, 'hash': _logoHash}
          : null,
      'background': _backgroundFileName != null
          ? {'filename': _backgroundFileName, 'hash': _backgroundHash}
          : null,
      'videos': _videos
          .map(
            (v) => {
              'index': _videos.indexOf(v),
              'filename': v.fileName,
              'hash': v.hash,
              'originalName': v.originalName,
            },
          )
          .toList(),
    };
  }

  /// Returns the File for a given asset type. Used by the HTTP server.
  File? getAssetFile(String assetType, [int? index]) {
    switch (assetType) {
      case 'logo':
        final path = logoFilePath;
        if (path == null) return null;
        final file = File(path);
        return file.existsSync() ? file : null;
      case 'background':
        final path = backgroundFilePath;
        if (path == null) return null;
        final file = File(path);
        return file.existsSync() ? file : null;
      case 'video':
        if (index == null) return null;
        final path = getVideoFilePath(index);
        if (path == null) return null;
        final file = File(path);
        return file.existsSync() ? file : null;
      default:
        return null;
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Logo
    final logoJson = prefs.getString(_prefKeyLogo);
    if (logoJson != null) {
      try {
        final data = jsonDecode(logoJson) as Map<String, dynamic>;
        _logoFileName = data['fileName'] as String?;
        _logoHash = data['hash'] as String?;

        // Verify file still exists
        if (_logoFileName != null) {
          final file = File(p.join(_assetsDir.path, _logoFileName!));
          if (!await file.exists()) {
            _logoFileName = null;
            _logoHash = null;
          }
        }
      } catch (_) {}
    }

    // Background
    final bgJson = prefs.getString(_prefKeyBackground);
    if (bgJson != null) {
      try {
        final data = jsonDecode(bgJson) as Map<String, dynamic>;
        _backgroundFileName = data['fileName'] as String?;
        _backgroundHash = data['hash'] as String?;

        if (_backgroundFileName != null) {
          final file = File(p.join(_assetsDir.path, _backgroundFileName!));
          if (!await file.exists()) {
            _backgroundFileName = null;
            _backgroundHash = null;
          }
        }
      } catch (_) {}
    }

    // Videos
    final videosJson = prefs.getString(_prefKeyVideos);
    if (videosJson != null) {
      try {
        final list = jsonDecode(videosJson) as List<dynamic>;
        _videos = [];
        for (final item in list) {
          final data = item as Map<String, dynamic>;
          final fileName = data['fileName'] as String;
          final file = File(p.join(_videosDir.path, fileName));
          if (await file.exists()) {
            _videos.add(
              _VideoEntry(
                fileName: fileName,
                hash: data['hash'] as String,
                originalName: data['originalName'] as String? ?? fileName,
              ),
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Logo
    if (_logoFileName != null) {
      await prefs.setString(
        _prefKeyLogo,
        jsonEncode({'fileName': _logoFileName, 'hash': _logoHash}),
      );
    } else {
      await prefs.remove(_prefKeyLogo);
    }

    // Background
    if (_backgroundFileName != null) {
      await prefs.setString(
        _prefKeyBackground,
        jsonEncode({'fileName': _backgroundFileName, 'hash': _backgroundHash}),
      );
    } else {
      await prefs.remove(_prefKeyBackground);
    }

    // Videos
    if (_videos.isNotEmpty) {
      await prefs.setString(
        _prefKeyVideos,
        jsonEncode(
          _videos
              .map(
                (v) => {
                  'fileName': v.fileName,
                  'hash': v.hash,
                  'originalName': v.originalName,
                },
              )
              .toList(),
        ),
      );
    } else {
      await prefs.remove(_prefKeyVideos);
    }
  }

  Future<void> _removeLogoFile() async {
    if (_logoFileName != null) {
      final file = File(p.join(_assetsDir.path, _logoFileName!));
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _removeBackgroundFile() async {
    if (_backgroundFileName != null) {
      final file = File(p.join(_assetsDir.path, _backgroundFileName!));
      if (await file.exists()) await file.delete();
    }
  }

  /// Reindex video files after a removal or reorder to keep them sequential (0, 1, 2...).
  Future<void> _reindexVideos() async {
    final tempVideos = <_VideoEntry>[];

    // Step 1: Rename all existing files to temporary names to avoid collisions during reorder
    for (int i = 0; i < _videos.length; i++) {
      final old = _videos[i];
      final oldPath = p.join(_videosDir.path, old.fileName);
      final ext = p.extension(old.fileName);
      final tempName = 'temp_${DateTime.now().microsecondsSinceEpoch}_$i$ext';
      final tempPath = p.join(_videosDir.path, tempName);

      final file = File(oldPath);
      if (await file.exists()) {
        await file.rename(tempPath);
      }

      tempVideos.add(
        _VideoEntry(
          fileName: tempName, // Temporarily store temp name
          hash: old.hash,
          originalName: old.originalName,
        ),
      );
    }

    // Step 2: Rename to final indexed names
    final newVideos = <_VideoEntry>[];
    for (int i = 0; i < tempVideos.length; i++) {
      final temp = tempVideos[i];
      final tempPath = p.join(_videosDir.path, temp.fileName);
      final ext = p.extension(temp.originalName);
      final newName = '$i$ext';
      final newPath = p.join(_videosDir.path, newName);

      final file = File(tempPath);
      if (await file.exists()) {
        await file.rename(newPath);
      }

      newVideos.add(
        _VideoEntry(
          fileName: newName,
          hash: temp.hash,
          originalName: temp.originalName,
        ),
      );
    }

    _videos = newVideos;
  }

  /// Compute SHA-256 hash of a file for cache invalidation.
  Future<String> _computeFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (e) {
      debugPrint('[FormAppSettings] Error computing hash: $e');
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }
}

class _VideoEntry {
  final String fileName;
  final String hash;
  final String originalName;

  _VideoEntry({
    required this.fileName,
    required this.hash,
    required this.originalName,
  });
}
