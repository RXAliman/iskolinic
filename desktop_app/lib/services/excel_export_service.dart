import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../models/custom_symptom.dart';
import '../models/inventory_item.dart';
import '../services/database_helper.dart';
import '../constants/symptoms.dart';

class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._internal();
  ExcelExportService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<String?> exportSymptomsReport({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, bool> departments,
    required Map<String, bool> expandDepartments,
    required bool includeStudent,
    required bool includeEmployee,
    String? savePath,
  }) async {
    // Fetch data on main thread (SQLite needs main thread context)
    final List<Map<String, dynamic>> visitationsData =
        await _db.getVisitationsWithPatientInfoForRange(startDate, endDate);
    final List<CustomSymptom> customSymptoms = (await _db.getAllCustomSymptoms())
        .where((s) =>
            s.category == 'traumatic' ||
            s.category == 'medical' ||
            s.category == 'behavioral')
        .toList();

    // Offload the heavy Excel generation to an isolate
    final List<int>? fileBytes = await compute(_generateSymptomsExcelBytes, {
      'visitationsData': visitationsData,
      'customSymptoms': customSymptoms.map((s) => s.name).toList(),
      'departments': departments,
      'expandDepartments': expandDepartments,
      'includeStudent': includeStudent,
      'includeEmployee': includeEmployee,
    });

    if (fileBytes == null) return null;

    return _saveBytes(
      fileBytes,
      savePath: savePath,
      defaultFileName:
          'Symptoms_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
  }

  static List<int>? _generateSymptomsExcelBytes(Map<String, dynamic> params) {
    final List<Map<String, dynamic>> visitationsData = params['visitationsData'];
    final List<String> customSymptomNames = params['customSymptoms'];
    final Map<String, bool> departments = params['departments'];
    final Map<String, bool> expandDepartments = params['expandDepartments'];
    final bool includeStudent = params['includeStudent'];
    final bool includeEmployee = params['includeEmployee'];

    final excel = Excel.createExcel();
    final List<String> allSymptoms = [...kSymptomsList, ...customSymptomNames];

    if (includeStudent) {
      _fillSymptomsSheet(
        sheet: excel['Student Symptoms'],
        visitationsData: visitationsData,
        targetRole: 'Student',
        departments: departments,
        expandDepartments: expandDepartments,
        allSymptoms: allSymptoms,
      );
    }

    if (includeEmployee) {
      _fillSymptomsSheet(
        sheet: excel['Employee Symptoms'],
        visitationsData: visitationsData,
        targetRole: 'Employee',
        departments: departments,
        expandDepartments: expandDepartments,
        allSymptoms: allSymptoms,
      );
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    return excel.save();
  }

  static void _fillSymptomsSheet({
    required Sheet sheet,
    required List<Map<String, dynamic>> visitationsData,
    required String targetRole,
    required Map<String, bool> departments,
    required Map<String, bool> expandDepartments,
    required List<String> allSymptoms,
  }) {
    // Header Row
    sheet.appendRow([
      TextCellValue('Department/Level'),
      ...allSymptoms.map((s) => TextCellValue(s)),
    ]);

    final rowsToProcess =
        _getRowsToProcessStatic(departments, expandDepartments);

    for (final rowInfo in rowsToProcess) {
      final String rowLabel = rowInfo['label'];
      final String dept = rowInfo['dept'];
      final String? level = rowInfo['level'];

      final rowData = <CellValue>[TextCellValue(rowLabel)];

      for (final symptom in allSymptoms) {
        int count = 0;
        for (final visitMap in visitationsData) {
          final String visitRole = visitMap['role'] as String? ?? '';
          if (visitRole != targetRole) continue;

          final String symptomsRaw = visitMap['symptoms'] as String? ?? '';
          final List<String> visitSymptoms =
              symptomsRaw.isEmpty ? [] : symptomsRaw.split('|');

          final String visitDept = visitMap['department'] as String? ?? '';
          final String visitLevel = visitMap['level'] as String? ?? '';

          bool matches = false;
          if (level != null) {
            matches = visitDept == dept && visitLevel == level;
          } else {
            matches = visitDept == dept;
          }

          if (matches && visitSymptoms.contains(symptom)) {
            count++;
          }
        }
        rowData.add(IntCellValue(count));
      }
      sheet.appendRow(rowData);
    }
  }

  Future<String?> exportSuppliesReport({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, bool> departments,
    required Map<String, bool> expandDepartments,
    required bool includeStudent,
    required bool includeEmployee,
    String? savePath,
  }) async {
    // Fetch data on main thread
    final List<Map<String, dynamic>> visitationsData =
        await _db.getVisitationsWithPatientInfoForRange(startDate, endDate);
    final List<InventoryItem> inventory = await _db.getAllInventory();

    // Offload to isolate
    final List<int>? fileBytes = await compute(_generateSuppliesExcelBytes, {
      'visitationsData': visitationsData,
      'inventory': inventory
          .map((item) => {
                'id': item.id,
                'itemName': item.itemName,
                'clinic': item.clinic,
              })
          .toList(),
      'departments': departments,
      'expandDepartments': expandDepartments,
      'includeStudent': includeStudent,
      'includeEmployee': includeEmployee,
    });

    if (fileBytes == null) return null;

    return _saveBytes(
      fileBytes,
      savePath: savePath,
      defaultFileName:
          'Supplies_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
  }

  static List<int>? _generateSuppliesExcelBytes(Map<String, dynamic> params) {
    final List<Map<String, dynamic>> visitationsData = params['visitationsData'];
    final List<Map<String, dynamic>> inventoryData = params['inventory'];
    final Map<String, bool> departments = params['departments'];
    final Map<String, bool> expandDepartments = params['expandDepartments'];
    final bool includeStudent = params['includeStudent'];
    final bool includeEmployee = params['includeEmployee'];

    final excel = Excel.createExcel();
    final List<String> allSupplies = inventoryData.map((item) {
      final name = item['itemName'] as String;
      final clinic = item['clinic'] as String;
      return clinic.isEmpty ? name : "$name ($clinic)";
    }).toList();

    final Map<String, String> supplyIdToName = {};
    for (final item in inventoryData) {
      final name = item['itemName'] as String;
      final clinic = item['clinic'] as String;
      final displayName = clinic.isEmpty ? name : "$name ($clinic)";
      supplyIdToName[item['id']] = displayName;
    }

    if (includeStudent) {
      _fillSuppliesSheet(
        sheet: excel['Student Supplies'],
        visitationsData: visitationsData,
        targetRole: 'Student',
        departments: departments,
        expandDepartments: expandDepartments,
        allSupplies: allSupplies,
        supplyIdToName: supplyIdToName,
      );
    }

    if (includeEmployee) {
      _fillSuppliesSheet(
        sheet: excel['Employee Supplies'],
        visitationsData: visitationsData,
        targetRole: 'Employee',
        departments: departments,
        expandDepartments: expandDepartments,
        allSupplies: allSupplies,
        supplyIdToName: supplyIdToName,
      );
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    return excel.save();
  }

  static void _fillSuppliesSheet({
    required Sheet sheet,
    required List<Map<String, dynamic>> visitationsData,
    required String targetRole,
    required Map<String, bool> departments,
    required Map<String, bool> expandDepartments,
    required List<String> allSupplies,
    required Map<String, String> supplyIdToName,
  }) {
    sheet.appendRow([
      TextCellValue('Department/Level'),
      ...allSupplies.map((s) => TextCellValue(s)),
    ]);

    final rowsToProcess =
        _getRowsToProcessStatic(departments, expandDepartments);

    for (final rowInfo in rowsToProcess) {
      final String rowLabel = rowInfo['label'];
      final String dept = rowInfo['dept'];
      final String? level = rowInfo['level'];

      final rowData = <CellValue>[TextCellValue(rowLabel)];

      for (final supplyName in allSupplies) {
        int count = 0;
        for (final visitMap in visitationsData) {
          final String visitRole = visitMap['role'] as String? ?? '';
          if (visitRole != targetRole) continue;

          final String suppliesRaw = visitMap['suppliesUsed'] as String? ?? '';
          final List<String> suppliesUsed =
              suppliesRaw.isEmpty ? [] : suppliesRaw.split('|');

          final String visitDept = visitMap['department'] as String? ?? '';
          final String visitLevel = visitMap['level'] as String? ?? '';

          bool matches = false;
          if (level != null) {
            matches = visitDept == dept && visitLevel == level;
          } else {
            matches = visitDept == dept;
          }

          if (matches) {
            for (final usedSupply in suppliesUsed) {
              final String usedStr = usedSupply.toString();
              final idPart =
                  usedStr.contains(':') ? usedStr.split(':')[0] : usedStr;
              final resolvedName = supplyIdToName[idPart] ??
                  (usedStr.contains(':') ? usedStr.split(':')[1] : usedStr);

              if (resolvedName == supplyName) {
                count++;
              }
            }
          }
        }
        rowData.add(IntCellValue(count));
      }
      sheet.appendRow(rowData);
    }
  }

  Future<String?> exportPatientsReport({String? savePath}) async {
    final List<Map<String, dynamic>> patientsData = await _db.getAllPatientsForExport();
    
    final List<int>? fileBytes = await compute(_generatePatientsExcelBytes, patientsData);
    
    if (fileBytes == null) return null;

    return _saveBytes(
      fileBytes,
      savePath: savePath,
      defaultFileName: 'Patients_List_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
  }

  static List<int>? _generatePatientsExcelBytes(List<Map<String, dynamic>> patientsData) {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Patients'];
    excel.delete('Sheet1');

    // Header Row
    sheet.appendRow([
      TextCellValue('ID Number'),
      TextCellValue('Patient Name'),
      TextCellValue('Role'),
      TextCellValue('Department'),
      TextCellValue('Level'),
      TextCellValue('Sex'),
      TextCellValue('Birthdate'),
      TextCellValue('Contact'),
      TextCellValue('Address'),
      TextCellValue('Guardian'),
      TextCellValue('Guardian Contact'),
    ]);

    for (final p in patientsData) {
      sheet.appendRow([
        TextCellValue(p['idNumber'] ?? ''),
        TextCellValue(p['patientName'] ?? ''),
        TextCellValue(p['role'] ?? ''),
        TextCellValue(p['department'] ?? ''),
        TextCellValue(p['level'] ?? ''),
        TextCellValue(p['sex'] ?? ''),
        TextCellValue(p['birthdate'] ?? ''),
        TextCellValue(p['contactNumber'] ?? ''),
        TextCellValue(p['address'] ?? ''),
        TextCellValue(p['guardianName'] ?? ''),
        TextCellValue(p['guardianContact'] ?? ''),
      ]);
    }

    return excel.save();
  }

  static List<Map<String, dynamic>> _getRowsToProcessStatic(
    Map<String, bool> departments,
    Map<String, bool> expandDepartments,
  ) {
    final List<Map<String, dynamic>> rows = [];

    final List<Map<String, dynamic>> deptConfigs = [
      {'dept': 'Pre-school', 'levels': ['Nursery', 'Pre-Kinder', 'Kinder']},
      {'dept': 'Grade School', 'levels': ['Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6']},
      {'dept': 'Junior High School', 'levels': ['Grade 7', 'Grade 8', 'Grade 9', 'Grade 10']},
      {'dept': 'Senior High School', 'levels': ['Grade 11', 'Grade 12']},
      {'dept': 'College', 'levels': ['First Year', 'Second Year', 'Third Year', 'Fourth Year']},
    ];

    final Set<String> processedDepts = {};

    for (final config in deptConfigs) {
      final String dept = config['dept'];
      processedDepts.add(dept);
      if (departments[dept] == true) {
        if (expandDepartments[dept] == true) {
          for (final level in config['levels']) {
            rows.add({'label': level, 'dept': dept, 'level': level});
          }
          // Include students with no level in the expanded department report
          rows.add({'label': '$dept (Uncategorized)', 'dept': dept, 'level': ''});
        } else {
          rows.add({'label': dept, 'dept': dept, 'level': null});
        }
      }
    }

    // Handle any other departments that might have been passed (e.g. Employees)
    for (final dept in departments.keys) {
      if (!processedDepts.contains(dept) && departments[dept] == true) {
        rows.add({'label': dept, 'dept': dept, 'level': null});
      }
    }

    return rows;
  }

  Future<String?> _saveBytes(
    List<int> fileBytes, {
    String? savePath,
    required String defaultFileName,
  }) async {
    String finalPath;
    if (savePath != null) {
      finalPath = savePath;
    } else {
      final directory = await getApplicationSupportDirectory();
      final exportDir = Directory(p.join(directory.path, 'exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      finalPath = p.join(exportDir.path, defaultFileName);
    }

    final File file = File(finalPath);
    await file.writeAsBytes(fileBytes);
    return finalPath;
  }
}
