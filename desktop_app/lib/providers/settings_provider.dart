import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/form_app_settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _keyConnectionMode = 'connection_mode';
  static const String _keyRetentionYears = 'retention_years';
  static const String _keyDeveloperMode = 'developer_mode';

  // 0: Offline, 1: LAN (Disabled), 2: Relay
  int _connectionMode = 2;
  int get connectionMode => _connectionMode;

  int _retentionYears = 5;
  int get retentionYears => _retentionYears;

  bool _isDeveloperMode = false;
  bool get isDeveloperMode => _isDeveloperMode;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Load settings from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _connectionMode = prefs.getInt(_keyConnectionMode) ?? 2;
    _retentionYears = prefs.getInt(_keyRetentionYears) ?? 5;
    _isDeveloperMode = prefs.getBool(_keyDeveloperMode) ?? false;

    // Initialize form app settings service
    await FormAppSettingsService.instance.init();

    _initialized = true;
    notifyListeners();
  }

  /// Update and persist connection mode
  Future<void> updateConnectionMode(int mode) async {
    if (mode == _connectionMode) return;

    // Safety check: Mode 1 (LAN) is currently disabled
    if (mode == 1) return;

    _connectionMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyConnectionMode, mode);
  }

  /// Update and persist retention years
  Future<void> updateRetentionYears(int years) async {
    if (years == _retentionYears) return;
    _retentionYears = years;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRetentionYears, years);
  }

  /// Toggle and persist developer mode
  Future<void> toggleDeveloperMode(bool value) async {
    if (value == _isDeveloperMode) return;
    _isDeveloperMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDeveloperMode, value);
  }

  // ── Form App Settings ──────────────────────────────────────────────────

  FormAppSettingsService get _formAppService =>
      FormAppSettingsService.instance;

  bool get hasCustomLogo => _formAppService.hasCustomLogo;
  bool get hasCustomBackground => _formAppService.hasCustomBackground;
  bool get hasCustomVideos => _formAppService.hasCustomVideos;
  int get formAppVideoCount => _formAppService.videoCount;
  String? get formAppLogoPath => _formAppService.logoFilePath;
  String? get formAppBackgroundPath => _formAppService.backgroundFilePath;
  List<String> get formAppVideoNames => _formAppService.videoOriginalNames;

  String? getFormAppVideoPath(int index) =>
      _formAppService.getVideoFilePath(index);

  String? getFormAppVideoOriginalName(int index) =>
      _formAppService.getVideoOriginalName(index);

  String? getFormAppVideoHash(int index) =>
      _formAppService.getVideoHash(index);

  Future<void> setFormAppLogo(String filePath) async {
    await _formAppService.setLogo(filePath);
    notifyListeners();
  }

  Future<void> clearFormAppLogo() async {
    await _formAppService.clearLogo();
    notifyListeners();
  }

  Future<void> setFormAppBackground(String filePath) async {
    await _formAppService.setBackground(filePath);
    notifyListeners();
  }

  Future<void> clearFormAppBackground() async {
    await _formAppService.clearBackground();
    notifyListeners();
  }

  Future<void> addFormAppVideos(List<String> filePaths) async {
    await _formAppService.addVideos(filePaths);
    notifyListeners();
  }

  Future<void> removeFormAppVideo(int index) async {
    await _formAppService.removeVideo(index);
    notifyListeners();
  }

  Future<void> reorderFormAppVideo(int oldIndex, int newIndex) async {
    await _formAppService.reorderVideo(oldIndex, newIndex);
    notifyListeners();
  }

  Future<void> clearFormAppVideos() async {
    await _formAppService.clearAllVideos();
    notifyListeners();
  }
}
