/// A singleton service to persist form data and state during navigation.
///
/// This ensures that if the tablet loses connection and the user needs to
/// re-scan or go back to the welcome screen, their progress is not lost.
class PersistentFormService {
  static final PersistentFormService instance =
      PersistentFormService._internal();
  factory PersistentFormService() => instance;
  PersistentFormService._internal();

  bool get isEmpty => firstName.trim().isEmpty && lastName.trim().isEmpty;

  bool get hasData =>
      studentNumber.isNotEmpty ||
      firstName.isNotEmpty ||
      lastName.isNotEmpty ||
      _selectedSymptoms.isNotEmpty ||
      customChiefComplaint.isNotEmpty;

  /// Update core patient fields from a data map (e.g. from desktop API).
  void updateFromMap(Map<String, dynamic> data) {
    isPartial = data['isPartial'] as bool? ?? false;
    existingPatientId = data['id'] as String?;
    firstName = data['firstName'] as String? ?? '';
    lastName = data['lastName'] as String? ?? '';
    middleName = data['middleName'] as String? ?? '';

    // Extension validation
    final incomingExt = data['extension'] as String? ?? 'None';
    const allowedExtensions = ['None', 'JR.', 'SR.', 'I', 'II', 'III'];
    if (incomingExt.trim().isEmpty) {
      extension = 'None';
      customExtension = '';
    } else if (allowedExtensions.contains(incomingExt)) {
      extension = incomingExt;
      customExtension = '';
    } else {
      extension = 'Others';
      customExtension = incomingExt;
    }

    if (data['birthdate'] != null) {
      birthdate = DateTime.tryParse(data['birthdate'] as String);
    }

    // Sex validation
    final incomingSex = data['sex'] as String?;
    const allowedSex = ['Male', 'Female', 'Intersex'];
    if (incomingSex == null || incomingSex.isEmpty) {
      sex = null;
    } else if (allowedSex.contains(incomingSex)) {
      sex = incomingSex;
    } else {
      sex = 'Intersex';
    }

    // Role validation
    final incomingRole = data['role'] as String?;
    const allowedRoles = ['Student', 'Employee'];
    if (incomingRole == null || incomingRole.isEmpty) {
      role = null;
    } else if (allowedRoles.contains(incomingRole)) {
      role = incomingRole;
    } else {
      role = null;
    }

    // Department validation
    final incomingDept = data['department'] as String?;
    const allowedDepts = [
      'General',
      'Pre-school',
      'Grade School',
      'Junior High School',
      'Senior High School',
      'College',
    ];
    if (incomingDept == null || incomingDept.isEmpty) {
      department = null;
    } else if (allowedDepts.contains(incomingDept)) {
      department = incomingDept;
    } else {
      department = null;
    }

    contactNumber = data['contactNumber'] as String? ?? '';
    address = data['address'] as String? ?? '';
    guardianName = data['guardianName'] as String? ?? '';
    guardianContact = data['guardianContact'] as String? ?? '';
    guardian2Name = data['guardian2Name'] as String? ?? '';
    guardian2Contact = data['guardian2Contact'] as String? ?? '';
    allergicTo = data['allergicTo'] as String? ?? '';
    level = data['level'] as String? ?? '';
  }

  // ── Patient Info ─────────────────────────────────────────────────
  String? existingPatientId;
  String studentNumber = '';
  String firstName = '';
  String lastName = '';
  String middleName = '';
  String extension = 'None';
  String customExtension = '';
  DateTime? birthdate;
  String? sex;
  String? role;
  String? department;
  String level = '';
  String contactNumber = '';
  String address = '';
  String guardianName = '';
  String guardianContact = '';
  String guardian2Name = '';
  String guardian2Contact = '';
  String allergicTo = '';
  String customChiefComplaint = '';
  bool isPartial = false;

  // ── Visitation Info ──────────────────────────────────────────────
  final Set<String> _selectedSymptoms = {};

  Set<String> get selectedSymptoms => _selectedSymptoms;

  void addSymptom(String symptom) => _selectedSymptoms.add(symptom);
  void removeSymptom(String symptom) => _selectedSymptoms.remove(symptom);
  void clearSymptoms() => _selectedSymptoms.clear();

  /// Resets all data in the persistence service.
  /// Usually called after successful submission or manual form clear.
  void clear() {
    existingPatientId = null;
    studentNumber = '';
    firstName = '';
    lastName = '';
    middleName = '';
    extension = 'None';
    customExtension = '';
    birthdate = null;
    sex = null;
    role = null;
    department = null;
    contactNumber = '';
    address = '';
    guardianName = '';
    guardianContact = '';
    guardian2Name = '';
    guardian2Contact = '';
    allergicTo = '';
    level = '';
    customChiefComplaint = '';
    isPartial = false;
    _selectedSymptoms.clear();
  }
}
