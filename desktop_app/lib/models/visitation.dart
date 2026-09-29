class Visitation {
  final String id;
  final String patientId;
  final DateTime dateTime;
  final List<String> symptoms;
  final List<String> suppliesUsed;
  final List<String> consumedSupplies;
  final String treatment;
  final String remarks;
  final String customChiefComplaint;

  // CRDT fields
  final String hlc;
  final String nodeId;
  final bool isDeleted;

  Visitation({
    required this.id,
    required this.patientId,
    DateTime? dateTime,
    this.symptoms = const [],
    this.suppliesUsed = const [],
    this.consumedSupplies = const [],
    this.treatment = '',
    this.remarks = '',
    this.customChiefComplaint = '',
    this.hlc = '',
    this.nodeId = '',
    this.isDeleted = false,
  }) : dateTime = dateTime ?? DateTime.now();

  Visitation copyWith({
    String? id,
    String? patientId,
    DateTime? dateTime,
    List<String>? symptoms,
    List<String>? suppliesUsed,
    List<String>? consumedSupplies,
    String? treatment,
    String? remarks,
    String? customChiefComplaint,
    String? hlc,
    String? nodeId,
    bool? isDeleted,
  }) {
    return Visitation(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      dateTime: dateTime ?? this.dateTime,
      symptoms: symptoms ?? this.symptoms,
      suppliesUsed: suppliesUsed ?? this.suppliesUsed,
      consumedSupplies: consumedSupplies ?? this.consumedSupplies,
      treatment: treatment ?? this.treatment,
      remarks: remarks ?? this.remarks,
      customChiefComplaint: customChiefComplaint ?? this.customChiefComplaint,
      hlc: hlc ?? this.hlc,
      nodeId: nodeId ?? this.nodeId,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'dateTime': dateTime.toIso8601String(),
      'symptoms': symptoms.join('|'),
      'suppliesUsed': suppliesUsed.join('|'),
      'consumedSupplies': consumedSupplies.join('|'),
      'treatment': treatment,
      'remarks': remarks,
      'customChiefComplaint': customChiefComplaint,
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Visitation.fromMap(Map<String, dynamic> map) {
    final symptomsStr = map['symptoms'] as String? ?? '';
    final suppliesStr = map['suppliesUsed'] as String? ?? '';
    final consumedStr = map['consumedSupplies'] as String? ?? '';
    return Visitation(
      id: map['id'] as String,
      patientId: map['patientId'] as String,
      dateTime: DateTime.parse(map['dateTime'] as String),
      symptoms: symptomsStr.isEmpty ? [] : symptomsStr.split('|'),
      suppliesUsed: suppliesStr.isEmpty ? [] : suppliesStr.split('|'),
      consumedSupplies: consumedStr.isEmpty ? [] : consumedStr.split('|'),
      treatment: map['treatment'] as String? ?? '',
      remarks: map['remarks'] as String? ?? '',
      customChiefComplaint: map['customChiefComplaint'] as String? ?? '',
      hlc: map['hlc'] as String? ?? '',
      nodeId: map['nodeId'] as String? ?? '',
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
    );
  }

  /// Converts this visitation to a JSON-compatible map for WebSocket sync.
  Map<String, dynamic> toSyncMap() => toMap();

  /// Creates a Visitation from a sync payload received over WebSocket.
  factory Visitation.fromSyncMap(Map<String, dynamic> map) =>
      Visitation.fromMap(map);
}
