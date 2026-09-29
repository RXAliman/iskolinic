import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service to handle local authentication (PIN), admin recovery, and sync secrets.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _storage = const FlutterSecureStorage(aOptions: AndroidOptions());

  static const String _keyPinHash = 'user_pin_hash';
  static const String _keyAdminHash = 'admin_password_hash';
  static const String _keySyncSecret = 'sync_secret';
  static const String _keyIsSetup = 'is_setup_complete';

  // ── Setup ────────────────────────────────────────────────────────

  /// Check if the initial security setup has been performed.
  Future<bool> isSetupComplete() async {
    final value = await _storage.read(key: _keyIsSetup);
    return value == 'true';
  }

  /// Initial configuration of security settings.
  Future<void> completeSetup({
    required String pin,
    required String adminPassword,
    required String syncSecret,
  }) async {
    await _storage.write(key: _keyPinHash, value: _hashValue(pin));
    await _storage.write(key: _keyAdminHash, value: _hashValue(adminPassword));
    await _storage.write(key: _keySyncSecret, value: syncSecret);
    await _storage.write(key: _keyIsSetup, value: 'true');
  }

  // ── Verification ──────────────────────────────────────────────────

  /// Verify if the provided PIN is correct.
  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: _keyPinHash);
    return storedHash == _hashValue(pin);
  }

  /// Verify if the provided Admin Password is correct.
  Future<bool> verifyAdminPassword(String password) async {
    final storedHash = await _storage.read(key: _keyAdminHash);
    return storedHash == _hashValue(password);
  }

  // ── Getters / Setters ─────────────────────────────────────────────

  /// Retrieve the sync secret for the relay server.
  Future<String?> getSyncSecret() async {
    return await _storage.read(key: _keySyncSecret);
  }

  /// Update the sync secret (Admin action).
  Future<void> updateSyncSecret(String secret) async {
    await _storage.write(key: _keySyncSecret, value: secret);
  }

  /// Reset the PIN using the admin password.
  Future<bool> resetPinWithAdmin(String adminPassword, String newPin) async {
    if (await verifyAdminPassword(adminPassword)) {
      await _storage.write(key: _keyPinHash, value: _hashValue(newPin));
      return true;
    }
    return false;
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Hash a string using SHA-256 for secure storage.
  String _hashValue(String value) {
    final bytes = utf8.encode(value);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
