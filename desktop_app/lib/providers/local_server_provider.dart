import 'package:flutter/material.dart';
import '../services/local_server_service.dart';

/// Exposes the embedded HTTP server's state to the widget tree via Provider.
class LocalServerProvider extends ChangeNotifier {
  final LocalServerService _service = LocalServerService.instance;

  LocalServerProvider() {
    _service.onDevicesChanged = () => notifyListeners();
  }

  bool get isRunning => _service.isRunning;
  String get localIp => _service.localIp;
  int get port => _service.port;
  String get authToken => _service.authToken;
  String get qrPayload => _service.qrPayload;
  List<String> get connectedDeviceModels => _service.connectedDeviceModels;
  List<EditRequest> get pendingRequests => _service.pendingRequests;

  void approveRequest(String id) {
    _service.approveRequest(id);
    notifyListeners();
  }

  void denyRequest(String id) {
    _service.denyRequest(id);
    notifyListeners();
  }

  void clearRequests() {
    _service.clearRequests();
    notifyListeners();
  }

  void refreshDevices() {
    notifyListeners();
  }

  /// Start the server and notify listeners.
  Future<void> startServer({int port = 8080}) async {
    await _service.start(port: port);
    notifyListeners();
  }

  /// Stop the server and notify listeners.
  Future<void> stopServer() async {
    await _service.stop();
    notifyListeners();
  }

  /// Regenerate the auth token (invalidates existing tablet connections).
  void regenerateToken() {
    _service.regenerateToken();
    notifyListeners();
  }

  /// Wire the data-changed callback so the desktop UI refreshes when
  /// the tablet submits a new patient.
  void setOnDataChanged(VoidCallback callback) {
    _service.onDataChanged = callback;
  }
}
