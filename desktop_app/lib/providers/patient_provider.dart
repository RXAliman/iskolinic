import 'dart:async';
import 'package:flutter/material.dart';
import '../models/patient.dart';
import '../models/visitation.dart';
import '../services/database_helper.dart';
import '../services/excel_export_service.dart';
import '../crdt/hlc.dart';
import '../crdt/node_id.dart';
import '../providers/inventory_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PatientProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  PatientProvider() {
    loadFilters();
  }

  /// Reference to SyncProvider for auto-push after writes.
  /// Set via [setOnLocalWrite] after both providers are created.
  VoidCallback? _onLocalWrite;

  /// Reference to InventoryProvider for auto-deduction on visitation.
  InventoryProvider? _inventoryProvider;

  /// Debounce timer — collapses rapid writes into a single push.
  Timer? _pushDebounce;
  static const _pushDebounceDelay = Duration(milliseconds: 200);

  // Current HLC state (loaded once on init)
  HLC _clock = const HLC(timestamp: 0, counter: 0, nodeId: '');
  String _nodeId = '';

  // Paginated patient data
  List<Patient> _patients = [];
  int _totalPatients = 0;
  int _allPatientsCount = 0;
  int _currentPage = 0;
  final int _pageSize = 10;
  String _searchQuery = '';
  bool _loading = false;

  // Selected patient & visitations
  List<Visitation> _visitations = [];
  Patient? _selectedPatient;
  int _currentVisitPage = 0;
  int _totalVisitations = 0;
  final int _visitPageSize = 10;
  int _todayVisits = 0;

  // Dashboard Visitations list state
  int _dashboardVisitPage = 0;
  final int _dashboardVisitPageSize = 3;
  List<Map<String, dynamic>> _dashboardVisits = [];
  int _dashboardTotalPatients = 0;

  // ── FILTER STATES ──────────────────────────────────────────────────
  List<String> _dashboardSelectedDepartments = [
    'Pre-school',
    'Grade School',
    'Junior High School',
    'Senior High School',
    'College',
  ];
  bool _dashboardIncludeStudent = true;
  bool _dashboardIncludeEmployee = true;

  List<String> _recordsSelectedDepartments = [
    'Pre-school',
    'Grade School',
    'Junior High School',
    'Senior High School',
    'College',
  ];
  bool _recordsIncludeStudent = true;
  bool _recordsIncludeEmployee = true;

  List<String> _visitsSelectedDepartments = [
    'Pre-school',
    'Grade School',
    'Junior High School',
    'Senior High School',
    'College',
  ];
  bool _visitsIncludeStudent = true;
  bool _visitsIncludeEmployee = true;
  DateTime? _visitsSelectedDate;

  Future<void> loadFilters() async {
    final prefs = await SharedPreferences.getInstance();

    final dDepts = prefs.getStringList('dashboard_depts');
    if (dDepts != null) _dashboardSelectedDepartments = dDepts;
    _dashboardIncludeStudent = prefs.getBool('dashboard_student') ?? true;
    _dashboardIncludeEmployee = prefs.getBool('dashboard_employee') ?? true;

    final rDepts = prefs.getStringList('records_depts');
    if (rDepts != null) _recordsSelectedDepartments = rDepts;
    _recordsIncludeStudent = prefs.getBool('records_student') ?? true;
    _recordsIncludeEmployee = prefs.getBool('records_employee') ?? true;

    final vDepts = prefs.getStringList('visits_depts');
    if (vDepts != null) _visitsSelectedDepartments = vDepts;
    _visitsIncludeStudent = prefs.getBool('visits_student') ?? true;
    _visitsIncludeEmployee = prefs.getBool('visits_employee') ?? true;

    final vDateStr = prefs.getString('visits_date');
    if (vDateStr != null) {
      _visitsSelectedDate = DateTime.tryParse(vDateStr);
    } else {
      _visitsSelectedDate = DateTime.now();
    }

    notifyListeners();
  }

  Future<void> _saveFilters(
    String prefix,
    List<String> depts,
    bool student,
    bool employee,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${prefix}_depts', depts);
    await prefs.setBool('${prefix}_student', student);
    await prefs.setBool('${prefix}_employee', employee);
  }

  void clearDashboardFilters() {
    _dashboardSelectedDepartments = [
      'Pre-school',
      'Grade School',
      'Junior High School',
      'Senior High School',
      'College',
      'General',
    ];
    _dashboardIncludeStudent = true;
    _dashboardIncludeEmployee = true;
    _dashboardVisitPage = 0;
    _saveFilters(
      'dashboard',
      _dashboardSelectedDepartments,
      _dashboardIncludeStudent,
      _dashboardIncludeEmployee,
    );
    loadPatients(); // This refreshes today's counts and lists
  }

  // Global visits (Visits Tab) state
  int _globalVisitPage = 0;
  final int _globalVisitPageSize = 10;
  int _totalGlobalVisits = 0;
  List<Map<String, dynamic>> _globalVisitations = [];

  // IDs of records changed by the last sync (for granular rebuild)
  Set<String> _lastSyncChangedIds = {};

  List<Patient> get patients => _patients;
  int get totalPatients => _totalPatients;
  int get allPatientsCount => _allPatientsCount;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  int get totalPages => (_totalPatients / _pageSize).ceil();
  Patient? get selectedPatient => _selectedPatient;
  List<Visitation> get visitations => _visitations;
  int get currentVisitPage => _currentVisitPage;
  int get totalVisitPages => (_totalVisitations / _visitPageSize).ceil();
  int get totalVisitations => _totalVisitations;
  int get visitPageSize => _visitPageSize;
  int get todayVisits => _todayVisits;

  List<Map<String, dynamic>> get dashboardVisits => _dashboardVisits;
  int get dashboardVisitPage => _dashboardVisitPage;
  int get dashboardVisitPageSize => _dashboardVisitPageSize;
  int get totalDashboardVisitPages =>
      (_todayVisits / _dashboardVisitPageSize).ceil();

  bool get loading => _loading;
  String get searchQuery => _searchQuery;
  Set<String> get lastSyncChangedIds => _lastSyncChangedIds;

  // Filter getters
  List<String> get dashboardSelectedDepartments =>
      _dashboardSelectedDepartments;
  bool get dashboardIncludeStudent => _dashboardIncludeStudent;
  bool get dashboardIncludeEmployee => _dashboardIncludeEmployee;
  int get dashboardTotalPatients => _dashboardTotalPatients;
  List<String> get recordsSelectedDepartments => _recordsSelectedDepartments;
  bool get recordsIncludeStudent => _recordsIncludeStudent;
  bool get recordsIncludeEmployee => _recordsIncludeEmployee;
  List<String> get visitsSelectedDepartments => _visitsSelectedDepartments;
  bool get visitsIncludeStudent => _visitsIncludeStudent;
  bool get visitsIncludeEmployee => _visitsIncludeEmployee;

  // Global visits getters
  List<Map<String, dynamic>> get globalVisitations => _globalVisitations;
  int get globalVisitPage => _globalVisitPage;
  int get globalVisitPageSize => _globalVisitPageSize;
  DateTime? get visitsSelectedDate => _visitsSelectedDate;
  int get totalGlobalVisits => _totalGlobalVisits;
  int get totalGlobalVisitPages =>
      (_totalGlobalVisits / _globalVisitPageSize).ceil();

  // ── STATE MUTATORS ─────────────────────────────────────────────────

  /// Register a callback that fires after every local write (used for auto-push sync).
  void setOnLocalWrite(VoidCallback callback) {
    _onLocalWrite = callback;
  }

  /// Set reference to InventoryProvider for auto-deduction.
  void setInventoryProvider(InventoryProvider provider) {
    _inventoryProvider = provider;
  }

  /// Initialize CRDT state — call once on startup.
  Future<void> initCrdt() async {
    _nodeId = await NodeId.get();
    _clock = HLC.now(_nodeId);
  }

  /// Advance the clock for a local write and return the packed HLC string.
  String _tick() {
    _clock = _clock.send();
    return _clock.pack();
  }

  /// Debounced push — waits 200ms after the last write before pushing.
  /// This collapses rapid writes (e.g. bulk imports) into a single sync push.
  void _autoPush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(_pushDebounceDelay, () {
      _onLocalWrite?.call();
    });
  }

  Future<void> loadPatients() async {
    _loading = true;
    notifyListeners();

    final offset = _currentPage * _pageSize;

    _allPatientsCount = await _db.getPatientCount();

    if (_searchQuery.isEmpty) {
      _totalPatients = await _db.getPatientCount(
        selectedDepartments: _recordsSelectedDepartments,
        includeStudent: _recordsIncludeStudent,
        includeEmployee: _recordsIncludeEmployee,
      );
      _patients = await _db.getPatientsPaginated(
        limit: _pageSize,
        offset: offset,
        selectedDepartments: _recordsSelectedDepartments,
        includeStudent: _recordsIncludeStudent,
        includeEmployee: _recordsIncludeEmployee,
      );
    } else {
      _totalPatients = await _db.searchPatientCount(
        query: _searchQuery,
        selectedDepartments: _recordsSelectedDepartments,
        includeStudent: _recordsIncludeStudent,
        includeEmployee: _recordsIncludeEmployee,
      );
      _patients = await _db.searchPatientsPaginated(
        query: _searchQuery,
        limit: _pageSize,
        offset: offset,
        selectedDepartments: _recordsSelectedDepartments,
        includeStudent: _recordsIncludeStudent,
        includeEmployee: _recordsIncludeEmployee,
      );
    }

    _loading = false;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _currentPage = 0;
    loadPatients();
  }

  void toggleRecordsFilter(String filter, bool value) {
    if (filter == 'Student') {
      _recordsIncludeStudent = value;
    } else if (filter == 'Employee') {
      _recordsIncludeEmployee = value;
    } else {
      if (value) {
        if (!_recordsSelectedDepartments.contains(filter)) {
          _recordsSelectedDepartments.add(filter);
        }
      } else {
        _recordsSelectedDepartments.remove(filter);
      }
    }
    _currentPage = 0;
    _saveFilters(
      'records',
      _recordsSelectedDepartments,
      _recordsIncludeStudent,
      _recordsIncludeEmployee,
    );
    loadPatients();
  }

  void clearFilters() {
    _searchQuery = '';
    _recordsSelectedDepartments = [
      'Pre-school',
      'Grade School',
      'Junior High School',
      'Senior High School',
      'College',
      'General',
    ];
    _recordsIncludeStudent = true;
    _recordsIncludeEmployee = true;
    _currentPage = 0;
    _saveFilters(
      'records',
      _recordsSelectedDepartments,
      _recordsIncludeStudent,
      _recordsIncludeEmployee,
    );
    loadPatients();
  }

  /// Reloads patients, today's visits, and patient-specific visits if any.
  Future<void> refreshAll() async {
    await loadPatients();
    await loadTodayVisits();
    await loadGlobalVisits();
    if (_selectedPatient != null) {
      await loadVisitations();
    }
  }

  void goToPage(int page) {
    if (page < 0 || page >= totalPages) return;
    _currentPage = page;
    loadPatients();
  }

  void nextPage() => goToPage(_currentPage + 1);
  void previousPage() => goToPage(_currentPage - 1);
  void firstPage() => goToPage(0);
  void lastPage() => goToPage(totalPages - 1);

  Future<void> addPatient(Patient patient, {String? nodeId}) async {
    final hlc = _tick();
    final withCrdt = patient.copyWith(hlc: hlc, nodeId: nodeId ?? _nodeId);
    await _db.insertPatient(withCrdt);
    await loadPatients();
    _autoPush();
  }

  Future<void> addPatientsBatch(List<Patient> patients) async {
    await _db.insertPatientsBatch(patients);
    await loadPatients();
    _autoPush();
  }

  Future<void> updatePatient(Patient patient) async {
    final hlc = _tick();
    final withCrdt = patient.copyWith(hlc: hlc, nodeId: _nodeId);
    await _db.updatePatient(withCrdt);
    await loadPatients();
    if (_selectedPatient?.id == patient.id) {
      _selectedPatient = withCrdt;
      notifyListeners();
    }
    _autoPush();
  }

  /// Soft-delete: sets isDeleted = 1 with a new HLC.
  Future<void> deletePatient(String id) async {
    final hlc = _tick();
    await _db.deletePatient(id, hlc: hlc);
    if (_selectedPatient?.id == id) {
      _selectedPatient = null;
      _visitations = [];
    }
    // Clamp page if we deleted the last item on the last page
    final newTotal = await _db.getPatientCount();
    final newTotalPages = (newTotal / _pageSize).ceil();
    if (_currentPage >= newTotalPages && _currentPage > 0) {
      _currentPage = newTotalPages - 1;
    }
    await loadPatients();
    await loadTodayVisits();
    _autoPush();
  }

  Future<void> selectPatient(Patient patient) async {
    _selectedPatient = patient;
    _currentVisitPage = 0;
    await loadVisitations();
    notifyListeners();
  }

  Future<void> selectPatientById(String id) async {
    final patient = await _db.getPatient(id);
    if (patient != null) {
      await selectPatient(patient);
    }
  }

  Future<void> loadVisitations() async {
    if (_selectedPatient == null) return;
    final offset = _currentVisitPage * _visitPageSize;
    _totalVisitations = await _db.getVisitationCountForPatient(
      _selectedPatient!.id,
    );
    _visitations = await _db.getVisitationsPaginated(
      _selectedPatient!.id,
      _visitPageSize,
      offset,
    );
    notifyListeners();
  }

  void goToVisitPage(int page) {
    if (page < 0 || (totalVisitPages > 0 && page >= totalVisitPages)) return;
    _currentVisitPage = page;
    loadVisitations();
  }

  void nextVisitPage() => goToVisitPage(_currentVisitPage + 1);
  void prevVisitPage() => goToVisitPage(_currentVisitPage - 1);
  void firstVisitPage() => goToVisitPage(0);
  void lastVisitPage() =>
      goToVisitPage((totalVisitPages > 0 ? totalVisitPages : 1) - 1);

  Future<void> updateVisitation(Visitation visit) async {
    // Before updating, get original to see if new supplies were added
    final original = await _db.getVisitation(visit.id);

    final updatedVisit = visit.copyWith(hlc: _tick());
    await _db.updateVisitation(updatedVisit);

    // If it's a new consumption (not in original), deduct stock
    if (original != null) {
      final originalSet = original.consumedSupplies.toSet();
      for (final supplyStr in visit.consumedSupplies) {
        if (!originalSet.contains(supplyStr)) {
          final id = supplyStr.contains(':')
              ? supplyStr.split(':')[0]
              : supplyStr;
          await _inventoryProvider?.deductStock(id, 1);
        }
      }
    }

    await loadTodayVisits();
    if (_selectedPatient?.id == visit.patientId) {
      await loadVisitations();
    } else {
      notifyListeners();
    }
    _autoPush();
  }

  Future<void> deleteVisitation(Visitation visit) async {
    final deletedVisit = visit.copyWith(isDeleted: true, hlc: _tick());
    await _db.updateVisitation(deletedVisit);

    // Inventory restocking is complex due to FEFO, omitted for now.

    await loadTodayVisits();
    if (_selectedPatient?.id == visit.patientId) {
      if (_visitations.length == 1 && _currentVisitPage > 0) {
        _currentVisitPage--;
      }
      await loadVisitations();
    } else {
      notifyListeners();
    }
    _autoPush();
  }

  Future<void> addVisitation({
    required String patientId,
    required List<String> symptoms,
    List<String> suppliesUsed = const [],
    List<String> consumedSupplies = const [],
    required String treatment,
    required String remarks,
    String customChiefComplaint = '',
    DateTime? dateTime,
    String? nodeId,
  }) async {
    final hlc = _tick();
    final visit = Visitation(
      id: const Uuid().v4(),
      patientId: patientId,
      dateTime: dateTime,
      symptoms: symptoms,
      suppliesUsed: suppliesUsed,
      treatment: treatment,
      remarks: remarks,
      customChiefComplaint: customChiefComplaint,
      hlc: hlc,
      nodeId: nodeId ?? _nodeId,
    );
    await _db.insertVisitation(visit);

    // Conditionally deduct stock
    for (final supplyStr in consumedSupplies) {
      // Resolve ID if it's in ID:Name format
      final id = supplyStr.contains(':') ? supplyStr.split(':')[0] : supplyStr;
      await _inventoryProvider?.deductStock(id, 1);
    }

    await loadTodayVisits();

    if (_selectedPatient?.id == patientId) {
      _currentVisitPage = 0;
      await loadVisitations();
    } else {
      notifyListeners();
    }
    _autoPush();
  }

  Future<void> addVisitationsBatch(List<Visitation> visits) async {
    await _db.insertVisitationsBatch(visits);

    await loadTodayVisits();

    // If any of the visits are for the selected patient, refresh.
    if (_selectedPatient != null &&
        visits.any((v) => v.patientId == _selectedPatient!.id)) {
      _currentVisitPage = 0;
      await loadVisitations();
    } else {
      notifyListeners();
    }
    _autoPush();
  }

  Future<void> loadTodayVisits() async {
    _dashboardTotalPatients = await _db.getPatientCount(
      selectedDepartments: _dashboardSelectedDepartments,
      includeStudent: _dashboardIncludeStudent,
      includeEmployee: _dashboardIncludeEmployee,
    );
    _todayVisits = await _db.getTodayVisitCount(
      selectedDepartments: _dashboardSelectedDepartments,
      includeStudent: _dashboardIncludeStudent,
      includeEmployee: _dashboardIncludeEmployee,
    );
    await loadDashboardVisits();
  }

  Future<void> loadDashboardVisits() async {
    final offset = _dashboardVisitPage * _dashboardVisitPageSize;
    _dashboardVisits = await _db.getTodayVisitationsPaginated(
      limit: _dashboardVisitPageSize,
      offset: offset,
      selectedDepartments: _dashboardSelectedDepartments,
      includeStudent: _dashboardIncludeStudent,
      includeEmployee: _dashboardIncludeEmployee,
    );
    notifyListeners();
  }

  void toggleDashboardFilter(String filter, bool value) {
    if (filter == 'Student') {
      _dashboardIncludeStudent = value;
    } else if (filter == 'Employee') {
      _dashboardIncludeEmployee = value;
    } else {
      if (value) {
        if (!_dashboardSelectedDepartments.contains(filter)) {
          _dashboardSelectedDepartments.add(filter);
        }
      } else {
        _dashboardSelectedDepartments.remove(filter);
      }
    }
    _dashboardVisitPage = 0;
    _saveFilters(
      'dashboard',
      _dashboardSelectedDepartments,
      _dashboardIncludeStudent,
      _dashboardIncludeEmployee,
    );
    loadTodayVisits();
  }

  void goToDashboardVisitPage(int page) {
    if (page < 0 ||
        (totalDashboardVisitPages > 0 && page >= totalDashboardVisitPages)) {
      return;
    }
    _dashboardVisitPage = page;
    loadDashboardVisits();
  }

  void nextDashboardVisitPage() =>
      goToDashboardVisitPage(_dashboardVisitPage + 1);
  void prevDashboardVisitPage() =>
      goToDashboardVisitPage(_dashboardVisitPage - 1);
  void firstDashboardVisitPage() => goToDashboardVisitPage(0);
  void lastDashboardVisitPage() => goToDashboardVisitPage(
    (totalDashboardVisitPages > 0 ? totalDashboardVisitPages : 1) - 1,
  );

  // ── Global Visits (Visits Tab) ───────────────────────────────────

  Future<void> loadGlobalVisits() async {
    _loading = true;
    notifyListeners();

    _totalGlobalVisits = await _db.getGlobalVisitCount(
      selectedDepartments: _visitsSelectedDepartments,
      includeStudent: _visitsIncludeStudent,
      includeEmployee: _visitsIncludeEmployee,
      date: _visitsSelectedDate,
    );

    final offset = _globalVisitPage * _globalVisitPageSize;
    _globalVisitations = await _db.getGlobalVisitationsPaginated(
      limit: _globalVisitPageSize,
      offset: offset,
      selectedDepartments: _visitsSelectedDepartments,
      includeStudent: _visitsIncludeStudent,
      includeEmployee: _visitsIncludeEmployee,
      date: _visitsSelectedDate,
    );
    _loading = false;
    notifyListeners();
  }

  void goToGlobalVisitPage(int page) {
    if (page < 0 ||
        (totalGlobalVisitPages > 0 && page >= totalGlobalVisitPages)) {
      return;
    }
    _globalVisitPage = page;
    loadGlobalVisits();
  }

  void nextGlobalVisitPage() => goToGlobalVisitPage(_globalVisitPage + 1);
  void prevGlobalVisitPage() => goToGlobalVisitPage(_globalVisitPage - 1);
  void firstGlobalVisitPage() => goToGlobalVisitPage(0);
  void lastGlobalVisitPage() => goToGlobalVisitPage(
    (totalGlobalVisitPages > 0 ? totalGlobalVisitPages : 1) - 1,
  );

  void toggleVisitsFilter(String filter, bool value) {
    if (filter == 'Student') {
      _visitsIncludeStudent = value;
    } else if (filter == 'Employee') {
      _visitsIncludeEmployee = value;
    } else {
      if (value) {
        if (!_visitsSelectedDepartments.contains(filter)) {
          _visitsSelectedDepartments.add(filter);
        }
      } else {
        _visitsSelectedDepartments.remove(filter);
      }
    }
    _globalVisitPage = 0;
    _saveFilters(
      'visits',
      _visitsSelectedDepartments,
      _visitsIncludeStudent,
      _visitsIncludeEmployee,
    );
    loadGlobalVisits();
  }

  void setVisitsDate(DateTime? date) async {
    _visitsSelectedDate = date;
    _globalVisitPage = 0;
    final prefs = await SharedPreferences.getInstance();
    if (date != null) {
      await prefs.setString('visits_date', date.toIso8601String());
    } else {
      await prefs.remove('visits_date');
    }
    loadGlobalVisits();
  }

  void previousVisitsDay() {
    final current = _visitsSelectedDate ?? DateTime.now();
    setVisitsDate(current.subtract(const Duration(days: 1)));
  }

  void nextVisitsDay() {
    final current = _visitsSelectedDate ?? DateTime.now();
    final next = current.add(const Duration(days: 1));
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final nextStart = DateTime(next.year, next.month, next.day);

    if (nextStart.isAfter(todayStart)) {
      return;
    } else {
      setVisitsDate(next);
    }
  }

  void clearVisitsFilters() async {
    _visitsSelectedDepartments = [
      'Pre-school',
      'Grade School',
      'Junior High School',
      'Senior High School',
      'College',
      'General',
    ];
    _visitsIncludeStudent = true;
    _visitsIncludeEmployee = true;
    _globalVisitPage = 0;
    _saveFilters(
      'visits',
      _visitsSelectedDepartments,
      _visitsIncludeStudent,
      _visitsIncludeEmployee,
    );
    loadGlobalVisits();
  }

  // ── Granular sync refresh ────────────────────────────────────────

  /// Called by SyncProvider after a batch merge completes.
  /// Only triggers notifyListeners if the changed IDs intersect with
  /// the currently displayed page.
  Future<void> onSyncComplete(Set<String> changedIds) async {
    _lastSyncChangedIds = changedIds;

    // Check if any currently displayed patient was affected
    final displayedIds = _patients.map((p) => p.id).toSet();
    final needsRefresh = displayedIds.intersection(changedIds).isNotEmpty;

    if (needsRefresh) {
      await loadPatients();
      await loadGlobalVisits();
    }

    // If the selected patient was updated, refresh it
    if (_selectedPatient != null && changedIds.contains(_selectedPatient!.id)) {
      final refreshed = await _db.getPatient(_selectedPatient!.id);
      _selectedPatient = refreshed;
      if (_selectedPatient != null) {
        _visitations = await _db.getVisitationsForPatient(_selectedPatient!.id);
      }
      notifyListeners();
    }
  }

  // ── Data Export ──────────────────────────────────────────────────

  Future<String?> exportPatientsReport({String? savePath}) async {
    _loading = true;
    notifyListeners();

    try {
      final result = await ExcelExportService.instance.exportPatientsReport(
        savePath: savePath,
      );
      return result;
    } catch (e) {
      debugPrint('Export error: $e');
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
