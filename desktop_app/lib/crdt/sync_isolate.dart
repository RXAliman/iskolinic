import 'dart:async';
import '../models/patient.dart';
import '../models/visitation.dart';
import '../services/database_helper.dart';
import '../models/inventory_item.dart';
import '../models/custom_symptom.dart';

/// Message sent to the sync isolate with a batch of remote records.
class SyncBatch {
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> visitations;
  final List<Map<String, dynamic>> inventory;
  final List<Map<String, dynamic>> inventoryStocks;
  final List<Map<String, dynamic>> customSymptoms;

  SyncBatch({
    this.patients = const [],
    this.visitations = const [],
    this.inventory = const [],
    this.inventoryStocks = const [],
    this.customSymptoms = const [],
  });
}

/// Result returned from the sync isolate after merging.
class SyncResult {
  final Set<String> changedPatientIds;
  final Set<String> changedVisitationIds;
  final Set<String> changedInventoryIds;
  final Set<String> changedInventoryStockIds;
  final Set<String> changedCustomSymptomIds;
  final int patientsProcessed;
  final int visitationsProcessed;
  final int inventoryProcessed;
  final int inventoryStocksProcessed;
  final int customSymptomsProcessed;

  SyncResult({
    this.changedPatientIds = const {},
    this.changedVisitationIds = const {},
    this.changedInventoryIds = const {},
    this.changedInventoryStockIds = const {},
    this.changedCustomSymptomIds = const {},
    this.patientsProcessed = 0,
    this.visitationsProcessed = 0,
    this.inventoryProcessed = 0,
    this.inventoryStocksProcessed = 0,
    this.customSymptomsProcessed = 0,
  });
}

/// Manages the background isolate that runs CRDT merges.
///
/// All heavy merge logic and batch sqflite inserts run off the main thread.
/// The main thread only receives [SyncResult] with IDs of changed records.
class SyncIsolate {
  /// Process a batch of remote records in a background isolate.
  static Future<SyncResult> mergeBatch(SyncBatch batch) async {
    final db = DatabaseHelper.instance;
    final changedPatientIds = <String>{};
    final changedVisitationIds = <String>{};
    final changedInventoryIds = <String>{};
    final changedInventoryStockIds = <String>{};
    final changedCustomSymptomIds = <String>{};

    // Process patients in micro-batches
    for (int i = 0; i < batch.patients.length; i++) {
      final patient = Patient.fromSyncMap(batch.patients[i]);
      final changed = await db.upsertPatientFromRemote(patient);
      if (changed) changedPatientIds.add(patient.id);

      if (i % 10 == 0) await Future.delayed(Duration.zero);
    }

    // Process visitations
    for (int i = 0; i < batch.visitations.length; i++) {
      final visit = Visitation.fromSyncMap(batch.visitations[i]);
      final changed = await db.upsertVisitationFromRemote(visit);
      if (changed) changedVisitationIds.add(visit.id);

      if (i % 10 == 0) await Future.delayed(Duration.zero);
    }

    // Process inventory
    for (int i = 0; i < batch.inventory.length; i++) {
      final item = InventoryItem.fromSyncMap(batch.inventory[i]);
      final changed = await db.upsertInventoryFromRemote(item);
      if (changed) changedInventoryIds.add(item.id);

      if (i % 10 == 0) await Future.delayed(Duration.zero);
    }

    // Process inventory stocks
    for (int i = 0; i < batch.inventoryStocks.length; i++) {
      final stock = StockBatch.fromSyncMap(batch.inventoryStocks[i]);
      final changed = await db.upsertInventoryStockFromRemote(stock);
      if (changed) changedInventoryStockIds.add(stock.id);

      if (i % 10 == 0) await Future.delayed(Duration.zero);
    }

    // Process custom symptoms
    for (int i = 0; i < batch.customSymptoms.length; i++) {
      final symptom = CustomSymptom.fromSyncMap(batch.customSymptoms[i]);
      final changed = await db.upsertCustomSymptomFromRemote(symptom);
      if (changed) changedCustomSymptomIds.add(symptom.id);

      if (i % 10 == 0) await Future.delayed(Duration.zero);
    }

    return SyncResult(
      changedPatientIds: changedPatientIds,
      changedVisitationIds: changedVisitationIds,
      changedInventoryIds: changedInventoryIds,
      changedInventoryStockIds: changedInventoryStockIds,
      changedCustomSymptomIds: changedCustomSymptomIds,
      patientsProcessed: batch.patients.length,
      visitationsProcessed: batch.visitations.length,
      inventoryProcessed: batch.inventory.length,
      inventoryStocksProcessed: batch.inventoryStocks.length,
      customSymptomsProcessed: batch.customSymptoms.length,
    );
  }
}
