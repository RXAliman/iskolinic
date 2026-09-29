import 'package:flutter/material.dart';
import '../crdt/sync_client.dart';
import '../crdt/data_compactor.dart';
import '../crdt/node_id.dart';
import 'patient_provider.dart';
import 'inventory_provider.dart';
import 'custom_symptom_provider.dart';
import '../services/auth_service.dart';

/// Manages the CRDT sync lifecycle and exposes connection status to the UI.
class SyncProvider extends ChangeNotifier {
  SyncClient? _client;
  PatientProvider? _patientProvider;
  InventoryProvider? _inventoryProvider;
  CustomSymptomProvider? _customSymptomProvider;
  int _currentMode = 0; // 0: Offline, 2: Relay
  int get currentMode => _currentMode;

  SyncConnectionState _connectionState = SyncConnectionState.disconnected;
  SyncConnectionState get connectionState => _connectionState;

  bool get isConnected => _connectionState == SyncConnectionState.connected;
  bool get isConnecting => _connectionState == SyncConnectionState.connecting;
  bool get isSyncing => _client?.isSyncing ?? false;

  /// Initialize the sync system.
  /// Call this after PatientProvider.initCrdt() has been called.
  Future<void> init(
    PatientProvider patientProvider,
    InventoryProvider inventoryProvider,
    CustomSymptomProvider customSymptomProvider, {
    String? wsUrl,
    int initialMode = 2,
  }) async {
    _currentMode = initialMode;
    _patientProvider = patientProvider;
    _inventoryProvider = inventoryProvider;
    _customSymptomProvider = customSymptomProvider;
    
    _inventoryProvider?.onLocalChange = pushChanges;
    _customSymptomProvider?.onLocalChange = pushChanges;

    if (wsUrl == null || wsUrl.isEmpty) {
      debugPrint('SyncProvider: no wsUrl configured, running offline');
      return;
    }

    final nodeId = await NodeId.get();
    final authSecret = await AuthService.instance.getSyncSecret();
    _client = SyncClient(wsUrl: wsUrl, nodeId: nodeId, authSecret: authSecret);

    _client!.onStateChanged = () {
      _connectionState = _client!.state;
      notifyListeners();
    };

    _client!.onSyncStatusChanged = (_) {
      notifyListeners();
    };

    _client!.onSyncComplete = (changedIds) {
      // The easiest way is to just call `load()` unconditionally when sync pushes anything.
      
      _patientProvider?.onSyncComplete(changedIds);
      _inventoryProvider?.loadInventory();
      _customSymptomProvider?.loadSymptoms();
    };

    // Run data compaction on startup
    final removed = await DataCompactor.run();
    if (removed > 0) {
      debugPrint('SyncProvider: compacted $removed old tombstones');
    }

    // Auto-connect to relay server only if in Relay mode
    if (_currentMode == 2) {
      await connect();
    }
  }

  /// Update the current connection mode and trigger connect/disconnect.
  Future<void> setConnectionMode(int mode) async {
    if (mode == _currentMode) return;
    _currentMode = mode;
    
    if (mode == 2) {
      await connect();
    } else {
      disconnect();
    }
    notifyListeners();
  }

  /// Manually connect to the relay server.
  Future<void> connect() async {
    if (_currentMode != 2) return;
    await _client?.connect();
  }

  /// Disconnect from the relay server.
  void disconnect() {
    _client?.disconnect();
  }
  
  /// Force a manual sync by reconnecting
  Future<void> forceSync() async {
    disconnect();
    if (_currentMode != 2) return;
    await Future.delayed(const Duration(milliseconds: 50));
    await connect();
  }

  /// Push local changes after a write.
  Future<void> pushChanges() async {
    if (_currentMode != 2) return;
    await _client?.pushChanges();
  }

  /// Re-initialize the client with the latest secret from storage.
  /// Used when the user updates the secret in settings.
  Future<void> reconnectWithNewSecret() async {
    final wsUrl = _client?.wsUrl;
    if (wsUrl == null) return;
    
    disconnect();
    
    final nodeId = await NodeId.get();
    final authSecret = await AuthService.instance.getSyncSecret();
    _client = SyncClient(wsUrl: wsUrl, nodeId: nodeId, authSecret: authSecret);

    _client!.onStateChanged = () {
      _connectionState = _client!.state;
      notifyListeners();
    };

    _client!.onSyncStatusChanged = (_) {
      notifyListeners();
    };

    _client!.onSyncComplete = (changedIds) {
      _patientProvider?.onSyncComplete(changedIds);
      _inventoryProvider?.loadInventory();
      _customSymptomProvider?.loadSymptoms();
    };

    if (_currentMode == 2) {
      await connect();
    }
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }
}
