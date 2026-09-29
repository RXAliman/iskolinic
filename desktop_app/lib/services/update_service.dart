import 'dart:convert';
import 'dart:io';

import '../constants/app_config.dart';

/// Metadata about an available update, parsed from a GitHub Release.
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
  });

  /// Parses a single GitHub Release JSON object.
  ///
  /// GitHub release format:
  /// ```json
  /// {
  ///   "tag_name": "v1.1.0",
  ///   "body": "## Changelog\n- Bug fixes",
  ///   "prerelease": false,
  ///   "assets": [
  ///     {
  ///       "name": "IskoLinic-Setup.exe",
  ///       "browser_download_url": "https://github.com/.../IskoLinic-Setup.exe"
  ///     }
  ///   ]
  /// }
  /// ```
  factory UpdateInfo.fromGitHubRelease(Map<String, dynamic> json) {
    // Extract version from tag_name, stripping leading 'v' if present
    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    // Find the installer .exe in the release assets
    final assets = json['assets'] as List<dynamic>? ?? [];
    String downloadUrl = '';
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.exe')) {
        downloadUrl = asset['browser_download_url'] as String? ?? '';
        break;
      }
    }

    return UpdateInfo(
      version: version,
      downloadUrl: downloadUrl,
      changelog: json['body'] as String? ?? '',
    );
  }
}

/// Handles checking for updates via GitHub Releases, downloading installers,
/// and launching them.
///
/// Uses the GitHub Releases API. The endpoint is determined by the build
/// environment (prod/dev) configured in [AppConfig]:
/// - **Prod**: `/releases/latest` — returns only full releases
/// - **Dev**: `/releases` — returns all releases including pre-releases
class UpdateService {
  UpdateService._();

  static const Duration _checkTimeout = Duration(seconds: 5);
  static const Duration _downloadTimeout = Duration(minutes: 5);

  // ── Version Check ─────────────────────────────────────────────

  /// Checks for a newer version via the GitHub Releases API.
  ///
  /// Returns [UpdateInfo] if a newer version is available, `null` otherwise.
  /// Returns `null` silently on any error (offline, timeout, parse error,
  /// private repo, etc.).
  static Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _checkTimeout;

      final request = await client.getUrl(
        Uri.parse(AppConfig.versionCheckUrl),
      );

