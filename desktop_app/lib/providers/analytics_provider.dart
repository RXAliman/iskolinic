import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../constants/symptoms.dart';

class AnalyticsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  Map<String, int> _symptomCounts = {};
  Map<String, int> _supplyCounts = {};
  bool _loading = false;
  int _totalVisits = 0;

  int get selectedYear => _selectedYear;
  int get selectedMonth => _selectedMonth;
  Map<String, int> get symptomCounts => _symptomCounts;
  Map<String, int> get supplyCounts => _supplyCounts;
  bool get loading => _loading;
  int get totalVisits => _totalVisits;

  Future<void> loadAnalytics() async {
    _loading = true;
    notifyListeners();

    final visitations = await _db.getVisitationsForMonth(
      _selectedYear,
      _selectedMonth,
    );
    _totalVisits = visitations.length;

    // Count each symptom
    final symptomMap = <String, int>{};
    for (final symptom in kSymptomsList) {
      symptomMap[symptom] = 0;
    }
    for (final visit in visitations) {
      for (final symptom in visit.symptoms) {
        symptomMap[symptom] = (symptomMap[symptom] ?? 0) + 1;
      }
    }
    _symptomCounts = symptomMap;

    // Count each supply used
    final supplyMap = <String, int>{};

    // Initialize with all current inventory items (to show 0 counts)
    final inventory = await _db.getAllInventory();
    final idToNameMap = <String, String>{};
    for (final item in inventory) {
      final formattedName = item.clinic.isEmpty
          ? item.itemName
          : "${item.itemName} (${item.clinic})";
      supplyMap[formattedName] = 0;
      idToNameMap[item.id] = formattedName;
    }

    for (final visit in visitations) {
      for (final supplyStr in visit.suppliesUsed) {
        // Extract ID if it's in ID:Name format
        final idPart =
            supplyStr.contains(':') ? supplyStr.split(':')[0] : supplyStr;
        // Resolve ID to current formatted name, or use the snapped/legacy name as fallback
        final displayName = idToNameMap[idPart] ??
            (supplyStr.contains(':') ? supplyStr.split(':')[1] : supplyStr);
        
        supplyMap[displayName] = (supplyMap[displayName] ?? 0) + 1;
      }
    }
    _supplyCounts = supplyMap;

    _loading = false;
    notifyListeners();
  }

  void setMonth(int year, int month) {
    _selectedYear = year;
    _selectedMonth = month;
    loadAnalytics();
  }

  void previousMonth() {
    if (_selectedMonth == 1) {
      _selectedMonth = 12;
      _selectedYear--;
    } else {
      _selectedMonth--;
    }
    loadAnalytics();
  }

  void nextMonth() {
    if (_selectedMonth == 12) {
      _selectedMonth = 1;
      _selectedYear++;
    } else {
      _selectedMonth++;
    }
    loadAnalytics();
  }
}
