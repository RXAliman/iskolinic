class CustomSymptom {
  final String id;
  final String name;
  final String category; // 'traumatic', 'medical', 'behavioral'
  
  // CRDT fields
  final String hlc;
  final String nodeId;
  final bool isDeleted;

  CustomSymptom({
    required this.id,
    required this.name,
    required this.category,
    required this.hlc,
    required this.nodeId,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory CustomSymptom.fromMap(Map<String, dynamic> map) {
    return CustomSymptom(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      hlc: map['hlc'] as String,
      nodeId: map['nodeId'] as String,
      isDeleted: (map['isDeleted'] as int) == 1,
    );
  }

  Map<String, dynamic> toSyncMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted,
    };
  }

  factory CustomSymptom.fromSyncMap(Map<String, dynamic> map) {
    return CustomSymptom(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      hlc: map['hlc'] as String,
      nodeId: map['nodeId'] as String,
      isDeleted: map['isDeleted'] is bool
          ? map['isDeleted'] as bool
          : (map['isDeleted'] as int? ?? 0) == 1,
    );
  }

  CustomSymptom copyWith({
    String? name,
    String? category,
    String? hlc,
    String? nodeId,
    bool? isDeleted,
  }) {
    return CustomSymptom(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      hlc: hlc ?? this.hlc,
      nodeId: nodeId ?? this.nodeId,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