      // GitHub API requires these headers
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'IskoLinic-Desktop');

      final response = await request.close().timeout(_checkTimeout);

      if (response.statusCode != 200) {
        await response.drain<void>();
        client.close();
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_checkTimeout);
      client.close();

      final decoded = jsonDecode(body);

      // Parse the release info based on the endpoint response:
      // - /releases/latest returns a single release object
      // - /releases returns an array of releases (pick the first one)
      late final UpdateInfo info;
      if (decoded is List) {
        if (decoded.isEmpty) return null;
        info = UpdateInfo.fromGitHubRelease(
          decoded.first as Map<String, dynamic>,
        );
      } else {
        info = UpdateInfo.fromGitHubRelease(decoded as Map<String, dynamic>);
      }

      if (info.downloadUrl.isEmpty) return null;

      if (_isNewerVersion(info.version, currentVersion)) {
        return info;
      }

      return null;
    } catch (_) {
      // Network error, timeout, parse error — all silently ignored.
      // The app will proceed normally without updating.
      return null;
    }
  }

  /// Fetches the release info for a specific version tag from GitHub.
  ///
  /// Tries tag formats `v1.0.2` and `1.0.2`. Returns `null` if not found
  /// or on any error.
  static Future<UpdateInfo?> fetchRelease(String version) async {
    // Try with and without 'v' prefix
    final tagsToTry = [
      'v$version',
      version,
    ];

    for (final tag in tagsToTry) {
      try {
        final url =
            'https://api.github.com/repos/${AppConfig.repoOwner}/${AppConfig.repoName}/releases/tags/$tag';
        final client = HttpClient();
        client.connectionTimeout = _checkTimeout;

        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('Accept', 'application/vnd.github+json');
        request.headers.set('User-Agent', 'IskoLinic-Desktop');

        final response = await request.close().timeout(_checkTimeout);

        if (response.statusCode != 200) {
          await response.drain<void>();
          client.close();
          continue;
        }

        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_checkTimeout);
        client.close();

        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final info = UpdateInfo.fromGitHubRelease(decoded);

        if (info.downloadUrl.isNotEmpty) {
          return info;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ── Installer Download ────────────────────────────────────────

  /// Downloads the installer from [url] to a temporary directory.
  ///
  /// Calls [onProgress] with values from 0.0 to 1.0 as the download progresses.
  /// Returns the downloaded [File], or `null` on failure.
  static Future<File?> downloadInstaller(
    String url,
    void Function(double progress)? onProgress,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _downloadTimeout;

      final request = await client.getUrl(Uri.parse(url));
      // GitHub release asset downloads require Accept header for binary
      request.headers.set('Accept', 'application/octet-stream');
      request.headers.set('User-Agent', 'IskoLinic-Desktop');

      final response = await request.close();

      if (response.statusCode != 200) {
        await response.drain<void>();
        client.close();
        return null;
      }

      final file = await _streamToFile(response, onProgress);
      client.close();
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Launches the downloaded installer and exits the current app.
  ///
  /// Uses Inno Setup's `/SILENT` flag so the installer shows only a progress
  /// bar (no wizard pages). `/CLOSEAPPLICATIONS` ensures the running instance
  /// is closed if it hasn't exited yet.
  static Future<void> launchInstallerAndExit(File installer) async {
    await Process.start(
      installer.path,
      ['/SILENT', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  // ── Private Helpers ───────────────────────────────────────────

  /// Streams an HTTP response to a temporary file with progress tracking.
  static Future<File> _streamToFile(
    HttpClientResponse response,
    void Function(double progress)? onProgress,
  ) async {
    final contentLength = response.contentLength;
    final tempDir = Directory.systemTemp;
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}IskoLinic-Update.exe',
    );

    // Delete any leftover file from a previous failed download
    if (await file.exists()) {
      await file.delete();
    }

    final sink = file.openWrite();
    int received = 0;

    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (contentLength > 0 && onProgress != null) {
        onProgress((received / contentLength).clamp(0.0, 1.0));
      }
    }

    await sink.flush();
    await sink.close();

    return file;
  }

  /// Fetches all releases from GitHub that are older than [currentVersion].
  /// Filters by pre-release suffix based on [isProduction].
  static Future<List<UpdateInfo>> fetchOlderReleases(
    String currentVersion,
    bool isProduction,
  ) async {
    try {
      final url =
          'https://api.github.com/repos/${AppConfig.repoOwner}/${AppConfig.repoName}/releases';
      final client = HttpClient();
      client.connectionTimeout = _checkTimeout;

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'IskoLinic-Desktop');

      final response = await request.close().timeout(_checkTimeout);

      if (response.statusCode != 200) {
        await response.drain<void>();
        client.close();
        return [];
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_checkTimeout);
      client.close();

      final decoded = jsonDecode(body);
      if (decoded is! List) return [];

      final releases =
          decoded
              .map((json) => UpdateInfo.fromGitHubRelease(json as Map<String, dynamic>))
              .where((info) => info.downloadUrl.isNotEmpty)
              // Filter by version (must be older)
              .where((info) => _isOlderVersion(info.version, currentVersion))
              // Filter by environment:
              // - Prod: Only show versions WITHOUT '-pre'
              // - Dev: Only show versions WITH '-pre'
              .where((info) {
                final isPre = info.version.contains('-pre');
                return isProduction ? !isPre : isPre;
              })
              .toList();

      // Sort by version descending (newest of the old ones first)
      releases.sort((a, b) => _compareVersions(b.version, a.version));

      return releases;
    } catch (_) {
      return [];
    }
  }

  /// Returns true if [remote] is older than [current].
  static bool _isOlderVersion(String remote, String current) {
    return _compareVersions(current, remote) > 0;
  }

  /// Compares two versions. Returns > 0 if v1 > v2, < 0 if v1 < v2, 0 if equal.
  static int _compareVersions(String v1, String v2) {
    final p1 = _parseVersion(v1);
    final p2 = _parseVersion(v2);

    for (int i = 0; i < 3; i++) {
      final r1 = i < p1.length ? p1[i] : 0;
      final r2 = i < p2.length ? p2[i] : 0;
      if (r1 > r2) return 1;
      if (r1 < r2) return -1;
    }
    return 0;
  }

  /// Compares two semantic version strings.
  /// Returns `true` if [remote] is newer than [current].
  ///
  /// Handles versions like "1.2.3", "1.2.3-dev", "1.2.3+4".
  static bool _isNewerVersion(String remote, String current) {
    final remoteParts = _parseVersion(remote);
    final currentParts = _parseVersion(current);

    for (int i = 0; i < 3; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false; // Versions are equal
  }

  /// Extracts numeric version parts from a version string.
  /// "1.2.3-dev+4" → [1, 2, 3]
  static List<int> _parseVersion(String version) {
    // Strip everything after a dash or plus (pre-release / build metadata)
    final base = version.split(RegExp(r'[-+]')).first;
    return base.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }
}
