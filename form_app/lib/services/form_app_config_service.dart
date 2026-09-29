import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages downloading and caching of custom form app assets from the desktop
/// server.
///
/// Cache directory: `<appCacheDir>/form_app_assets/`
/// Config cache: [SharedPreferences] stores hashes of cached files.
///
/// This is entirely outside CRDT synchronization — it only handles the
/// welcome screen customization assets (logo, background, videos).
class FormAppConfigService {
  static final FormAppConfigService instance =
      FormAppConfigService._internal();
  factory FormAppConfigService() => instance;
  FormAppConfigService._internal();

  static const String _prefKeyConfig = 'form_app_cached_config';

  Directory? _cacheDir;
  Directory? _videosCacheDir;
  Map<String, dynamic>? _cachedConfig;
  bool _initialized = false;

  /// Initialize the cache directory.
  Future<void> init() async {
    if (_initialized) return;

    final appCacheDir = await getApplicationCacheDirectory();
    _cacheDir = Directory(p.join(appCacheDir.path, 'form_app_assets'));
    _videosCacheDir = Directory(p.join(_cacheDir!.path, 'videos'));

    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    if (!await _videosCacheDir!.exists()) {
      await _videosCacheDir!.create(recursive: true);
    }

    // Load previously cached config
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_prefKeyConfig);
    if (configJson != null) {
      try {
        _cachedConfig = jsonDecode(configJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    _initialized = true;
  }

  /// Sync assets from the desktop server.
  ///
  /// Fetches `/api/form-config` to get the current config with hashes,
  /// then downloads any assets whose hashes differ from what we have cached.
  /// Reports progress via optional [onProgress] callback.
  Future<void> syncAssets(
    String baseUrl,
    Map<String, String> headers, {
    void Function(String status, double progress)? onProgress,
  }) async {
    try {
      onProgress?.call('Initializing cache...', 0.1);
      await init();

      onProgress?.call('Fetching configuration from desktop...', 0.2);
      // Fetch the current config from desktop
      final configResponse = await http
          .get(
            Uri.parse('$baseUrl/api/form-config'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (configResponse.statusCode != 200) {
        debugPrint(
            '[FormAppConfig] Config fetch failed: ${configResponse.statusCode}');
        onProgress?.call('Configuration loaded', 1.0);
        return;
      }

      final remoteConfig =
          jsonDecode(configResponse.body) as Map<String, dynamic>;
      final oldConfig = _cachedConfig ?? {};

      onProgress?.call('Syncing branding & assets...', 0.35);
      // Sync logo
      await _syncSingleAsset(
        baseUrl: baseUrl,
        headers: headers,
        remoteEntry: remoteConfig['logo'] as Map<String, dynamic>?,
        oldEntry: oldConfig['logo'] as Map<String, dynamic>?,
        assetType: 'logo',
        endpoint: '/api/assets/logo',
      );

      // Sync background
      await _syncSingleAsset(
        baseUrl: baseUrl,
        headers: headers,
        remoteEntry: remoteConfig['background'] as Map<String, dynamic>?,
        oldEntry: oldConfig['background'] as Map<String, dynamic>?,
        assetType: 'background',
        endpoint: '/api/assets/background',
      );

      // Sync videos
      final remoteVideos =
          (remoteConfig['videos'] as List<dynamic>?) ?? [];
      final oldVideos =
          (oldConfig['videos'] as List<dynamic>?) ?? [];

      // Remove videos that no longer exist on the server
      for (int i = remoteVideos.length; i < oldVideos.length; i++) {
        final old = oldVideos[i] as Map<String, dynamic>;
        final fileName = old['filename'] as String?;
        if (fileName != null) {
          final file = File(p.join(_videosCacheDir!.path, fileName));
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      // Download new or changed videos
      final totalVideos = remoteVideos.length;
      for (int i = 0; i < totalVideos; i++) {
        final remote = remoteVideos[i] as Map<String, dynamic>;
        final remoteHash = remote['hash'] as String?;
        final remoteFileName = remote['filename'] as String?;

        String? oldHash;
        if (i < oldVideos.length) {
          final old = oldVideos[i] as Map<String, dynamic>;
          oldHash = old['hash'] as String?;
        }

        if (remoteHash != null &&
            remoteFileName != null &&
            remoteHash != oldHash) {
          final currentProgress = 0.4 + (((i + 1) / totalVideos) * 0.5);
          final vidName = remote['originalName'] as String? ?? 'Video ${i + 1}';
          onProgress?.call('Downloading $vidName...', currentProgress);

          await _downloadFile(
            url: '$baseUrl/api/assets/videos/$i',
            headers: headers,
            targetPath: p.join(_videosCacheDir!.path, remoteFileName),
          );
        }
      }

      // Save the new config
      _cachedConfig = remoteConfig;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyConfig, jsonEncode(remoteConfig));

      onProgress?.call('Form App ready!', 1.0);
      debugPrint('[FormAppConfig] Asset sync complete.');
    } catch (e) {
      debugPrint('[FormAppConfig] Sync error (non-fatal): $e');
      onProgress?.call('Ready', 1.0);
    }
  }

  /// Returns an [ImageProvider] for the custom logo, or null if not cached.
  ImageProvider? getLogoProvider() {
    if (_cachedConfig == null) return null;
    final logoEntry = _cachedConfig!['logo'] as Map<String, dynamic>?;
    if (logoEntry == null) return null;

    final fileName = logoEntry['filename'] as String?;
    if (fileName == null || _cacheDir == null) return null;

    final file = File(p.join(_cacheDir!.path, fileName));
    if (!file.existsSync()) return null;

    return FileImage(file);
  }

  /// Returns an [ImageProvider] for the custom background, or null.
  ImageProvider? getBackgroundProvider() {
    if (_cachedConfig == null) return null;
    final bgEntry = _cachedConfig!['background'] as Map<String, dynamic>?;
    if (bgEntry == null) return null;

    final fileName = bgEntry['filename'] as String?;
    if (fileName == null || _cacheDir == null) return null;

    final file = File(p.join(_cacheDir!.path, fileName));
    if (!file.existsSync()) return null;

    return FileImage(file);
  }

  /// Returns a list of cached video file paths.
  /// Empty list means use the default bundled video.
  List<String> getVideoPaths() {
    if (_cachedConfig == null) return [];
    final videos = (_cachedConfig!['videos'] as List<dynamic>?) ?? [];
    if (videos.isEmpty) return [];

    final paths = <String>[];
    for (final entry in videos) {
      final data = entry as Map<String, dynamic>;
      final fileName = data['filename'] as String?;
      if (fileName == null || _videosCacheDir == null) continue;

      final file = File(p.join(_videosCacheDir!.path, fileName));
      if (file.existsSync()) {
        paths.add(file.path);
      }
    }
    return paths;
  }

  /// Whether there are any custom assets configured.
  bool get hasCustomConfig =>
      _cachedConfig != null &&
      (_cachedConfig!['logo'] != null ||
          _cachedConfig!['background'] != null ||
          (_cachedConfig!['videos'] as List<dynamic>?)?.isNotEmpty == true);

  // ── Internal helpers ──────────────────────────────────────────────────

  Future<void> _syncSingleAsset({
    required String baseUrl,
    required Map<String, String> headers,
    required Map<String, dynamic>? remoteEntry,
    required Map<String, dynamic>? oldEntry,
    required String assetType,
    required String endpoint,
  }) async {
    if (remoteEntry == null) {
      // No custom asset on server — remove cached file if any
      if (oldEntry != null) {
        final oldFileName = oldEntry['filename'] as String?;
        if (oldFileName != null && _cacheDir != null) {
          final file = File(p.join(_cacheDir!.path, oldFileName));
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      return;
    }

    final remoteHash = remoteEntry['hash'] as String?;
    final remoteFileName = remoteEntry['filename'] as String?;
    final oldHash = oldEntry?['hash'] as String?;

    if (remoteHash == null || remoteFileName == null) return;

    // Skip if hash unchanged
    if (remoteHash == oldHash) {
      final file = File(p.join(_cacheDir!.path, remoteFileName));
      if (await file.exists()) return;
    }

    // Remove old file if filename changed
    if (oldEntry != null) {
      final oldFileName = oldEntry['filename'] as String?;
      if (oldFileName != null && oldFileName != remoteFileName) {
        final oldFile = File(p.join(_cacheDir!.path, oldFileName));
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }
    }

    await _downloadFile(
      url: '$baseUrl$endpoint',
      headers: headers,
      targetPath: p.join(_cacheDir!.path, remoteFileName),
    );
  }

  Future<void> _downloadFile({
    required String url,
    required Map<String, String> headers,
    required String targetPath,
  }) async {
    try {
      debugPrint('[FormAppConfig] Downloading: $url');
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final file = File(targetPath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[FormAppConfig] Saved: $targetPath '
            '(${response.bodyBytes.length} bytes)');
      } else {
        debugPrint('[FormAppConfig] Download failed for $url: '
            '${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[FormAppConfig] Download error for $url: $e');
    }
  }
}
