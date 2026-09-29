import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/inventory_item.dart';
import '../services/database_helper.dart';
import '../crdt/hlc.dart';
import '../crdt/node_id.dart';

class InventoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Called to push changes after local write
  Future<void> Function()? onLocalChange;

  List<InventoryItem> _items = [];
  int _totalItems = 0;
  int _currentPage = 0;
  final int _pageSize = 10;
  String _searchQuery = '';
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  bool _loading = false;
  List<InventoryItem> _lowStockItems = []; // Global list of all low stock items
  List<InventoryItem> _expiringItems =
      []; // Items with stocks expiring in < 3 months
  List<InventoryItem> _allItems = []; // Global list of all inventory items
  final Set<String> _pendingDeductions =
      {}; // Safeguard against duplicate requests

  List<InventoryItem> get items => _items;
  int get totalItems => _totalItems;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  int get totalPages => (_totalItems / _pageSize).ceil();
  String get searchQuery => _searchQuery;
  int get sortColumnIndex => _sortColumnIndex;
  bool get sortAscending => _sortAscending;
  bool get loading => _loading;
  List<InventoryItem> get lowStockItems => _lowStockItems;
  List<InventoryItem> get expiringItems => _expiringItems;
  List<InventoryItem> get allItems => _allItems;

  Future<void> loadInventory() async {
    _loading = true;
    notifyListeners();

    final orderBy = _getSortColumn(_sortColumnIndex);

    _items = await _db.searchInventoryPaginated(
      query: _searchQuery,
      limit: _pageSize,
      offset: _currentPage * _pageSize,
      orderBy: orderBy,
      ascending: _sortAscending,
    );

    _totalItems = await _db.getInventoryCount(_searchQuery);

    // Refresh global lists for dashboard/helpers
    _allItems = await _db.getAllInventoryItems();
    _lowStockItems = _allItems.where((i) => i.isLowStock).toList();
    _updateExpiringItems();

    _loading = false;
    notifyListeners();
  }

  void _updateExpiringItems() {
    final now = DateTime.now();
    final threshold = now.add(const Duration(days: 90)); // ~3 months

    _expiringItems = _allItems.where((item) {
      return item.stocks.any((stock) {
        if (stock.expiryDate == null || stock.isDeleted || stock.amount <= 0) {
          return false;
        }
        return stock.expiryDate!.isBefore(threshold);
      });
    }).toList();

    // Sort expiring items by the earliest expiry date found in their stocks
    _expiringItems.sort((a, b) {
      final aEarliest = a.stocks
          .where((s) => !s.isDeleted && s.amount > 0 && s.expiryDate != null)
          .fold<DateTime?>(
            null,
            (min, s) =>
                min == null || s.expiryDate!.isBefore(min) ? s.expiryDate : min,
          );
      final bEarliest = b.stocks
          .where((s) => !s.isDeleted && s.amount > 0 && s.expiryDate != null)
          .fold<DateTime?>(
            null,
            (min, s) =>
                min == null || s.expiryDate!.isBefore(min) ? s.expiryDate : min,
          );

      if (aEarliest == null) return 1;
      if (bEarliest == null) return -1;
      return aEarliest.compareTo(bEarliest);
    });
  }

  String _getSortColumn(int index) {
    switch (index) {
      case 0:
        return 'itemName';
      case 1:
        return 'itemName'; // quantity is derived now, sort by name or we could do something more complex
      case 2:
        return 'clinic';
      case 3:
        return 'itemType';
      case 4:
        return 'lowStockAmount';
      default:
        return 'itemName';
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _currentPage = 0;
    loadInventory();
  }

  void setSort(int index, bool ascending) {
    _sortColumnIndex = index;
    _sortAscending = ascending;
    _currentPage = 0;
    loadInventory();
  }

  void nextPage() {
    if (_currentPage < totalPages - 1) {
      _currentPage++;
      loadInventory();
    }
  }

  void previousPage() {
    if (_currentPage > 0) {
      _currentPage--;
      loadInventory();
    }
  }

  void firstPage() {
    _currentPage = 0;
    loadInventory();
  }

  void lastPage() {
    _currentPage = totalPages - 1;
    loadInventory();
  }

  Future<void> addNewSupplyItem({
    required String itemName,
    required int lowStockAmount,
    required String clinic,
    required String itemType,
    List<({int amount, DateTime? expiry})>? initialStocks,
    String? nodeId,
  }) async {
    final effectiveNodeId = nodeId ?? await NodeId.get();
    final hlc = HLC.now(effectiveNodeId).pack();
    final itemId = const Uuid().v4();

    final item = InventoryItem(
      id: itemId,
      itemName: itemName,
      lowStockAmount: lowStockAmount,
      clinic: clinic,
      itemType: itemType,
      hlc: hlc,
      nodeId: effectiveNodeId,
    );
    await _db.insertInventoryItem(item);

    if (initialStocks != null) {
      for (final entry in initialStocks) {
        if (entry.amount <= 0) continue;
        final stock = StockBatch(
          id: const Uuid().v4(),
          itemId: itemId,
          amount: entry.amount,
          expiryDate: entry.expiry,
          hlc: hlc,
          nodeId: effectiveNodeId,
        );
        await _db.insertStockBatch(stock);
      }
    }

    await loadInventory();
    onLocalChange?.call();
  }

  Future<void> updateInventoryItem(InventoryItem item) async {
    final nodeId = await NodeId.get();
    final updated = item.copyWith(hlc: HLC.now(nodeId).pack(), nodeId: nodeId);
    await _db.updateInventoryItem(updated);
    await loadInventory();
    onLocalChange?.call();
  }

  Future<void> addStockBatch({
    required String itemId,
    required int amount,
    DateTime? expiryDate,
    String? nodeId,
  }) async {
    final effectiveNodeId = nodeId ?? await NodeId.get();
    final hlc = HLC.now(effectiveNodeId).pack();

    final stock = StockBatch(
      id: const Uuid().v4(),
      itemId: itemId,
      amount: amount,
      expiryDate: expiryDate,
      hlc: hlc,
      nodeId: effectiveNodeId,
    );
    await _db.insertStockBatch(stock);
    await loadInventory();
    onLocalChange?.call();
  }

  Future<void> updateStockBatch(StockBatch stock) async {
    final nodeId = await NodeId.get();
    final hlc = HLC.now(nodeId).pack();

    // If amount is 0 or less, auto-delete the batch
    if (stock.amount <= 0) {
      await _db.deleteStockBatch(stock.id, hlc: hlc, nodeId: nodeId);
    } else {
      final updated = stock.copyWith(hlc: hlc, nodeId: nodeId);
      await _db.updateStockBatch(updated);
    }
    await loadInventory();
    onLocalChange?.call();
  }

  Future<void> deleteStockBatch(String id) async {
    final nodeId = await NodeId.get();
    final hlc = HLC.now(nodeId).pack();
    await _db.deleteStockBatch(id, hlc: hlc, nodeId: nodeId);
    await loadInventory();
    onLocalChange?.call();
  }

  Future<void> deductStock(String itemId, int qty, {String? nodeId}) async {
    if (_pendingDeductions.contains(itemId)) return;
    _pendingDeductions.add(itemId);
    try {
      final effectiveNodeId = nodeId ?? await NodeId.get();
      final hlc = HLC.now(effectiveNodeId).pack();
      // FIFO deduction logic is implemented inside DatabaseHelper.deductStock
      await _db.deductStock(itemId, qty, hlc: hlc, nodeId: effectiveNodeId);
      await loadInventory();
      onLocalChange?.call();
    } finally {
      _pendingDeductions.remove(itemId);
    }
  }

  /// Resolves a supply ID or a legacy name to a display string like "Alcohol (College Clinic)"
  String getFormattedSupplyName(String idOrName) {
    try {
      final item = _allItems.firstWhere((i) => i.id == idOrName);
      if (item.clinic.isEmpty) return item.itemName;
      return "${item.itemName} - ${item.clinic}";
    } catch (_) {
      // If not found by ID, it might be a legacy itemName string or newly deleted item
      return idOrName;
    }
  }

  Future<void> deleteItem(String id) async {
    final nodeId = await NodeId.get();
    final hlc = HLC.now(nodeId).pack();
    await _db.deleteInventoryItemSoft(id, hlc: hlc, nodeId: nodeId);
    await loadInventory();
    onLocalChange?.call();
  }

  // ── Inventory Export ──────────────────────────────────────────────

  Future<List<int>> getAvailableYears() async {
    return await _db.getInventoryYears();
  }

  Future<String?> exportInventoryReport(List<int> selectedYears) async {
    if (selectedYears.isEmpty) return null;

    _loading = true;
    notifyListeners();

    try {
      final allItems = await _db.getAllInventoryItems();
      final allVisitations = await _db.getAllVisitationsForReport();

      final excel = Excel.createExcel();

      final clinics = ['Clinic A', 'Clinic B', 'Clinic C'];

      for (final clinic in clinics) {
        final sheet = excel[clinic];
        final clinicItems = allItems.where((i) => i.clinic == clinic).toList();

        // Header
        // Row 0: Month Names (Merged)
        // Row 1: "Supply Item", "Type", and then "Quantity" repeated for each month

        sheet.appendRow([TextCellValue('Inventory Monthly Report - $clinic')]);
        sheet.appendRow([
          TextCellValue(
            'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
          ),
        ]);
        sheet.appendRow([]); // Spacer

        // Build columns for each month in selected years
        List<CellValue> row3 = [
          TextCellValue('Supply Item'),
          TextCellValue('Type'),
        ];
        List<CellValue> row2 = [TextCellValue(''), TextCellValue('')];

        int colOffset = 2;
        for (final year in selectedYears) {
          for (int m = 1; m <= 12; m++) {
            final monthName = DateFormat('MMMM yyyy').format(DateTime(year, m));
            row2.add(TextCellValue(monthName));
            row2.add(TextCellValue('')); // Empty for merge

            row3.add(TextCellValue('Quantity'));
            row3.add(TextCellValue('Expiry Dates'));

            // Merge month name header over Quantity and Expiry Dates
            // Row index is 3 (0-indexed: 0=title, 1=date, 2=spacer, 3=row2)
            // Column indices: colOffset and colOffset + 1
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: colOffset, rowIndex: 3),
              CellIndex.indexByColumnRow(
                columnIndex: colOffset + 1,
                rowIndex: 3,
              ),
            );

            colOffset += 2;
          }
        }

        sheet.appendRow(row2);
        sheet.appendRow(row3);

        // Data Rows
        for (final item in clinicItems) {
          List<CellValue> dataRow = [
            TextCellValue(item.itemName),
            TextCellValue(item.itemType),
          ];

          for (final year in selectedYears) {
            for (int m = 1; m <= 12; m++) {
              final endOfMonth = DateTime(year, m + 1, 0, 23, 59, 59);

              // Calculate historical quantity and expiries
              int baseQty = 0;
              Set<String> expiries = {};
              for (final batch in item.stocks) {
                if (!batch.isDeleted && batch.createdAt.isBefore(endOfMonth)) {
                  baseQty += batch.amount;
                  if (batch.amount > 0 && batch.expiryDate != null) {
                    expiries.add(DateFormat('MMM yyyy').format(batch.expiryDate!));
                  }
                }
              }

              // 2. Deductions after endOfMonth
              int deductionsAfter = 0;
              for (final visit in allVisitations) {
                final visitDate = DateTime.parse(visit['dateTime'] as String);
                if (visitDate.isAfter(endOfMonth)) {
                  final consumedStr =
                      visit['consumedSupplies'] as String? ?? '';
                  if (consumedStr.isNotEmpty) {
                    final consumedList = consumedStr.split('|');
                    for (final s in consumedList) {
                      final id = s.contains(':') ? s.split(':')[0] : s;
                      if (id == item.id) {
                        deductionsAfter++;
                      }
                    }
                  }
                }
              }

              final finalQty = baseQty + deductionsAfter;
              dataRow.add(TextCellValue('$finalQty ${item.itemType}'));
              dataRow.add(TextCellValue(expiries.join(', ')));
            }
          }
          sheet.appendRow(dataRow);
        }
      }

      // Remove default empty sheet
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Save file
      final fileBytes = excel.save();
      if (fileBytes == null) return null;

      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Save Inventory Report',
        fileName:
            'Inventory_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile != null) {
        if (!outputFile.endsWith('.xlsx')) {
          outputFile += '.xlsx';
        }
        final file = File(outputFile);
        await file.writeAsBytes(fileBytes);
        return outputFile;
      }
      return null;
    } catch (e) {
      debugPrint('Export error: $e');
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
