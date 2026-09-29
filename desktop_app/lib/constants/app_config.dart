/// Application configuration with environment-aware settings.
///
/// The environment is determined at build time via `--dart-define=ENV=dev|prod`.
/// Defaults to 'prod' when not specified, ensuring clinic builds are always
/// safe even if the flag is forgotten.
///
/// Build commands:
///   Dev:  flutter build windows --release --dart-define=ENV=dev
///   Prod: flutter build windows --release
class AppConfig {
  AppConfig._();

  // ── Environment ─────────────────────────────────────────────────
  static const String _env = String.fromEnvironment(
    'ENV',
    defaultValue: 'prod',
  );
  static bool get isProduction => _env != 'dev';
  static String get environmentLabel => isProduction ? 'Production' : 'Dev';

  // ── App Info ────────────────────────────────────────────────────
  static const String appName = 'IskoLinic';
  static const String appPublisher = 'Iskolinic Team';

  // ── GitHub Repository ───────────────────────────────────────────
  static const String _repoOwner = 'RXAliman';
  static const String _repoName = 'iskolinic';
  static String get repoOwner => _repoOwner;
  static String get repoName => _repoName;

  // ── Update Check URLs ──────────────────────────────────────────
  // Prod: /releases/latest — only returns full (non-pre-release) releases
  // Dev:  /releases — returns all releases including pre-releases
  static const String _prodVersionUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _devVersionUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases';

  static String get versionCheckUrl =>
      isProduction ? _prodVersionUrl : _devVersionUrl;

  // ── Sync ────────────────────────────────────────────────────────
  static String get relayServerUrl => isProduction
      ? 'wss://iskolinic.onrender.com/ws'
      : 'wss://dev-iskolinic.onrender.com/ws';

  static String get databaseName =>
      isProduction ? 'clinic.db' : 'clinic_dev.db';
}
