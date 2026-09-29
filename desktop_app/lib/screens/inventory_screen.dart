import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  final _horizontalScrollCtrl = ScrollController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = context.read<InventoryProvider>().searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadInventory();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Removed old _showAddStockDialog as it's replaced by ItemDetailDialog logic

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  void _showExportDialog() async {
    final inventory = context.read<InventoryProvider>();
    final years = await inventory.getAvailableYears();
    final List<int> selectedYears = List.from(years); // Select all by default

    if (!mounted) return;

    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Export Inventory Report'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select the years you want to include in the monthly inventory report.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (years.isEmpty)
                    const Text('No inventory data found.')
                  else
                    ...years.map((year) {
                      return CheckboxListTile(
                        title: Text(year.toString()),
                        value: selectedYears.contains(year),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedYears.add(year);
                            } else {
                              selectedYears.remove(year);
                            }
                          });
                        },
                      );
                    }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedYears.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, selectedYears),
                child: const Text('Export'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && mounted) {
      try {
        final path = await inventory.exportInventoryReport(result);
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Report exported successfully to $path'),
              backgroundColor: AppTheme.accent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to export report: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  void _showAddNewItemDialog() {
    final nameCtrl = TextEditingController();
    final lowStockCtrl = TextEditingController();
    String? selectedClinic;
    String? selectedType;
    final formKey = GlobalKey<FormState>();

    // Inline repeatable stock entries (like Past Medical History)
    final List<Map<String, dynamic>> stockEntries = [];

    final clinics = ['Clinic A', 'Clinic B', 'Clinic C'];
    final months = List.generate(12, (i) => i + 1);
    final years = List.generate(10, (i) => DateTime.now().year + i);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            child: Container(
              width: 600,
              constraints: const BoxConstraints(maxHeight: 700),
              padding: const EdgeInsets.all(28),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: AppTheme.accentGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.post_add_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'New Supply Item',
                            style: Theme.of(ctx).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Fields with asterisks (*) are required to be filled up.",
                        style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          label: Text.rich(
                            TextSpan(
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w400,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Supply Name ',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                TextSpan(
                                  text: '*',
                                  style: TextStyle(color: AppTheme.danger),
                                ),
                              ],
                            ),
                          ),
                          prefixIcon: const Icon(
                            Icons.medical_services_outlined,
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: lowStockCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Low Stock At',
                                prefixIcon: Icon(Icons.warning_amber_rounded),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedType,
                              decoration: InputDecoration(
                                label: Text.rich(
                                  TextSpan(
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w400,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Item Type ',
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '*',
                                        style: TextStyle(
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                prefixIcon: const Icon(Icons.category_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'piece',
                                  child: Text('Piece'),
                                ),
                                DropdownMenuItem(
                                  value: 'bottle',
                                  child: Text('Bottle'),
                                ),
                                DropdownMenuItem(
                                  value: 'roll',
                                  child: Text('Roll'),
                                ),
                                DropdownMenuItem(
                                  value: 'box',
                                  child: Text('Box'),
                                ),
                                DropdownMenuItem(
                                  value: 'pack',
                                  child: Text('Pack'),
                                ),
                                DropdownMenuItem(
                                  value: 'pair',
                                  child: Text('Pair'),
                                ),
                                DropdownMenuItem(
                                  value: 'set',
                                  child: Text('Set'),
                                ),
                              ],
                              validator: (v) => v == null ? 'Required' : null,
                              onChanged: (v) {
                                if (v != null) setState(() => selectedType = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedClinic,
                        decoration: InputDecoration(
                          label: Text.rich(
                            TextSpan(
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w400,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Clinic Location ',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                TextSpan(
                                  text: '*',
                                  style: TextStyle(color: AppTheme.danger),
                                ),
                              ],
                            ),
                          ),
                          prefixIcon: const Icon(Icons.location_on_outlined),
                        ),
                        items: clinics.map((c) {
                          return DropdownMenuItem(value: c, child: Text(c));
                        }).toList(),
                        validator: (v) => v == null ? 'Required' : null,
                        onChanged: (v) {
                          if (v != null) setState(() => selectedClinic = v);
                        },
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      // Stock Batches section (like Past Medical History)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Stock Batches (Optional)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                stockEntries.insert(0, {
                                  'amount': '',
                                  'month': null,
                                  'year': null,
                                });
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.accent,
                              side: BorderSide(color: AppTheme.accent),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text(
                              'Add Stock',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (stockEntries.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.cardLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: const Center(
                            child: Text(
                              'No stocks added yet. Click "Add Stock" to start.',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: Column(
                            children: List.generate(stockEntries.length, (
                              index,
                            ) {
                              final entry = stockEntries[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 80,
                                      child: TextFormField(
                                        initialValue:
                                            entry['amount']?.toString() ?? '',
                                        decoration: const InputDecoration(
                                          labelText: 'Qty',
                                          isDense: true,
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        onChanged: (val) =>
                                            entry['amount'] = val,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: entry['month'] as int?,
                                        decoration: const InputDecoration(
                                          labelText: 'Month',
                                          isDense: true,
                                        ),
                                        items: [
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text('None'),
                                          ),
                                          ...months.map(
                                            (m) => DropdownMenuItem(
                                              value: m,
                                              child: Text(_monthNames[m - 1]),
                                            ),
                                          ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => entry['month'] = v),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: entry['year'] as int?,
                                        decoration: const InputDecoration(
                                          labelText: 'Year',
                                          isDense: true,
                                        ),
                                        items: [
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text('None'),
                                          ),
                                          ...years.map(
                                            (y) => DropdownMenuItem(
                                              value: y,
                                              child: Text(y.toString()),
                                            ),
                                          ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => entry['year'] = v),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(
                                        () => stockEntries.removeAt(index),
                                      ),
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: AppTheme.danger,
                                        size: 20,
                                      ),
                                      splashRadius: 18,
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
                                // Parse stock entries
                                final stocks =
                                    <({int amount, DateTime? expiry})>[];
                                for (final entry in stockEntries) {
                                  final amt =
                                      int.tryParse(
                                        entry['amount']?.toString() ?? '',
                                      ) ??
                                      0;
                                  if (amt <= 0) continue;
                                  DateTime? expiry;
                                  final m = entry['month'] as int?;
                                  final y = entry['year'] as int?;
                                  if (m != null && y != null) {
                                    expiry = DateTime(y, m);
                                  }
                                  stocks.add((amount: amt, expiry: expiry));
                                }

                                context
                                    .read<InventoryProvider>()
                                    .addNewSupplyItem(
                                      itemName: nameCtrl.text.trim(),
                                      lowStockAmount:
                                          int.tryParse(lowStockCtrl.text) ?? 0,
                                      clinic: selectedClinic!,
                                      itemType: selectedType!,
                                      initialStocks: stocks,
                                    );
                                Navigator.pop(ctx);
                              }
                            },
                            child: const Text('Create Item'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showItemDetailDialog(InventoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          final currentItem = provider.allItems.firstWhere(
            (i) => i.id == item.id,
            orElse: () => item,
          );

          return Dialog(
            child: Container(
              width: 700,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentItem.itemName,
                            style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${currentItem.itemType} • ${currentItem.clinic}',
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Total Stock',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              currentItem.quantity.toString(),
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Stock Batches (FIFO)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  if (currentItem.stocks.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          'No stocks available.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: currentItem.stocks.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final batch = currentItem.stocks[index];
                            final isExpiring =
                                batch.expiryDate != null &&
                                batch.expiryDate!
                                        .difference(DateTime.now())
                                        .inDays <=
                                    90;

                            return ListTile(
                              leading: Icon(
                                Icons.inventory_2_outlined,
                                color: isExpiring
                                    ? AppTheme.danger
                                    : AppTheme.textMuted,
                              ),
                              title: Text('Amount: ${batch.amount}'),
                              subtitle: Text(
                                batch.expiryDate == null
                                    ? 'No Expiry'
                                    : 'Expires: ${batch.expiryDate!.month}/${batch.expiryDate!.year}',
                                style: TextStyle(
                                  color: isExpiring ? AppTheme.danger : null,
                                  fontWeight: isExpiring ? FontWeight.bold : null,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () {
                                  _showAddStockBatchDialog(currentItem, batch: batch);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          _showAddStockBatchDialog(currentItem);
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Stock'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          _showRemoveDialog(currentItem);
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Remove Stock'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {
                          _showEditItemDialog(currentItem);
                        },
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Edit Item'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.textSecondary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          _showDeleteConfirmationDialog(currentItem);
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  void _showAddStockBatchDialog(InventoryItem item, {StockBatch? batch}) {
    final qtyCtrl = TextEditingController(text: batch?.amount.toString() ?? '');
    int? selectedMonth = batch?.expiryDate?.month;
    int? selectedYear = batch?.expiryDate?.year;

    final months = List.generate(12, (i) => i + 1);
    final years = List.generate(10, (i) => DateTime.now().year + i);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    batch == null ? 'Add Stock' : 'Edit Stock',
                    style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Expiry Month',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...months.map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(_monthNames[m - 1]),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedMonth = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedYear,
                    decoration: const InputDecoration(
                      labelText: 'Expiry Year',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...years.map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text(y.toString()),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedYear = v),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final qty = int.tryParse(qtyCtrl.text) ?? 0;
                          if (qty <= 0) return;

                          DateTime? expiry;
                          if (selectedYear != null && selectedMonth != null) {
                            expiry = DateTime(selectedYear!, selectedMonth!);
                          }

                          if (batch == null) {
                            context.read<InventoryProvider>().addStockBatch(
                              itemId: item.id,
                              amount: qty,
                              expiryDate: expiry,
                            );
                          } else {
                            context.read<InventoryProvider>().updateStockBatch(
                              batch.copyWith(amount: qty, expiryDate: expiry),
                            );
                          }
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          batch == null ? 'Add Stock' : 'Save Changes',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditItemDialog(InventoryItem item) {
    final nameCtrl = TextEditingController(text: item.itemName);
    final lowStockCtrl = TextEditingController(
      text: item.lowStockAmount.toString(),
    );
    String selectedClinic = item.clinic;
    String selectedType = item.itemType;
    final formKey = GlobalKey<FormState>();

    final clinics = ['Clinic A', 'Clinic B', 'Clinic C'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(28),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit Item',
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Supply Name *',
                        prefixIcon: Icon(Icons.medical_services_outlined),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: lowStockCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Low Stock At',
                        prefixIcon: Icon(Icons.warning_amber_rounded),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedClinic,
                      decoration: const InputDecoration(
                        labelText: 'Clinic Location *',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      items: clinics
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => selectedClinic = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Item Type *',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'piece', child: Text('Piece')),
                        DropdownMenuItem(
                          value: 'bottle',
                          child: Text('Bottle'),
                        ),
                        DropdownMenuItem(value: 'roll', child: Text('Roll')),
                        DropdownMenuItem(value: 'box', child: Text('Box')),
                        DropdownMenuItem(value: 'pack', child: Text('Pack')),
                        DropdownMenuItem(value: 'pair', child: Text('Pair')),
                        DropdownMenuItem(value: 'set', child: Text('Set')),
                      ],
                      onChanged: (v) => setState(() => selectedType = v!),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (formKey.currentState!.validate()) {
                              final updated = item.copyWith(
                                itemName: nameCtrl.text.trim(),
                                lowStockAmount:
                                    int.tryParse(lowStockCtrl.text) ?? 0,
                                clinic: selectedClinic,
                                itemType: selectedType,
                              );
                              context
                                  .read<InventoryProvider>()
                                  .updateInventoryItem(updated);
                              Navigator.pop(ctx);
                            }
                          },
                          child: const Text('Update Item'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRemoveDialog(InventoryItem item) {
    final qtyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remove Stock',
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text('How many units of ${item.itemName} to remove?'),
              const SizedBox(height: 8),
              Text(
                'Current stock: ${item.quantity}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quantity to remove *',
                  prefixIcon: Icon(Icons.remove_circle_outline),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final qty = int.tryParse(qtyCtrl.text) ?? 0;
                      if (qty <= 0) return;
                      context.read<InventoryProvider>().deductStock(
                        item.id,
                        qty,
                      );
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmationDialog(InventoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Supply'),
        content: Text(
          'Are you sure you want to permanently delete "${item.itemName}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<InventoryProvider>().deleteItem(item.id);
              Navigator.pop(ctx); // Close confirmation dialog
              Navigator.pop(context); // Close detail dialog behind it
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Removed old _showEditItemDialog, _showRemoveDialog, _showDeleteConfirmationDialog
  // as they are moved to ItemDetailDialog logic.

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, inventory, _) {
        final filteredItems = inventory.items;
        final currentPage = inventory.currentPage;
        final totalPages = inventory.totalPages;
        final pageSize = inventory.pageSize;
        final totalItems = inventory.totalItems;

        final start = currentPage * pageSize;
        final end = (start + filteredItems.length);

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inventory',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 4),
              Text(
                inventory.searchQuery.isNotEmpty
                    ? '$totalItems search results'
                    : '$totalItems total items',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),

              // Search & Add Row
              Row(
                children: [
                  SizedBox(
                    width: 400,
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocusNode,
                      onChanged: (v) => inventory.setSearchQuery(v),
                      decoration: InputDecoration(
                        hintText: 'Search supplies...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: inventory.searchQuery.isNotEmpty
                            ? Tooltip(
                                message: 'Clear search',
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    inventory.setSearchQuery('');
                                  },
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _showAddNewItemDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add New Item'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.accent),
                      ),
                      padding: const EdgeInsets.all(16),
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final syncProvider = context.read<SyncProvider>();
                      final isOffline = syncProvider.currentMode == 0;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isOffline
                                ? 'Refreshing local data...'
                                : 'Reloading and syncing...',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                      await context.read<InventoryProvider>().loadInventory();
                      if (context.mounted) {
                        syncProvider.forceSync();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.accent),
                      ),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Reload'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _showExportDialog,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.accent),
                      ),
                    ),
                    icon: const Icon(Icons.file_download_rounded, size: 18),
                    label: const Text('Export'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Inventory table
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: inventory.loading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredItems.isEmpty
                      ? const Center(child: Text('No supplies found'))
                      : Scrollbar(
                          controller: _horizontalScrollCtrl,
                          thumbVisibility: true,
                          notificationPredicate: (notification) =>
                              notification.depth == 1,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  controller: _horizontalScrollCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: DataTable(
                                      showCheckboxColumn: false,
                                      sortColumnIndex:
                                          inventory.sortColumnIndex,
                                      sortAscending: inventory.sortAscending,
                                      headingRowColor: WidgetStateProperty.all(
                                        AppTheme.cardLight,
                                      ),
                                      columns: [
                                        DataColumn(
                                          label: const Tooltip(
                                            message: 'Supply Item Name',
                                            child: Text('Supply Item'),
                                          ),
                                          onSort: (idx, asc) =>
                                              _onSort(idx, asc),
                                        ),
                                        DataColumn(
                                          label: const Tooltip(
                                            message: 'Current Stock Level',
                                            child: Text('In Stock'),
                                          ),
                                          numeric: true,
                                          onSort: (idx, asc) =>
                                              _onSort(idx, asc),
                                        ),
                                        DataColumn(
                                          label: const Tooltip(
                                            message: 'Location of the clinic',
                                            child: Text('Clinic'),
                                          ),
                                          onSort: (idx, asc) =>
                                              _onSort(idx, asc),
                                        ),
                                        DataColumn(
                                          label: const Tooltip(
                                            message: 'Type of supply item',
                                            child: Text('Type'),
                                          ),
                                          onSort: (idx, asc) =>
                                              _onSort(idx, asc),
                                        ),
                                        DataColumn(
                                          label: const Tooltip(
                                            message: 'Low Stock Threshold',
                                            child: Text('Low Stock At'),
                                          ),
                                          numeric: true,
                                          onSort: (idx, asc) =>
                                              _onSort(idx, asc),
                                        ),
                                        DataColumn(
                                          label: const Tooltip(
                                            message: 'Inventory Status',
                                            child: Text('Status'),
                                          ),
                                          onSort: (idx, asc) =>
                                              _onSort(idx, asc),
                                        ),
                                      ],
                                      rows: filteredItems.map((item) {
                                        final isLow = item.isLowStock;
                                        return DataRow(
                                          onSelectChanged: (selected) {
                                            if (selected != null && selected) {
                                              _showItemDetailDialog(item);
                                            }
                                          },
                                          cells: [
                                            DataCell(
                                              Text(
                                                item.itemName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(item.quantity.toString()),
                                            ),
                                            DataCell(Text(item.clinic)),
                                            DataCell(Text(item.itemType)),
                                            DataCell(
                                              Text(
                                                item.lowStockAmount.toString(),
                                              ),
                                            ),
                                            DataCell(
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isLow
                                                      ? AppTheme.danger
                                                            .withValues(
                                                              alpha: 0.1,
                                                            )
                                                      : Colors.green.withValues(
                                                          alpha: 0.1,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  isLow
                                                      ? 'LOW STOCK'
                                                      : 'HEALTHY',
                                                  style: TextStyle(
                                                    color: isLow
                                                        ? AppTheme.danger
                                                        : Colors.green,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ),
              if (totalPages > 1) ...[
                const SizedBox(height: 16),
                _buildPagination(inventory, totalItems, totalPages, start, end),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPagination(
    InventoryProvider provider,
    int totalItems,
    int totalPages,
    int start,
    int end,
  ) {
    final currentPage = provider.currentPage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${start + 1}–$end of $totalItems items',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                onPressed: currentPage > 0 ? () => provider.firstPage() : null,
                icon: const Icon(Icons.first_page_rounded, size: 20),
                tooltip: 'First page',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage > 0
                    ? () => provider.previousPage()
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                tooltip: 'Previous',
                splashRadius: 18,
              ),
              const SizedBox(width: 8),
              Container(
                width: 64,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${currentPage + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: currentPage < totalPages - 1
                    ? () => provider.nextPage()
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: 'Next',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage < totalPages - 1
                    ? () => provider.lastPage()
                    : null,
                icon: const Icon(Icons.last_page_rounded, size: 20),
                tooltip: 'Last page',
                splashRadius: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onSort(int columnIndex, bool ascending) {
    context.read<InventoryProvider>().setSort(columnIndex, ascending);
  }
}
