import 'dart:convert';

class Patient {
  final String id;
  final String firstName;
  final String lastName;
  final String middleName;
  final String extension;
  final String patientName;
  final String idNumber;
  final DateTime? birthdate;
  final String sex;
  final String contactNumber;
  final String address;
  final String guardianName;
  final String guardianContact;
  final String guardian2Name;
  final String guardian2Contact;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>> pastMedicalHistory;
  final List<Map<String, dynamic>> vaccinationHistory;
  final String allergicTo;
  final String patientRemarks;
  final Map<String, dynamic> permissions;
  final String role;
  final String department;
  final String level;

  // CRDT fields
  final String hlc;
  final String nodeId;
  final bool isDeleted;

  Patient({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName = '',
    this.extension = '',
    required this.patientName,
    required this.idNumber,
    this.birthdate,
    this.sex = '',
    this.contactNumber = '',
    this.address = '',
    this.guardianName = '',
    this.guardianContact = '',
    this.guardian2Name = '',
    this.guardian2Contact = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.hlc = '',
    this.nodeId = '',
    this.isDeleted = false,
    this.pastMedicalHistory = const [],
    this.vaccinationHistory = const [],
    this.allergicTo = '',
    this.patientRemarks = '',
    this.permissions = const {},
    this.role = '',
    this.department = '',
    this.level = '',
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'extension': extension,
      'patientName': patientName,
      'idNumber': idNumber,
      'birthdate': birthdate?.toIso8601String(),
      'sex': sex,
      'contactNumber': contactNumber,
      'address': address,
      'guardianName': guardianName,
      'guardianContact': guardianContact,
      'guardian2Name': guardian2Name,
      'guardian2Contact': guardian2Contact,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted ? 1 : 0,
      'medicalHistory': jsonEncode(pastMedicalHistory),
      'vaccinationHistory': jsonEncode(vaccinationHistory),
      'allergicTo': allergicTo,
      'patientRemarks': patientRemarks,
      'permissions': jsonEncode(permissions),
      'role': role,
      'department': department,
      'level': level,
    };
  }

  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'] as String,
      firstName: map['firstName'] as String? ?? '',
      lastName: map['lastName'] as String? ?? '',
      middleName: map['middleName'] as String? ?? '',
      extension: map['extension'] as String? ?? '',
      patientName: map['patientName'] as String,
      idNumber: map['idNumber'] as String,
      birthdate: map['birthdate'] != null ? DateTime.parse(map['birthdate'] as String) : null,
      sex: map['sex'] as String? ?? '',
      contactNumber: map['contactNumber'] as String? ?? '',
      address: map['address'] as String? ?? '',
      guardianName: map['guardianName'] as String? ?? '',
      guardianContact: map['guardianContact'] as String? ?? '',
      guardian2Name: map['guardian2Name'] as String? ?? '',
      guardian2Contact: map['guardian2Contact'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      hlc: map['hlc'] as String? ?? '',
      nodeId: map['nodeId'] as String? ?? '',
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
      pastMedicalHistory: map['medicalHistory'] != null 
          ? List<Map<String, dynamic>>.from(jsonDecode(map['medicalHistory'] as String))
          : [],
      vaccinationHistory: map['vaccinationHistory'] != null 
          ? List<Map<String, dynamic>>.from(jsonDecode(map['vaccinationHistory'] as String))
          : [],
      allergicTo: (map['allergicTo'] ?? map['allergic to']) as String? ?? '',
      patientRemarks: (map['patientRemarks'] ?? map['patient remarks']) as String? ?? '',
      permissions: map['permissions'] != null
          ? Map<String, dynamic>.from(jsonDecode(map['permissions'] as String))
          : const {},
      role: map['role'] as String? ?? '',
      department: map['department'] as String? ?? '',
      level: map['level'] as String? ?? '',
    );
  }

  Patient copyWith({
    String? firstName,
    String? lastName,
    String? middleName,
    String? extension,
    String? patientName,
    String? idNumber,
    DateTime? birthdate,
    String? sex,
    String? contactNumber,
    String? address,
    String? guardianName,
    String? guardianContact,
    String? guardian2Name,
    String? guardian2Contact,
    String? hlc,
    String? nodeId,
    bool? isDeleted,
    List<Map<String, dynamic>>? pastMedicalHistory,
    List<Map<String, dynamic>>? vaccinationHistory,
    String? allergicTo,
    String? patientRemarks,
    Map<String, dynamic>? permissions,
    String? role,
    String? department,
    String? level,
  }) {
    return Patient(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      extension: extension ?? this.extension,
      patientName: patientName ?? this.patientName,
      idNumber: idNumber ?? this.idNumber,
      birthdate: birthdate ?? this.birthdate,
      sex: sex ?? this.sex,
      contactNumber: contactNumber ?? this.contactNumber,
      address: address ?? this.address,
      guardianName: guardianName ?? this.guardianName,
      guardianContact: guardianContact ?? this.guardianContact,
      guardian2Name: guardian2Name ?? this.guardian2Name,
      guardian2Contact: guardian2Contact ?? this.guardian2Contact,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      hlc: hlc ?? this.hlc,
      nodeId: nodeId ?? this.nodeId,
      isDeleted: isDeleted ?? this.isDeleted,
      pastMedicalHistory: pastMedicalHistory ?? this.pastMedicalHistory,
      vaccinationHistory: vaccinationHistory ?? this.vaccinationHistory,
      allergicTo: allergicTo ?? this.allergicTo,
      patientRemarks: patientRemarks ?? this.patientRemarks,
      permissions: permissions ?? this.permissions,
      role: role ?? this.role,
      department: department ?? this.department,
      level: level ?? this.level,
    );
  }

  /// Converts this patient to a JSON-compatible map for WebSocket sync.
  Map<String, dynamic> toSyncMap() {
    final map = toMap();
    map['allergic to'] = map.remove('allergicTo');
    map['patient remarks'] = map.remove('patientRemarks');
    return map;
  }

  /// Creates a Patient from a sync payload received over WebSocket.
  factory Patient.fromSyncMap(Map<String, dynamic> map) {
    return Patient.fromMap({
      ...map,
      'allergicTo': map['allergic to'],
      'patientRemarks': map['patient remarks'],
    });
  }
}
