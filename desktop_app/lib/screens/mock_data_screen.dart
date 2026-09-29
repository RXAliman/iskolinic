import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../providers/patient_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/custom_symptom_provider.dart';
import '../services/mock_data_service.dart';
import '../services/database_helper.dart';
import '../theme/app_theme.dart';
import '../models/patient.dart';
import '../constants/app_config.dart';

class DevToolsScreen extends StatefulWidget {
  const DevToolsScreen({super.key});

  @override
  State<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends State<DevToolsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await DatabaseHelper.instance.getMockDataStats();
    if (mounted) {
      setState(() {
        _stats = stats;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Tools'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt), text: 'Patients'),
            Tab(icon: Icon(Icons.medical_services), text: 'Visitations'),
            Tab(icon: Icon(Icons.inventory), text: 'Inventory'),
            Tab(icon: Icon(Icons.analytics), text: 'Overview'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MockPatientTab(onRefreshStats: _loadStats),
          _MockVisitationTab(onRefreshStats: _loadStats),
          _MockInventoryTab(onRefreshStats: _loadStats),
          _DataOverviewTab(stats: _stats, onRefreshStats: _loadStats),
        ],
      ),
    );
  }
}

class _MockPatientTab extends StatefulWidget {
  final VoidCallback onRefreshStats;
  const _MockPatientTab({required this.onRefreshStats});

  @override
  State<_MockPatientTab> createState() => _MockPatientTabState();
}

class _MockPatientTabState extends State<_MockPatientTab> {
  int _bulkCount = 10;
  int? _selectedYearsAgo;
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bulk Generate Patients',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedYearsAgo,
                    decoration: const InputDecoration(
                      labelText: 'Target Creation Time',
                      prefixIcon: Icon(Icons.history_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Current Year (Today)'),
                      ),
                      ...List.generate(10, (i) => i + 1).map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text('$y year${y > 1 ? 's' : ''} ago'),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedYearsAgo = val),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            tickMarkShape: const RoundSliderTickMarkShape(
                              tickMarkRadius: 2.0,
                            ),
                            activeTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.5,
                            ),
                            inactiveTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: _bulkCount.toDouble(),
                            min: 1,
                            max: 100,
                            divisions: 20, // 5 per dot
                            label: _bulkCount.toString(),
                            onChanged: (val) =>
                                setState(() => _bulkCount = val.toInt()),
                          ),
                        ),
                      ),
                      Text(
                        'Count: $_bulkCount',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generate,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(
                        _isGenerating
                            ? 'Generating...'
                            : 'Generate $_bulkCount Patients',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Mock Patients Management',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          // We could add a list here, but let's keep it simple for now as per plan
          // A "Delete All Mock Patients" button is more important
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmNuke(context),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete All Mock Data (Safe)'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isGenerating = true);
    final provider = context.read<PatientProvider>();
    int? targetYear;
    if (_selectedYearsAgo != null) {
      targetYear = DateTime.now().year - _selectedYearsAgo!;
    }

    await MockDataService.bulkGeneratePatients(
      provider,
      _bulkCount,
      year: targetYear,
    );
    widget.onRefreshStats();
    if (mounted) {
      setState(() => _isGenerating = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Generated $_bulkCount mock patients')),
      );
    }
  }

  Future<void> _confirmNuke(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final patientProvider = context.read<PatientProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final customSymptomProvider = context.read<CustomSymptomProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuke Mock Data?'),
        content: const Text(
          'This will delete all patients, visitations, and inventory items marked with the MOCK_NODE nodeId. This is safe and will not touch real data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Nuke It'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.nukeMockData();
      widget.onRefreshStats();
      if (mounted) {
        patientProvider.refreshAll();
        inventoryProvider.loadInventory();
        customSymptomProvider.loadSymptoms();
        messenger.showSnackBar(
          const SnackBar(content: Text('All mock data has been purged.')),
        );
      }
    }
  }
}

class _MockVisitationTab extends StatefulWidget {
  final VoidCallback onRefreshStats;
  const _MockVisitationTab({required this.onRefreshStats});

  @override
  State<_MockVisitationTab> createState() => _MockVisitationTabState();
}

class _MockVisitationTabState extends State<_MockVisitationTab> {
  int _bulkCount = 5;
  int _daysBack = 30;
  int _patientSubsetCount = 5;
  bool _isGenerating = false;
  bool _targetAll = false;
  int _customSymptomsPerGroup = 5;
  bool _isGeneratingCustomSymptoms = false;

