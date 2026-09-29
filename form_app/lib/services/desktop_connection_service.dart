import 'dart:convert';
import 'package:http/http.dart' as http;
import 'device_service.dart';

/// Manages the tablet's connection to the desktop app's local HTTP server.
///
/// Stores connection credentials parsed from the QR code and provides
/// methods to verify the connection, fetch patients, and submit new records.
class DesktopConnectionService {
  static final DesktopConnectionService instance =
      DesktopConnectionService._internal();
  factory DesktopConnectionService() => instance;
  DesktopConnectionService._internal();

  String _host = '';
  int _port = 8080;
  String _token = '';
  bool _connected = false;

  bool get isConnected => _connected;
  String get host => _host;
  int get port => _port;
  String get baseUrl => 'http://$_host:$_port';

  /// Parse QR code JSON and attempt to connect.
  ///
  /// Returns `true` if the health check succeeds.
  Future<bool> connect(String qrPayload) async {
    try {
      // ignore: avoid_print
      print('[DesktopConnection] Parsing QR payload: $qrPayload');
      final data = jsonDecode(qrPayload) as Map<String, dynamic>;
      _host = data['host'] as String;
      // JSON numbers can decode as int or double depending on platform
      _port = (data['port'] is int)
          ? data['port'] as int
          : (data['port'] as num).toInt();
      _token = data['token'] as String;

      // ignore: avoid_print
      print('[DesktopConnection] Connecting to http://$_host:$_port');

      // Verify connection with health check
      _connected = await _healthCheck();
      // ignore: avoid_print
      print('[DesktopConnection] Health check result: $_connected');

      return _connected;
    } catch (e) {
      // ignore: avoid_print
      print('[DesktopConnection] Connect error: $e');
      _connected = false;
      return false;
    }
  }

  /// Connect using manual IP and token.
  Future<bool> connectManual({
    required String host,
    required int port,
    required String token,
  }) async {
    _host = host;
    _port = port;
    _token = token;
    _connected = await _healthCheck();
    return _connected;
  }

  /// Verify the server is reachable and the token is valid.
  Future<bool> _healthCheck() async {
    try {
      final url = '$baseUrl/api/health';
      // ignore: avoid_print
      print('[DesktopConnection] Health check: GET $url');
      final response = await http
          .get(Uri.parse(url), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      // ignore: avoid_print
      print(
        '[DesktopConnection] Response: ${response.statusCode} ${response.body}',
      );
      return response.statusCode == 200;
    } catch (e) {
      // ignore: avoid_print
      print('[DesktopConnection] Health check failed: $e');
      return false;
    }
  }

  /// Re-check the connection status. Call this before critical operations.
  Future<bool> checkConnection() async {
    _connected = await _healthCheck();
    return _connected;
  }

  /// Fetch all patients from the desktop database.
  ///
  /// Returns a list of patient maps, or an empty list on failure.
  Future<List<Map<String, dynamic>>> fetchPatients() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/patients'), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      _connected = false;
      return [];
    }
  }

  /// Fetch a single patient by their ID number.
  ///
  /// Returns a map of patient details or null if not found.
  Future<Map<String, dynamic>?> fetchPatientByIdNumber(
    String idNumber, {
    String? requestId,
  }) async {
    try {
      var url = '$baseUrl/api/patients/search?idNumber=$idNumber';
      if (requestId != null) url += '&requestId=$requestId';

      final response = await http
          .get(Uri.parse(url), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      _connected = false;
      return null;
    }
  }

  /// Request permission to edit/view full details of a patient.
  Future<Map<String, dynamic>?> requestEdit(String idNumber) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/edit-requests'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'idNumber': idNumber}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Check the status of a pending edit request.
  Future<Map<String, dynamic>?> checkEditRequestStatus(String requestId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/edit-requests/$requestId'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Submit a new patient (and optional visitation) to the desktop database.
  ///
  /// Returns `true` on success.
  Future<bool> submitPatient(Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/patients'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return true;
      }
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Server error ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  /// Disconnect (clear credentials).
  void disconnect() {
    _host = '';
    _port = 8080;
    _token = '';
    _connected = false;
  }

  /// Standard auth headers for every request.
  Map<String, String> get authHeaders => _authHeaders;

  Map<String, String> get _authHeaders {
    return {
      'Authorization': 'Bearer $_token',
      'X-Device-Model': DeviceService.instance.cachedModel ?? 'Unknown Device',
    };
  }
}
