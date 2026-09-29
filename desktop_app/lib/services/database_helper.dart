import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/patient.dart';
import '../models/visitation.dart';
import '../models/inventory_item.dart';
import '../models/custom_symptom.dart';
import '../crdt/hlc.dart';
import '../constants/app_config.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, AppConfig.databaseName);

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        firstName TEXT NOT NULL,
        lastName TEXT NOT NULL,
        middleName TEXT NOT NULL DEFAULT '',
        extension TEXT NOT NULL DEFAULT '',
        patientName TEXT NOT NULL,
        idNumber TEXT NOT NULL,
        birthdate TEXT,
        sex TEXT NOT NULL DEFAULT '',
        contactNumber TEXT NOT NULL DEFAULT '',
        address TEXT,
        guardianName TEXT,
        guardianContact TEXT,
        guardian2Name TEXT NOT NULL DEFAULT '',
        guardian2Contact TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        hlc TEXT NOT NULL DEFAULT '',
        nodeId TEXT NOT NULL DEFAULT '',
        isDeleted INTEGER NOT NULL DEFAULT 0,
        medicalHistory TEXT NOT NULL DEFAULT '[]',
        vaccinationHistory TEXT NOT NULL DEFAULT '[]',
        allergicTo TEXT NOT NULL DEFAULT '',
        patientRemarks TEXT NOT NULL DEFAULT '',
        permissions TEXT NOT NULL DEFAULT '{}',
        role TEXT NOT NULL DEFAULT '',
        department TEXT NOT NULL DEFAULT '',
        level TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE visitations (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        dateTime TEXT NOT NULL,
        symptoms TEXT,
        suppliesUsed TEXT,
        consumedSupplies TEXT NOT NULL DEFAULT '',
        treatment TEXT,
        remarks TEXT,
        customChiefComplaint TEXT NOT NULL DEFAULT '',
        hlc TEXT NOT NULL DEFAULT '',
        nodeId TEXT NOT NULL DEFAULT '',
        isDeleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    // Index on HLC for efficient sync queries
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_patients_hlc ON patients (hlc)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_visitations_hlc ON visitations (hlc)',
    );
    // Inventory table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory (
        id TEXT PRIMARY KEY,
        itemName TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        lowStockAmount INTEGER NOT NULL DEFAULT 0,
        clinic TEXT NOT NULL DEFAULT '',
        itemType TEXT NOT NULL DEFAULT 'piece',
        createdAt TEXT NOT NULL,
        hlc TEXT NOT NULL DEFAULT '',
        nodeId TEXT NOT NULL DEFAULT '',
        isDeleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_name ON inventory (itemName)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_hlc ON inventory (hlc)',
    );
    // Custom Symptoms table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_symptoms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        hlc TEXT NOT NULL DEFAULT '',
        nodeId TEXT NOT NULL DEFAULT '',
        isDeleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_custom_symptoms_hlc ON custom_symptoms (hlc)',
    );
    // Inventory Stocks table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_stocks (
        id TEXT PRIMARY KEY,
        itemId TEXT NOT NULL,
        amount INTEGER NOT NULL DEFAULT 0,
        expiryDate TEXT,
        createdAt TEXT NOT NULL,
        hlc TEXT NOT NULL DEFAULT '',
        nodeId TEXT NOT NULL DEFAULT '',
        isDeleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (itemId) REFERENCES inventory (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_stocks_itemId ON inventory_stocks (itemId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_stocks_expiry ON inventory_stocks (expiryDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_stocks_hlc ON inventory_stocks (hlc)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migrate inventory clinic names to the new terminology
      await db.execute(
        "UPDATE inventory SET clinic = 'Clinic A' "
        "WHERE clinic IN ('Pre-school Clinic', 'Junior High School Clinic', 'Senior High School Clinic', 'College Clinic')",
      );
      await db.execute(
        "UPDATE inventory SET clinic = 'Clinic B' "
        "WHERE clinic = 'Grade School Clinic'",
      );
    }
    if (oldVersion < 3) {
      // 1. Create inventory_stocks table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_stocks (
          id TEXT PRIMARY KEY,
          itemId TEXT NOT NULL,
          amount INTEGER NOT NULL DEFAULT 0,
          expiryDate TEXT,
          createdAt TEXT NOT NULL,
          hlc TEXT NOT NULL DEFAULT '',
          nodeId TEXT NOT NULL DEFAULT '',
          isDeleted INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (itemId) REFERENCES inventory (id)
        )
      ''');

      // 2. Migrate existing inventory to stocks
      // We group by itemName + clinic to keep them separate per clinic as requested
      final List<Map<String, dynamic>> items = await db.query('inventory');

      final Map<String, List<Map<String, dynamic>>> groups = {};
      for (final item in items) {
        final key = "${item['itemName']}_${item['clinic']}_${item['itemType']}"
            .toLowerCase()
            .trim();
        groups.putIfAbsent(key, () => []).add(item);
      }

      final now = DateTime.now().toIso8601String();

      for (final group in groups.values) {
        // Sort by ID to be deterministic across nodes
        group.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

        // The first item in the group is our survivor
        final survivor = group.first;
        final survivorId = survivor['id'] as String;

        // 2a. Create a separate stock batch for EACH item in the group
        for (final item in group) {
          final qty = item['quantity'] as int? ?? 0;
          if (qty > 0) {
            await db.insert('inventory_stocks', {
              'id': 'legacy_${item['id']}',
              'itemId': survivorId,
              'amount': qty,
              'expiryDate': null,
              'createdAt': now,
              'hlc': item['hlc'],
              'nodeId': item['nodeId'],
              'isDeleted': 0,
            });
          }
        }

        // 2b. Soft-delete all other items in the group from the inventory table
        // We use soft-delete so it syncs correctly to other nodes.
        // We use a fresh HLC to ensure this delete propagates and wins over old states.
        final migrationHlc = HLC
            .now(survivor['nodeId'] as String? ?? 'migration')
            .pack();
        for (int i = 1; i < group.length; i++) {
          await db.update(
            'inventory',
            {'isDeleted': 1, 'hlc': migrationHlc, 'nodeId': survivor['nodeId']},
            where: 'id = ?',
            whereArgs: [group[i]['id']],
          );
        }
      }

      // 3. Add indices for the new table
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inventory_stocks_itemId ON inventory_stocks (itemId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inventory_stocks_expiry ON inventory_stocks (expiryDate)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inventory_stocks_hlc ON inventory_stocks (hlc)',
      );
    }
    if (oldVersion < 4) {
      // Add customChiefComplaint column to visitations
      await db.execute(
        "ALTER TABLE visitations ADD COLUMN customChiefComplaint TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 5) {
      // Add level column to patients
      await db.execute(
        "ALTER TABLE patients ADD COLUMN level TEXT NOT NULL DEFAULT ''",
      );
    }

    if (oldVersion < 6) {
      // Cleanup any remaining duplicates that were not correctly merged/deleted in previous versions
      // OR were re-introduced by sync because of hard deletes in version 3.
      final List<Map<String, dynamic>> items = await db.query(
        'inventory',
        where: 'isDeleted = 0',
      );

      final Map<String, List<Map<String, dynamic>>> groups = {};
      for (final item in items) {
        // We use itemName + clinic + itemType as the key to identify duplicates
        final key = "${item['itemName']}_${item['clinic']}_${item['itemType']}"
            .toLowerCase()
            .trim();
        groups.putIfAbsent(key, () => []).add(item);
      }

      // We need an HLC for the soft-delete. We try to get the node ID from meta.
      final List<Map<String, dynamic>> meta = await db.query(
        'meta',
        where: 'key = ?',
        whereArgs: ['nodeId'],
      );
      final String nodeId = meta.isNotEmpty
          ? meta.first['value'] as String
          : 'migration_node';
      final String hlc = HLC.now(nodeId).pack();

      for (final group in groups.values) {
        if (group.length <= 1) continue;

        // Sort by ID to be deterministic across nodes
        group.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

        final survivorId = group.first['id'] as String;

        for (int i = 1; i < group.length; i++) {
          final duplicateId = group[i]['id'] as String;

          // 1. Move all stocks from duplicate to survivor
          await db.update(
            'inventory_stocks',
            {'itemId': survivorId, 'hlc': hlc, 'nodeId': nodeId},
            where: 'itemId = ?',
            whereArgs: [duplicateId],
          );

          // 2. Soft-delete the duplicate item in the inventory table
          await db.update(
            'inventory',
            {'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
            where: 'id = ?',
            whereArgs: [duplicateId],
          );
        }
      }

      // 3. Restoration: Un-merge items that were incorrectly merged despite having different types
      // This specifically handles items where legacy stocks are pointing to a survivor of a different type.
      final List<Map<String, dynamic>> deletedItems = await db.query(
        'inventory',
        where: 'isDeleted = 1',
      );

      for (final deletedItem in deletedItems) {
        final deletedId = deletedItem['id'] as String;
        final legacyStockId = "legacy_$deletedId";

        // Find if this item's legacy stock exists and is pointing elsewhere
        final List<Map<String, dynamic>> stocks = await db.query(
          'inventory_stocks',
          where: 'id = ?',
          whereArgs: [legacyStockId],
        );

        if (stocks.isNotEmpty) {
          final currentItemId = stocks.first['itemId'] as String;
          if (currentItemId != deletedId) {
            // It was merged. Check if types match.
            final List<Map<String, dynamic>> survivors = await db.query(
              'inventory',
              where: 'id = ?',
              whereArgs: [currentItemId],
            );

            if (survivors.isNotEmpty) {
              final survivor = survivors.first;
              final sType = survivor['itemType']
                  .toString()
                  .toLowerCase()
                  .trim();
              final dType = deletedItem['itemType']
                  .toString()
                  .toLowerCase()
                  .trim();

              if (sType != dType) {
                // Incorrectly merged! Un-merge by restoring the item and its legacy stock.
                await db.update(
                  'inventory_stocks',
                  {'itemId': deletedId, 'hlc': hlc, 'nodeId': nodeId},
                  where: 'id = ?',
                  whereArgs: [legacyStockId],
                );
                await db.update(
                  'inventory',
                  {'isDeleted': 0, 'hlc': hlc, 'nodeId': nodeId},
                  where: 'id = ?',
                  whereArgs: [deletedId],
                );
              }
            }
          }
        }
      }
      if (oldVersion < 7) {
        // Re-run cleanup to fix the "zeroed-out" duplicates caused by the case-sensitive bug in version 6.
        final List<Map<String, dynamic>> items = await db.query(
          'inventory',
          where: 'isDeleted = 0',
        );

        final Map<String, List<Map<String, dynamic>>> groups = {};
        for (final item in items) {
          final key =
              "${item['itemName']}_${item['clinic']}_${item['itemType']}"
                  .toLowerCase()
                  .trim();
          groups.putIfAbsent(key, () => []).add(item);
        }

        final List<Map<String, dynamic>> meta = await db.query(
          'meta',
          where: 'key = ?',
          whereArgs: ['nodeId'],
        );
        final String nodeId = meta.isNotEmpty
            ? meta.first['value'] as String
            : 'migration_node';
        final String hlc = HLC.now(nodeId).pack();

        for (final group in groups.values) {
          if (group.length <= 1) continue;
          group.sort(
            (a, b) => (a['id'] as String).compareTo(b['id'] as String),
          );
          final survivorId = group.first['id'] as String;

          for (int i = 1; i < group.length; i++) {
            final duplicateId = group[i]['id'] as String;
            await db.update(
              'inventory_stocks',
              {'itemId': survivorId, 'hlc': hlc, 'nodeId': nodeId},
              where: 'itemId = ?',
              whereArgs: [duplicateId],
            );
            await db.update(
              'inventory',
              {'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
              where: 'id = ?',
              whereArgs: [duplicateId],
            );
          }
        }
      }
    }
  }

  // ── Meta (key-value store) ──────────────────────────────────────

  Future<String?> getMeta(String key) async {
    final db = await database;
    final maps = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Helpers ─────────────────────────────────────────────────────

  String _buildPatientFilterClause(
    List<String>? selectedDepartments,
    bool includeStudent,
    bool includeEmployee, {
    String tablePrefix = '',
  }) {
    final prefix = tablePrefix.isNotEmpty ? '$tablePrefix.' : '';
    List<String> roleConditions = [];
    if (includeStudent) roleConditions.add("${prefix}role = 'Student'");
    if (includeEmployee) roleConditions.add("${prefix}role = 'Employee'");

    if (roleConditions.isEmpty) {
      return "1=0"; // No roles selected, match nothing
    }

    String roleClause = "(${roleConditions.join(' OR ')})";

    if (selectedDepartments == null) {
      return roleClause;
    }

    if (selectedDepartments.isEmpty) {
      return "1=0"; // Departments list provided but empty, match nothing
    }

    final deptList = selectedDepartments.map((d) => "'$d'").join(',');
    return "($roleClause AND ${prefix}department IN ($deptList))";
  }

  // ── Patient CRUD (with soft-delete) ─────────────────────────────

  Future<void> insertPatient(Patient patient) async {
    final db = await database;
    await db.insert(
      'patients',
      patient.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertPatientsBatch(List<Patient> patients) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final patient in patients) {
        batch.insert(
          'patients',
          patient.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Patient>> getPatients() async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'isDeleted = 0',
      orderBy: 'patientName ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<List<Patient>> getMockPatients() async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: "isDeleted = 0 AND nodeId = 'MOCK_NODE'",
      orderBy: 'patientName ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<List<Patient>> getPatientsPaginated({
    required int limit,
    required int offset,
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
  }) async {
    final db = await database;
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
    );
    final maps = await db.query(
      'patients',
      where: 'isDeleted = 0 AND $filterClause',
      orderBy: 'patientName ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<int> getPatientCount({
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
  }) async {
    final db = await database;
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
    );
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM patients WHERE isDeleted = 0 AND $filterClause',
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<Patient>> searchPatientsPaginated({
    required String query,
    required int limit,
    required int offset,
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
  }) async {
    final db = await database;
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
    );
    final maps = await db.query(
      'patients',
      where:
          'isDeleted = 0 AND $filterClause AND (patientName LIKE ? OR idNumber LIKE ? OR firstName LIKE ? OR lastName LIKE ?)',
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
      orderBy: 'patientName ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<int> searchPatientCount({
    required String query,
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
  }) async {
    final db = await database;
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
    );
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM patients WHERE isDeleted = 0 AND $filterClause AND (patientName LIKE ? OR idNumber LIKE ? OR firstName LIKE ? OR lastName LIKE ?)',
      ['%$query%', '%$query%', '%$query%', '%$query%'],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<Patient?> getPatient(String id) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Patient.fromMap(maps.first);
  }

  Future<void> updatePatient(Patient patient) async {
    final db = await database;
    await db.update(
      'patients',
      patient.toMap(),
      where: 'id = ?',
      whereArgs: [patient.id],
    );
  }

  /// Soft-delete: marks the patient and its visitations as deleted.
  Future<void> deletePatient(String id, {required String hlc}) async {
    final db = await database;
    await db.update(
      'visitations',
      {'isDeleted': 1, 'hlc': hlc},
      where: 'patientId = ? AND isDeleted = 0',
      whereArgs: [id],
    );
    await db.update(
      'patients',
      {'isDeleted': 1, 'hlc': hlc},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Patient>> searchPatients(String query) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'isDeleted = 0 AND (patientName LIKE ? OR idNumber LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'patientName ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<Patient?> getPatientByIdNumber(String idNumber) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'isDeleted = 0 AND idNumber = ?',
      whereArgs: [idNumber],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Patient.fromMap(maps.first);
  }

  // ── Visitation CRUD (with soft-delete) ──────────────────────────

  Future<void> insertVisitation(Visitation visit) async {
    final db = await database;
    await db.insert(
      'visitations',
      visit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertVisitationsBatch(List<Visitation> visits) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final visit in visits) {
        batch.insert(
          'visitations',
          visit.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateVisitation(Visitation visit) async {
    final db = await database;
    await db.update(
      'visitations',
      visit.toMap(),
      where: 'id = ?',
      whereArgs: [visit.id],
    );
  }

  Future<Visitation?> getVisitation(String id) async {
    final db = await database;
    final maps = await db.query(
      'visitations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Visitation.fromMap(maps.first);
  }

  Future<List<Visitation>> getVisitationsForPatient(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'visitations',
      where: 'patientId = ? AND isDeleted = 0',
      whereArgs: [patientId],
      orderBy: 'dateTime DESC',
    );
    return maps.map((m) => Visitation.fromMap(m)).toList();
  }

  Future<List<Visitation>> getVisitationsPaginated(
    String patientId,
    int limit,
    int offset,
  ) async {
    final db = await database;
    final maps = await db.query(
      'visitations',
      where: 'patientId = ? AND isDeleted = 0',
      whereArgs: [patientId],
      orderBy: 'dateTime DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => Visitation.fromMap(m)).toList();
  }

  Future<int> getVisitationCountForPatient(String patientId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM visitations WHERE patientId = ? AND isDeleted = 0',
      [patientId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<Visitation>> getVisitationsForMonth(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 1).toIso8601String();
    final maps = await db.query(
      'visitations',
      where: 'isDeleted = 0 AND dateTime >= ? AND dateTime < ?',
      whereArgs: [start, end],
    );
    return maps.map((m) => Visitation.fromMap(m)).toList();
  }

  Future<int> getTodayVisitCount({
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
      tablePrefix: 'p',
    );

    final result = await db.rawQuery(
      '''
      SELECT COUNT(v.id) as count 
      FROM visitations v
      JOIN patients p ON v.patientId = p.id
      WHERE v.isDeleted = 0 
        AND v.dateTime >= ? 
        AND v.dateTime < ?
        AND $filterClause
      ''',
      [start, end],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Gets today's visitations along with the patient's name, paginated.
  Future<List<Map<String, dynamic>>> getTodayVisitationsPaginated({
    required int limit,
    required int offset,
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
      tablePrefix: 'p',
    );

    final maps = await db.rawQuery(
      '''
      SELECT v.*, p.patientName, p.firstName, p.department, p.role, p.level 
      FROM visitations v 
      JOIN patients p ON v.patientId = p.id 
      WHERE v.isDeleted = 0 
        AND v.dateTime >= ? 
        AND v.dateTime < ?
        AND $filterClause
      ORDER BY v.dateTime DESC
      LIMIT ? OFFSET ?
      ''',
      [start, end, limit, offset],
    );

    return maps;
  }

  /// Global visit count with filters.
  Future<int> getGlobalVisitCount({
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
    DateTime? date,
  }) async {
    final db = await database;
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
      tablePrefix: 'p',
    );

    String dateClause = '';
    List<dynamic> args = [];
    if (date != null) {
      final dateStr =
          "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      dateClause = ' AND v.dateTime LIKE ?';
      args.add('$dateStr%');
    }

    final result = await db.rawQuery('''
      SELECT COUNT(v.id) as count 
      FROM visitations v
      JOIN patients p ON v.patientId = p.id
      WHERE v.isDeleted = 0 
        AND $filterClause
        $dateClause
      ''', args);
    return result.first['count'] as int? ?? 0;
  }

  /// Global paginated visitations with filters.
  Future<List<Map<String, dynamic>>> getGlobalVisitationsPaginated({
    required int limit,
    required int offset,
    List<String>? selectedDepartments,
    bool includeStudent = true,
    bool includeEmployee = true,
    DateTime? date,
  }) async {
    final db = await database;
    final filterClause = _buildPatientFilterClause(
      selectedDepartments,
      includeStudent,
      includeEmployee,
      tablePrefix: 'p',
    );

    String dateClause = '';
    List<dynamic> args = [];
    if (date != null) {
      final dateStr =
          "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      dateClause = ' AND v.dateTime LIKE ?';
      args.add('$dateStr%');
    }

    args.add(limit);
    args.add(offset);

    final maps = await db.rawQuery('''
      SELECT v.*, p.patientName, p.firstName, p.department, p.role, p.level 
      FROM visitations v 
      JOIN patients p ON v.patientId = p.id 
      WHERE v.isDeleted = 0 
        AND $filterClause
        $dateClause
      ORDER BY v.dateTime DESC
      LIMIT ? OFFSET ?
      ''', args);

    return maps;
  }

  // ── CRDT Sync Methods ──────────────────────────────────────────

  /// Get all patients changed since the given HLC (for outbound sync).
  Future<List<Patient>> getPatientChangesSince(String sinceHlc) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'hlc > ?',
      whereArgs: [sinceHlc],
      orderBy: 'hlc ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  /// Get all visitations changed since the given HLC (for outbound sync).
  Future<List<Visitation>> getVisitationChangesSince(String sinceHlc) async {
    final db = await database;
    final maps = await db.query(
      'visitations',
      where: 'hlc > ?',
      whereArgs: [sinceHlc],
      orderBy: 'hlc ASC',
    );
    return maps.map((m) => Visitation.fromMap(m)).toList();
  }

  /// CRDT merge: upsert a remote patient only if its HLC > local HLC.
  /// Returns true if a change was applied.
  Future<bool> upsertPatientFromRemote(Patient remote) async {
    final db = await database;
    final existing = await db.query(
      'patients',
      where: 'id = ?',
      whereArgs: [remote.id],
    );

    if (existing.isEmpty) {
      await db.insert('patients', remote.toMap());
      return true;
    }

    final localHlc = HLC.unpack(existing.first['hlc'] as String? ?? '');
    final remoteHlc = HLC.unpack(remote.hlc);

    if (remoteHlc > localHlc) {
      await db.update(
        'patients',
        remote.toMap(),
        where: 'id = ?',
        whereArgs: [remote.id],
      );
      return true;
    }
    return false;
  }

  Future<bool> upsertVisitationFromRemote(Visitation remote) async {
    final db = await database;
    try {
      final existing = await db.query(
        'visitations',
        where: 'id = ?',
        whereArgs: [remote.id],
      );

      if (existing.isEmpty) {
        await db.insert('visitations', remote.toMap());
        return true;
      }

      final localHlc = HLC.unpack(existing.first['hlc'] as String? ?? '');
      final remoteHlc = HLC.unpack(remote.hlc);

      if (remoteHlc > localHlc) {
        await db.update(
          'visitations',
          remote.toMap(),
          where: 'id = ?',
          whereArgs: [remote.id],
        );
        return true;
      }
      return false;
    } catch (e) {
      if (e is DatabaseException &&
          e.isUniqueConstraintError() == false &&
          e.toString().contains('FOREIGN KEY')) {
        // Orphaned visitation (synced before its parent patient record arrived).
        // Since we chunk patients first, this is rare, but if it happens, we
        // skip inserting to prevent the isolate from crashing. The sync protocol
        // will naturally resolve this if we eventually get the patient record.
        return false;
      }
      rethrow;
    }
  }

  // ── Data Compaction ─────────────────────────────────────────────

  /// Permanently removes tombstoned records older than [daysThreshold] days.
  Future<int> compactTombstones({int daysThreshold = 90}) async {
    final db = await database;
    final cutoff = HLC(
      timestamp: DateTime.now()
          .subtract(Duration(days: daysThreshold))
          .millisecondsSinceEpoch,
      counter: 0,
      nodeId: '',
    ).pack();

    int removed = 0;
    removed += await db.delete(
      'visitations',
      where: 'isDeleted = 1 AND hlc < ?',
      whereArgs: [cutoff],
    );
    removed += await db.delete(
      'patients',
      where: 'isDeleted = 1 AND hlc < ?',
      whereArgs: [cutoff],
    );
    return removed;
  }

  // ── Inventory (New Tabular Model) ─────────────────────────────

  Future<void> insertInventoryItem(InventoryItem item) async {
    final db = await database;
    await db.insert(
      'inventory',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<InventoryItem>> getAllInventory() async {
    final db = await database;
    final itemMaps = await db.query(
      'inventory',
      where: 'isDeleted = 0',
      orderBy: 'itemName ASC',
    );

    final List<InventoryItem> items = [];
    for (final itemMap in itemMaps) {
      final itemId = itemMap['id'] as String;
      final stockMaps = await db.query(
        'inventory_stocks',
        where: 'itemId = ? AND isDeleted = 0',
        whereArgs: [itemId],
      );
      final stocks = stockMaps.map((m) => StockBatch.fromMap(m)).toList();
      items.add(InventoryItem.fromMap(itemMap, stocks: stocks));
    }
    return items;
  }

  Future<int> getInventoryCount(String query) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM inventory WHERE isDeleted = 0 AND itemName LIKE ?',
      ['%$query%'],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<InventoryItem>> searchInventoryPaginated({
    required String query,
    required int limit,
    required int offset,
    required String orderBy,
    required bool ascending,
  }) async {
    final db = await database;
    final itemMaps = await db.query(
      'inventory',
      where: 'isDeleted = 0 AND itemName LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: '$orderBy ${ascending ? 'ASC' : 'DESC'}',
      limit: limit,
      offset: offset,
    );

    final List<InventoryItem> items = [];
    for (final itemMap in itemMaps) {
      final itemId = itemMap['id'] as String;
      final stockMaps = await db.query(
        'inventory_stocks',
        where: 'itemId = ? AND isDeleted = 0',
        whereArgs: [itemId],
      );
      final stocks = stockMaps.map((m) => StockBatch.fromMap(m)).toList();
      items.add(InventoryItem.fromMap(itemMap, stocks: stocks));
    }
    return items;
  }

  Future<List<InventoryItem>> getAllInventoryItems() async {
    final db = await database;
    final itemMaps = await db.query(
      'inventory',
      where: 'isDeleted = 0',
      orderBy: 'itemName ASC',
    );

    final List<InventoryItem> items = [];
    for (final itemMap in itemMaps) {
      final itemId = itemMap['id'] as String;
      final stockMaps = await db.query(
        'inventory_stocks',
        where: 'itemId = ? AND isDeleted = 0',
        whereArgs: [itemId],
      );
      final stocks = stockMaps.map((m) => StockBatch.fromMap(m)).toList();
      items.add(InventoryItem.fromMap(itemMap, stocks: stocks));
    }
    return items;
  }

  Future<List<String>> getDistinctClinics() async {
    final db = await database;
    final maps = await db.rawQuery(
      "SELECT DISTINCT clinic FROM inventory WHERE isDeleted = 0 ORDER BY clinic ASC",
    );
    return maps.map((m) => (m['clinic'] as String?) ?? '').toList();
  }

  Future<int> getInventoryCountByClinic(
    String clinic, {
    String query = '',
  }) async {
    final db = await database;
    String sql =
        'SELECT COUNT(*) as count FROM inventory WHERE isDeleted = 0 AND clinic = ?';
    List<dynamic> args = [clinic];
    if (query.isNotEmpty) {
      sql += ' AND itemName LIKE ?';
      args.add('%$query%');
    }
    final result = await db.rawQuery(sql, args);
    return result.first['count'] as int? ?? 0;
  }

  Future<List<InventoryItem>> getInventoryByClinicPaginated({
    required String clinic,
    required int limit,
    required int offset,
    String query = '',
  }) async {
    final db = await database;
    String where = 'isDeleted = 0 AND clinic = ?';
    List<dynamic> whereArgs = [clinic];
    if (query.isNotEmpty) {
      where += ' AND itemName LIKE ?';
      whereArgs.add('%$query%');
    }
    final itemMaps = await db.query(
      'inventory',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'itemName ASC',
      limit: limit,
      offset: offset,
    );

    final List<InventoryItem> items = [];
    for (final itemMap in itemMaps) {
      final itemId = itemMap['id'] as String;
      final stockMaps = await db.query(
        'inventory_stocks',
        where: 'itemId = ? AND isDeleted = 0',
        whereArgs: [itemId],
      );
      final stocks = stockMaps.map((m) => StockBatch.fromMap(m)).toList();
      items.add(InventoryItem.fromMap(itemMap, stocks: stocks));
    }
    return items;
  }

  Future<List<InventoryItem>> getLowStockItems() async {
    final allItems = await getAllInventoryItems();
    return allItems.where((item) => item.isLowStock).toList();
  }

  Future<void> deleteInventoryItemSoft(
    String id, {
    required String hlc,
    required String nodeId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'inventory',
        {'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'inventory_stocks',
        {'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
        where: 'itemId = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> updateInventoryItem(InventoryItem item) async {
    final db = await database;
    await db.update(
      'inventory',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // ── Inventory Stock CRUD ────────────────────────────────────────

  Future<void> insertStockBatch(StockBatch batch) async {
    final db = await database;
    await db.insert(
      'inventory_stocks',
      batch.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateStockBatch(StockBatch batch) async {
    final db = await database;
    await db.update(
      'inventory_stocks',
      batch.toMap(),
      where: 'id = ?',
      whereArgs: [batch.id],
    );
  }

  Future<void> deleteStockBatch(
    String id, {
    required String hlc,
    required String nodeId,
  }) async {
    final db = await database;
    await db.update(
      'inventory_stocks',
      {'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deductStock(
    String itemId,
    int qty, {
    required String hlc,
    required String nodeId,
  }) async {
    final db = await database;
    return await db.transaction<int>((txn) async {
      // Fetch active batches, ordered by expiry date (null expiry at the end)
      final List<Map<String, dynamic>> stockMaps = await txn.query(
        'inventory_stocks',
        where: 'itemId = ? AND isDeleted = 0 AND amount > 0',
        whereArgs: [itemId],
        orderBy: 'expiryDate ASC, createdAt ASC',
      );

      if (stockMaps.isEmpty) return 0;

      int remainingToDeduct = qty;
      for (final map in stockMaps) {
        if (remainingToDeduct <= 0) break;

        final batchId = map['id'] as String;
        final currentAmount = map['amount'] as int;

        if (currentAmount <= remainingToDeduct) {
          // Consume whole batch — soft-delete it
          remainingToDeduct -= currentAmount;
          await txn.update(
            'inventory_stocks',
            {'amount': 0, 'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
            where: 'id = ?',
            whereArgs: [batchId],
          );
        } else {
          // Partially consume batch
          final newAmount = currentAmount - remainingToDeduct;
          remainingToDeduct = 0;
          await txn.update(
            'inventory_stocks',
            {'amount': newAmount, 'hlc': hlc, 'nodeId': nodeId},
            where: 'id = ?',
            whereArgs: [batchId],
          );
        }
      }

      // Return the actual amount deducted
      return qty - remainingToDeduct;
    });
  }

  // addStock is no longer needed in this form because we use insertStockBatch
  // to add new specific batches with expiries.

  Future<int> removeDetachedVisitations() async {
    final db = await database;

    // Get node ID to mark soft delete
    final nodeIdStr = await getMeta('nodeId') ?? 'unknown';
    final hlcStr = HLC.now(nodeIdStr).pack();

    return await db.transaction((txn) async {
      // Mark visitations deleted if their patient is deleted or missing
      final count = await txn.rawUpdate(
        '''
        UPDATE visitations 
        SET isDeleted = 1, hlc = ?, nodeId = ?
        WHERE isDeleted = 0 
          AND patientId NOT IN (SELECT id FROM patients WHERE isDeleted = 0)
      ''',
        [hlcStr, nodeIdStr],
      );

      return count;
    });
  }

  Future<void> purgeOldRecords(int years) async {
    final db = await database;
    final thresholdDate = DateTime.now().subtract(Duration(days: years * 365));
    final thresholdIso = thresholdDate.toIso8601String();

    // Get node HLC to mark soft delete
    final nodeIdStr = await getMeta('nodeId') ?? 'unknown';
    final hlcStr = HLC.now(nodeIdStr).pack();

    await db.transaction((txn) async {
      // Find old patients
      final oldPatients = await txn.query(
        'patients',
        columns: ['id'],
        where: 'createdAt < ? AND isDeleted = 0',
        whereArgs: [thresholdIso],
      );

      for (final p in oldPatients) {
        final pid = p['id'] as String;
        // Mark patient deleted
        await txn.update(
          'patients',
          {'isDeleted': 1, 'hlc': hlcStr, 'nodeId': nodeIdStr},
          where: 'id = ?',
          whereArgs: [pid],
        );
        // Mark associated visitations deleted
        await txn.update(
          'visitations',
          {'isDeleted': 1, 'hlc': hlcStr, 'nodeId': nodeIdStr},
          where: 'patientId = ?',
          whereArgs: [pid],
        );
      }
    });
  }

  /// Count active patient records older than [years] years.
  Future<int> countOldRecords(int years) async {
    final db = await database;
    final thresholdDate = DateTime.now().subtract(Duration(days: years * 365));
    final thresholdIso = thresholdDate.toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM patients WHERE createdAt < ? AND isDeleted = 0',
      [thresholdIso],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> garbageCollectTombstones() async {
    final db = await database;
    // 30 days in milliseconds
    final cutoffTimestamp =
        DateTime.now().millisecondsSinceEpoch - (30 * 24 * 60 * 60 * 1000);

    await db.transaction((txn) async {
      final tables = [
        'patients',
        'visitations',
        'inventory',
        'custom_symptoms',
      ];
      for (final table in tables) {
        final deletedRecords = await txn.query(
          table,
          columns: ['id', 'hlc'],
          where: 'isDeleted = 1',
        );
        for (final r in deletedRecords) {
          final id = r['id'] as String;
          final hlc = r['hlc'] as String;
          try {
            final unpacked = HLC.unpack(hlc);
            // Verify timestamp is older than 30 days and valid (>0)
            if (unpacked.timestamp > 0 &&
                unpacked.timestamp < cutoffTimestamp) {
              await txn.delete(table, where: 'id = ?', whereArgs: [id]);
            }
          } catch (e) {
            // skip if malformed
          }
        }
      }
    });
  }

  // ── Custom Symptoms ───────────────────────────────────────────────

  Future<int> insertCustomSymptom(CustomSymptom symptom) async {
    final db = await database;
    return await db.insert('custom_symptoms', symptom.toMap());
  }

  Future<List<CustomSymptom>> getCustomSymptomsByCategory(
    String category,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'custom_symptoms',
      where: 'category = ? AND isDeleted = 0',
      whereArgs: [category],
    );
    return maps.map((m) => CustomSymptom.fromMap(m)).toList();
  }

  Future<List<CustomSymptom>> getAllCustomSymptoms() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'custom_symptoms',
      where: 'isDeleted = 0',
    );
    return maps.map((m) => CustomSymptom.fromMap(m)).toList();
  }

  Future<int> getCustomSymptomCount(
    String category, {
    String query = '',
  }) async {
    final db = await database;
    String sql =
        'SELECT COUNT(*) as count FROM custom_symptoms WHERE category = ? AND isDeleted = 0';
    List<dynamic> args = [category];
    if (query.isNotEmpty) {
      sql += ' AND name LIKE ?';
      args.add('%$query%');
    }
    final result = await db.rawQuery(sql, args);
    return result.first['count'] as int? ?? 0;
  }

  Future<List<CustomSymptom>> getCustomSymptomsPaginated({
    required String category,
    required int limit,
    required int offset,
    String query = '',
  }) async {
    final db = await database;
    String where = 'category = ? AND isDeleted = 0';
    List<dynamic> whereArgs = [category];
    if (query.isNotEmpty) {
      where += ' AND name LIKE ?';
      whereArgs.add('%$query%');
    }
    final maps = await db.query(
      'custom_symptoms',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => CustomSymptom.fromMap(m)).toList();
  }

  Future<void> deleteCustomSymptomSoft(
    String id, {
    required String hlc,
    required String nodeId,
  }) async {
    final db = await database;
    await db.update(
      'custom_symptoms',
      {'isDeleted': 1, 'hlc': hlc, 'nodeId': nodeId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<CustomSymptom>> getCustomSymptomChangesSince(
    String sinceHlc,
  ) async {
    final db = await database;
    final maps = await db.query(
      'custom_symptoms',
      where: 'hlc > ?',
      whereArgs: [sinceHlc],
      orderBy: 'hlc ASC',
    );
    return maps.map((m) => CustomSymptom.fromMap(m)).toList();
  }

  Future<bool> upsertCustomSymptomFromRemote(CustomSymptom remote) async {
    final db = await database;
    final existing = await db.query(
      'custom_symptoms',
      where: 'id = ?',
      whereArgs: [remote.id],
    );

    if (existing.isEmpty) {
      await db.insert('custom_symptoms', remote.toMap());
      return true;
    }

    final localHlc = HLC.unpack(existing.first['hlc'] as String? ?? '');
    final remoteHlc = HLC.unpack(remote.hlc);

    if (remoteHlc > localHlc) {
      await db.update(
        'custom_symptoms',
        remote.toMap(),
        where: 'id = ?',
        whereArgs: [remote.id],
      );
      return true;
    }
    return false;
  }

  // ── Inventory CRDT ──────────────────────────────────────────────

  Future<List<InventoryItem>> getInventoryChangesSince(String sinceHlc) async {
    final db = await database;
    final maps = await db.query(
      'inventory',
      where: 'hlc > ?',
      whereArgs: [sinceHlc],
      orderBy: 'hlc ASC',
    );
    return maps.map((m) => InventoryItem.fromMap(m)).toList();
  }

  Future<bool> upsertInventoryFromRemote(InventoryItem remote) async {
    final db = await database;
    final existing = await db.query(
      'inventory',
      where: 'id = ?',
      whereArgs: [remote.id],
    );

    if (existing.isEmpty) {
      await db.insert('inventory', remote.toMap());
      return true;
    }

    final localHlc = HLC.unpack(existing.first['hlc'] as String? ?? '');
    final remoteHlc = HLC.unpack(remote.hlc);

    if (remoteHlc > localHlc) {
      await db.update(
        'inventory',
        remote.toMap(),
        where: 'id = ?',
        whereArgs: [remote.id],
      );
      return true;
    }
    return false;
  }

  // ── Inventory Stocks CRDT ──────────────────────────────────────

  Future<List<StockBatch>> getInventoryStockChangesSince(
    String sinceHlc,
  ) async {
    final db = await database;
    final maps = await db.query(
      'inventory_stocks',
      where: 'hlc > ?',
      whereArgs: [sinceHlc],
      orderBy: 'hlc ASC',
    );
    return maps.map((m) => StockBatch.fromMap(m)).toList();
  }

  Future<bool> upsertInventoryStockFromRemote(StockBatch remote) async {
    try {
      final db = await database;
      final existing = await db.query(
        'inventory_stocks',
        where: 'id = ?',
        whereArgs: [remote.id],
      );

      if (existing.isEmpty) {
        await db.insert('inventory_stocks', remote.toMap());
        return true;
      }

      final localHlc = HLC.unpack(existing.first['hlc'] as String? ?? '');
      final remoteHlc = HLC.unpack(remote.hlc);

      if (remoteHlc > localHlc) {
        await db.update(
          'inventory_stocks',
          remote.toMap(),
          where: 'id = ?',
          whereArgs: [remote.id],
        );
        return true;
      }
      return false;
    } catch (e) {
      // Log the full error to see exactly what's failing (casting, constraints, etc.)
      debugPrint('DatabaseHelper: Error upserting stock batch (ID: ${remote.id}, ItemID: ${remote.itemId}): $e');
      return false;
    }
  }

  // ── Inventory Reporting ──────────────────────────────────────────

  Future<List<int>> getInventoryYears() async {
    final db = await database;
    final stocksYears = await db.rawQuery(
      "SELECT DISTINCT strftime('%Y', createdAt) as year FROM inventory_stocks",
    );
    final visitsYears = await db.rawQuery(
      "SELECT DISTINCT strftime('%Y', dateTime) as year FROM visitations WHERE isDeleted = 0",
    );

    Set<int> years = {};
    for (var row in stocksYears) {
      final y = row['year'];
      if (y != null) {
        final parsed = int.tryParse(y.toString());
        if (parsed != null) years.add(parsed);
      }
    }
    for (var row in visitsYears) {
      final y = row['year'];
      if (y != null) {
        final parsed = int.tryParse(y.toString());
        if (parsed != null) years.add(parsed);
      }
    }

    // Also include current year if empty
    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }

    final sortedYears = years.toList()..sort();
    return sortedYears;
  }

  Future<List<Map<String, dynamic>>> getAllVisitationsForReport() async {
    final db = await database;
    return await db.query(
      'visitations',
      where: 'isDeleted = 0',
      columns: ['id', 'dateTime', 'consumedSupplies'],
    );
  }

  // ── Mock Data Management (Dev Only) ──────────────────────────

  Future<Map<String, int>> getMockDataStats() async {
    final db = await database;
    final Map<String, int> stats = {};

    final patients = await db.rawQuery(
      "SELECT COUNT(*) as count FROM patients WHERE nodeId = 'MOCK_NODE'",
    );
    stats['patients'] = patients.first['count'] as int? ?? 0;

    final visits = await db.rawQuery(
      "SELECT COUNT(*) as count FROM visitations WHERE nodeId = 'MOCK_NODE'",
    );
    stats['visitations'] = visits.first['count'] as int? ?? 0;

    final inventory = await db.rawQuery(
      "SELECT COUNT(*) as count FROM inventory WHERE nodeId = 'MOCK_NODE'",
    );
    stats['inventory'] = inventory.first['count'] as int? ?? 0;

    final stocks = await db.rawQuery(
      "SELECT COUNT(*) as count FROM inventory_stocks WHERE nodeId = 'MOCK_NODE'",
    );
    stats['stocks'] = stocks.first['count'] as int? ?? 0;

    final customSymptoms = await db.rawQuery(
      "SELECT COUNT(*) as count FROM custom_symptoms WHERE nodeId = 'MOCK_NODE' AND isDeleted = 0",
    );
    stats['customSymptoms'] = customSymptoms.first['count'] as int? ?? 0;

    final totalPatients = await db.rawQuery(
      "SELECT COUNT(*) as count FROM patients WHERE isDeleted = 0",
    );
    stats['totalActivePatients'] = totalPatients.first['count'] as int? ?? 0;

    final totalVisits = await db.rawQuery(
      "SELECT COUNT(*) as count FROM visitations WHERE isDeleted = 0",
    );
    stats['totalActiveVisitations'] = totalVisits.first['count'] as int? ?? 0;

    return stats;
  }

  Future<void> nukeMockData() async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Delete all stock batches that are mock or belong to a mock inventory item
      await txn.rawDelete('''
        DELETE FROM inventory_stocks 
        WHERE nodeId = 'MOCK_NODE' 
           OR itemId IN (SELECT id FROM inventory WHERE nodeId = 'MOCK_NODE')
      ''');

      // 2. Delete mock inventory items
      await txn.delete('inventory', where: "nodeId = 'MOCK_NODE'");

      // 3. Delete all visitations that are mock or belong to a mock patient
      await txn.rawDelete('''
        DELETE FROM visitations 
        WHERE nodeId = 'MOCK_NODE' 
           OR patientId IN (SELECT id FROM patients WHERE nodeId = 'MOCK_NODE')
      ''');

      // 4. Delete mock patients
      await txn.delete('patients', where: "nodeId = 'MOCK_NODE'");

      // 5. Delete mock custom symptoms
      await txn.delete('custom_symptoms', where: "nodeId = 'MOCK_NODE'");
    });
  }

  Future<void> randomizeInventoryDates() async {
    final db = await database;
    final now = DateTime.now();
    final random = DateTime.now().millisecondsSinceEpoch;

    // We'll update inventory and inventory_stocks created within the last 10 years randomly
    // For simplicity, we just target all MOCK_NODE items
    final inventory = await db.query(
      'inventory',
      where: "nodeId = 'MOCK_NODE'",
    );
    final stocks = await db.query(
      'inventory_stocks',
      where: "nodeId = 'MOCK_NODE'",
    );

    await db.transaction((txn) async {
      int seed = random;
      for (final item in inventory) {
        seed++;
        final rand = (seed * 1103515245 + 12345) & 0x7fffffff;
        final monthsBack = rand % 120; // up to 10 years
        final newDate = now.subtract(Duration(days: monthsBack * 30));
        await txn.update(
          'inventory',
          {'createdAt': newDate.toIso8601String()},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }

      for (final stock in stocks) {
        seed++;
        final rand = (seed * 1103515245 + 12345) & 0x7fffffff;
        final monthsBack = rand % 120;
        final newDate = now.subtract(Duration(days: monthsBack * 30));
        await txn.update(
          'inventory_stocks',
          {'createdAt': newDate.toIso8601String()},
          where: 'id = ?',
          whereArgs: [stock['id']],
        );
      }
    });
  }

  /// Gets visitations with patient details for a specific date range.
  Future<List<Map<String, dynamic>>> getVisitationsWithPatientInfoForRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();

    return await db.rawQuery(
      '''
      SELECT v.*, p.department, p.level, p.role
      FROM visitations v
      JOIN patients p ON v.patientId = p.id
      WHERE v.isDeleted = 0 
        AND v.dateTime >= ? 
        AND v.dateTime <= ?
      ORDER BY v.dateTime ASC
      ''',
      [startIso, endIso],
    );
  }

  /// Gets all patients for export.
  Future<List<Map<String, dynamic>>> getAllPatientsForExport() async {
    final db = await database;
    return await db.query(
      'patients',
      where: 'isDeleted = 0',
      orderBy: 'patientName ASC',
    );
  }

  /// Close the database connection gracefully.
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