  @override
  Widget build(BuildContext context) {
    final patientProvider = context.watch<PatientProvider>();
    final mockPatientsCount = patientProvider.allPatientsCount;
    // We'll fetch the actual list in the generate method to avoid heavy UI rebuilds
    // with thousands of mock patients.

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Generate Mock Visits',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  RadioGroup<bool>(
                    groupValue: _targetAll,
                    onChanged: (v) => setState(() => _targetAll = v!),
                    child: Row(
                      children: const [
                        Radio<bool>(value: false),
                        Text('Random Subset'),
                        SizedBox(width: 24),
                        Radio<bool>(value: true),
                        Text('All Mock Patients'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_targetAll) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              tickMarkShape: const RoundSliderTickMarkShape(
                                tickMarkRadius: 2.0,
                              ),
                              activeTickMarkColor: AppTheme.accent.withValues(
                                alpha: 0.5,
                              ),
                              inactiveTickMarkColor: AppTheme.accent.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            child: Slider(
                              value: _patientSubsetCount
                                  .clamp(
                                    1,
                                    mockPatientsCount == 0
                                        ? 1
                                        : mockPatientsCount,
                                  )
                                  .toDouble(),
                              min: 1,
                              max: mockPatientsCount == 0
                                  ? 1
                                  : mockPatientsCount.toDouble(),
                              divisions: mockPatientsCount == 0
                                  ? 1
                                  : (mockPatientsCount > 1
                                        ? (mockPatientsCount > 20
                                              ? 10
                                              : mockPatientsCount - 1)
                                        : 1),
                              label: _patientSubsetCount.toString(),
                              onChanged: mockPatientsCount == 0
                                  ? null
                                  : (val) => setState(
                                      () => _patientSubsetCount = val.toInt(),
                                    ),
                            ),
                          ),
                        ),
                        Text(
                          'Target Patients: $_patientSubsetCount',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            tickMarkShape: const RoundSliderTickMarkShape(
                              tickMarkRadius: 2.0,
                            ),
                            activeTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.5,
                            ),
                            inactiveTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: _bulkCount.toDouble(),
                            min: 1,
                            max: 50,
                            divisions: 10,
                            label: _bulkCount.toString(),
                            onChanged: (val) =>
                                setState(() => _bulkCount = val.toInt()),
                          ),
                        ),
                      ),
                      Text(
                        'Visits: $_bulkCount',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            tickMarkShape: const RoundSliderTickMarkShape(
                              tickMarkRadius: 2.0,
                            ),
                            activeTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.5,
                            ),
                            inactiveTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: _daysBack.toDouble(),
                            min: 0,
                            max: 365,
                            divisions: 12, // Monthly dots
                            label: _daysBack.toString(),
                            onChanged: (val) =>
                                setState(() => _daysBack = val.toInt()),
                          ),
                        ),
                      ),
                      Text(
                        'Spread: $_daysBack days',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_isGenerating || mockPatientsCount == 0)
                          ? null
                          : _generate,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.history_edu),
                      label: Text(
                        _isGenerating
                            ? 'Generating...'
                            : _targetAll
                            ? 'Generate $_bulkCount Visits for All'
                            : 'Generate $_bulkCount Visits for $_patientSubsetCount Patients',
                      ),
                    ),
                  ),
                  if (mockPatientsCount == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'No mock patients found. Generate patients first.',
                        style: TextStyle(color: AppTheme.danger, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Generate Custom Symptoms',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            tickMarkShape: const RoundSliderTickMarkShape(
                              tickMarkRadius: 2.0,
                            ),
                            activeTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.5,
                            ),
                            inactiveTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: _customSymptomsPerGroup.toDouble(),
                            min: 1,
                            max: 50,
                            divisions: 49,
                            label: _customSymptomsPerGroup.toString(),
                            onChanged: (val) => setState(() =>
                                _customSymptomsPerGroup = val.toInt()),
                          ),
                        ),
                      ),
                      Text(
                        'Count per Group: $_customSymptomsPerGroup',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingCustomSymptoms
                          ? null
                          : _generateCustomSymptoms,
                      icon: _isGeneratingCustomSymptoms
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.healing),
                      label: Text(
                        _isGeneratingCustomSymptoms
                            ? 'Generating...'
                            : 'Generate $_customSymptomsPerGroup Symptoms per Group',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateCustomSymptoms() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isGeneratingCustomSymptoms = true);
    
    try {
      final provider = context.read<CustomSymptomProvider>();
      await MockDataService.bulkGenerateCustomSymptoms(
        provider,
        _customSymptomsPerGroup,
      );
      
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Generated $_customSymptomsPerGroup custom symptoms for each group (traumatic, medical, behavioral).',
          ),
        ),
      );
      widget.onRefreshStats();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to generate custom symptoms: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCustomSymptoms = false);
      }
    }
  }

  Future<void> _generate() async {
    final provider = context.read<PatientProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isGenerating = true);

    try {
      final mockPatients = await DatabaseHelper.instance.getMockPatients();

      if (mockPatients.isEmpty) return;

      List<Patient> targets;
      if (_targetAll) {
        targets = mockPatients;
      } else {
        // Pick a random subset
        final shuffled = List<Patient>.from(mockPatients)..shuffle();
        targets = shuffled.take(_patientSubsetCount).toList();
      }

      await MockDataService.bulkGenerateVisitsForMultiplePatients(
        provider,
        targets.map((p) => p.id).toList(),
        _bulkCount,
        daysBack: _daysBack,
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Generated $_bulkCount visits for each of ${targets.length} mock patients.',
          ),
        ),
      );
      widget.onRefreshStats();
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }
}

