class StockBatch {
  final String id;
  final String itemId;
  final int amount;
  final DateTime? expiryDate;
  final DateTime createdAt;

  // CRDT fields
  final String hlc;
  final String nodeId;
  final bool isDeleted;

  StockBatch({
    required this.id,
    required this.itemId,
    required this.amount,
    this.expiryDate,
    required this.hlc,
    required this.nodeId,
    this.isDeleted = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemId': itemId,
      'amount': amount,
      'expiryDate': expiryDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory StockBatch.fromMap(Map<String, dynamic> map) {
    return StockBatch(
      id: map['id'] as String,
      itemId: map['itemId'] as String,
      amount: map['amount'] as int,
      expiryDate: map['expiryDate'] != null
          ? DateTime.parse(map['expiryDate'] as String)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      hlc: map['hlc'] as String? ?? '',
      nodeId: map['nodeId'] as String? ?? '',
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toSyncMap() {
    return {
      'id': id,
      'itemId': itemId,
      'amount': amount,
      'expiryDate': expiryDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted,
    };
  }

  factory StockBatch.fromSyncMap(Map<String, dynamic> map) {
    return StockBatch(
      id: map['id'] as String,
      itemId: map['itemId'] as String,
      amount: map['amount'] as int,
      expiryDate: map['expiryDate'] != null
          ? DateTime.parse(map['expiryDate'] as String)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      hlc: map['hlc'] as String,
      nodeId: map['nodeId'] as String,
      isDeleted: map['isDeleted'] is bool
          ? map['isDeleted'] as bool
          : (map['isDeleted'] as int? ?? 0) == 1,
    );
  }

  StockBatch copyWith({
    int? amount,
    DateTime? expiryDate,
    String? hlc,
    String? nodeId,
    bool? isDeleted,
  }) {
    return StockBatch(
      id: id,
      itemId: itemId,
      amount: amount ?? this.amount,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt,
      hlc: hlc ?? this.hlc,
      nodeId: nodeId ?? this.nodeId,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class InventoryItem {
  final String id;
  final String itemName;
  final int lowStockAmount;
  final String clinic;
  final String itemType; // 'piece' or 'bottle'
  final DateTime createdAt;
  final List<StockBatch> stocks;

  // CRDT fields
  final String hlc;
  final String nodeId;
  final bool isDeleted;

  InventoryItem({
    required this.id,
    required this.itemName,
    required this.lowStockAmount,
    required this.clinic,
    required this.itemType,
    required this.hlc,
    required this.nodeId,
    this.isDeleted = false,
    this.stocks = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get quantity => stocks
      .where((s) => !s.isDeleted)
      .fold(0, (sum, stock) => sum + stock.amount);

  bool get isLowStock => quantity <= lowStockAmount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemName': itemName,
      'lowStockAmount': lowStockAmount,
      'clinic': clinic,
      'itemType': itemType,
      'createdAt': createdAt.toIso8601String(),
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory InventoryItem.fromMap(
    Map<String, dynamic> map, {
    List<StockBatch> stocks = const [],
  }) {
    return InventoryItem(
      id: map['id'] as String,
      itemName: map['itemName'] as String,
      lowStockAmount: map['lowStockAmount'] as int,
      clinic: map['clinic'] as String,
      itemType: map['itemType'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      hlc: map['hlc'] as String? ?? '',
      nodeId: map['nodeId'] as String? ?? '',
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
      stocks: stocks,
    );
  }

  Map<String, dynamic> toSyncMap() {
    return {
      'id': id,
      'itemName': itemName,
      'lowStockAmount': lowStockAmount,
      'clinic': clinic,
      'itemType': itemType,
      'createdAt': createdAt.toIso8601String(),
      'hlc': hlc,
      'nodeId': nodeId,
      'isDeleted': isDeleted,
    };
  }

  factory InventoryItem.fromSyncMap(
    Map<String, dynamic> map, {
    List<StockBatch> stocks = const [],
  }) {
    return InventoryItem(
      id: map['id'] as String,
      itemName: map['itemName'] as String,
      lowStockAmount: map['lowStockAmount'] as int,
      clinic: map['clinic'] as String,
      itemType: map['itemType'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      hlc: map['hlc'] as String,
      nodeId: map['nodeId'] as String,
      isDeleted: map['isDeleted'] is bool
          ? map['isDeleted'] as bool
          : (map['isDeleted'] as int? ?? 0) == 1,
      stocks: stocks,
    );
  }

  InventoryItem copyWith({
    String? itemName,
    int? lowStockAmount,
    String? clinic,
    String? itemType,
    String? hlc,
    String? nodeId,
    bool? isDeleted,
    List<StockBatch>? stocks,
  }) {
    return InventoryItem(
      id: id,
      itemName: itemName ?? this.itemName,
      lowStockAmount: lowStockAmount ?? this.lowStockAmount,
      clinic: clinic ?? this.clinic,
      itemType: itemType ?? this.itemType,
      createdAt: createdAt,
      hlc: hlc ?? this.hlc,
      nodeId: nodeId ?? this.nodeId,
      isDeleted: isDeleted ?? this.isDeleted,
      stocks: stocks ?? this.stocks,
    );
  }
}