class _MockInventoryTab extends StatefulWidget {
  final VoidCallback onRefreshStats;
  const _MockInventoryTab({required this.onRefreshStats});

  @override
  State<_MockInventoryTab> createState() => _MockInventoryTabState();
}

class _MockInventoryTabState extends State<_MockInventoryTab> {
  bool _isSeeding = false;
  int _targetCount = 5;
  int _seedCount = 10;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory Utilities',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            tickMarkShape: const RoundSliderTickMarkShape(
                              tickMarkRadius: 2.0,
                            ),
                            activeTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.5,
                            ),
                            inactiveTickMarkColor: AppTheme.accent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: _seedCount.toDouble(),
                            min: 1,
                            max: 100,
                            divisions: 99,
                            label: _seedCount.toString(),
                            onChanged: (val) =>
                                setState(() => _seedCount = val.toInt()),
                          ),
                        ),
                      ),
                      Text(
                        'Items per Clinic: $_seedCount',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSeeding ? null : _seedDefaults,
                      icon: _isSeeding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.inventory_2),
                      label: Text(
                        _isSeeding
                            ? 'Seeding...'
                            : 'Seed $_seedCount Clinic Supplies per Clinic Group',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Adds supplies with initial stocks to all clinic groups (Clinic A & Clinic B).',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Bulk Stock Actions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    tickMarkShape: const RoundSliderTickMarkShape(
                      tickMarkRadius: 2.0,
                    ),
                    activeTickMarkColor: AppTheme.accent.withValues(alpha: 0.5),
                    inactiveTickMarkColor: AppTheme.accent.withValues(
                      alpha: 0.2,
                    ),
                  ),
                  child: Slider(
                    value: _targetCount.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: _targetCount.toString(),
                    onChanged: (val) =>
                        setState(() => _targetCount = val.toInt()),
                  ),
                ),
              ),
              Text(
                'Target Items: $_targetCount',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _bulkUpdateStock(mode: 'low'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: Text('Set $_targetCount to LOW'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _bulkUpdateStock(mode: 'healthy'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: Text('Set $_targetCount to HEALTHY'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _bulkUpdateStock(mode: 'expiring'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  child: Text('Set $_targetCount to EXPIRING'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Temporal Data Management',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.blue.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _randomizeDates,
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Randomize All CreatedAt Dates'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Randomly shifts createdAt of all mock inventory, batches, and visits within the last 10 years. Use this to test reporting.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _randomizeDates() async {
    final messenger = ScaffoldMessenger.of(context);
    await DatabaseHelper.instance.randomizeInventoryDates();
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('All mock data dates have been randomized.'),
        ),
      );
    }
    widget.onRefreshStats();
  }

  Future<void> _seedDefaults() async {
    setState(() => _isSeeding = true);
    final provider = context.read<InventoryProvider>();
    await MockDataService.seedCustomInventory(provider, _seedCount);
    widget.onRefreshStats();
    if (mounted) {
      setState(() => _isSeeding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_seedCount inventory items seeded per clinic group.')),
      );
    }
  }

  Future<void> _bulkUpdateStock({required String mode}) async {
    final provider = context.read<InventoryProvider>();
    final mockItems = provider.allItems
        .where((i) => i.nodeId == MockDataService.mockNodeId)
        .toList();

    if (mockItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mock items found to update.')),
      );
      return;
    }

    mockItems.shuffle();
    final targets = mockItems.take(_targetCount).toList();

    int count = 0;
    for (final item in targets) {
      if (mode == 'expiring') {
        // To make it expiring, we add a batch with an expiry date randomized within the 3-month threshold
        final randomDays = Random().nextInt(70) + 10; // 10 to 80 days from now
        await provider.addStockBatch(
          itemId: item.id,
          amount: 5,
          expiryDate: DateTime.now().add(Duration(days: randomDays)),
          nodeId: MockDataService.mockNodeId,
        );
        count++;
        continue;
      }

      final low = mode == 'low';
      final target = low ? item.lowStockAmount - 1 : item.lowStockAmount * 3;
      final current = item.quantity;
      final diff = target - current;

      if (diff > 0) {
        await provider.addStockBatch(
          itemId: item.id,
          amount: diff,
          nodeId: MockDataService.mockNodeId,
        );
        count++;
      } else if (diff < 0) {
        await provider.deductStock(
          item.id,
          diff.abs(),
          nodeId: MockDataService.mockNodeId,
        );
        count++;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated stock for $count mock items.')),
      );
    }
    widget.onRefreshStats();
  }
}

class _DataOverviewTab extends StatelessWidget {
  final Map<String, int> stats;
  final VoidCallback onRefreshStats;
  const _DataOverviewTab({required this.stats, required this.onRefreshStats});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Database Statistics',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                onPressed: onRefreshStats,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statCard(
                'Active Patients',
                stats['totalActivePatients'] ?? 0,
                Icons.person,
              ),
              _statCard(
                'Mock Patients',
                stats['patients'] ?? 0,
                Icons.bug_report,
                color: Colors.orange,
              ),
              _statCard(
                'Active Visits',
                stats['totalActiveVisitations'] ?? 0,
                Icons.history,
              ),
              _statCard(
                'Mock Visits',
                stats['visitations'] ?? 0,
                Icons.bug_report,
                color: Colors.orange,
              ),
              _statCard(
                'Mock Items',
                stats['inventory'] ?? 0,
                Icons.inventory,
                color: Colors.orange,
              ),
              _statCard(
                'Mock Batches',
                stats['stocks'] ?? 0,
                Icons.layers,
                color: Colors.orange,
              ),
              _statCard(
                'Mock Custom Symptoms',
                stats['customSymptoms'] ?? 0,
                Icons.healing,
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Dangerous Actions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            color: AppTheme.danger.withValues(alpha: 0.05),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.file_download,
                    color: AppTheme.accent,
                  ),
                  title: const Text('Export Database Snapshot'),
                  subtitle: const Text('Copies clinic.db to your Desktop'),
                  onTap: () => _exportDb(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.delete_sweep,
                    color: AppTheme.danger,
                  ),
                  title: const Text('Purge All Mock Data'),
                  subtitle: const Text(
                    'Permanently deletes records with MOCK_NODE nodeId',
                  ),
                  onTap: () => _confirmNuke(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, {Color? color}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color ?? AppTheme.accent, size: 16),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.toString(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDb(BuildContext context) async {
    try {
      final dbDir = await getApplicationSupportDirectory();
      final dbFile = File(p.join(dbDir.path, AppConfig.databaseName));

      if (!await dbFile.exists()) {
        throw Exception('Database file not found at ${dbFile.path}');
      }

      final desktopDir = p.join(
        Platform.environment['USERPROFILE']!,
        'Desktop',
      );
      final targetPath = p.join(
        desktopDir,
        'IskoLinic_Snapshot_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db',
      );

      await dbFile.copy(targetPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Database exported to Desktop: ${p.basename(targetPath)}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmNuke(BuildContext context) async {
    final patientProvider = context.read<PatientProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final customSymptomProvider = context.read<CustomSymptomProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purge All Mock Data?'),
        content: const Text(
          'This will permanently delete all mock-generated patients, visitations, and inventory records. Real data will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Purge'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.nukeMockData();
      onRefreshStats();
      if (context.mounted) {
        patientProvider.refreshAll();
        inventoryProvider.loadInventory();
        customSymptomProvider.loadSymptoms();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mock data purged successfully.')),
        );
      }
    }
  }
}
