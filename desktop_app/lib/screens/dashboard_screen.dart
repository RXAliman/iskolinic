import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/visitation.dart';
import '../models/inventory_item.dart';
import '../providers/patient_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/local_server_provider.dart';
import '../theme/app_theme.dart';
import '../services/database_helper.dart';
import 'patient_list_screen.dart';
import 'patient_detail_screen.dart';
import 'patient_form_screen.dart';
import 'visitation_form_screen.dart';
import 'visits_screen.dart';
import 'analytics_screen.dart';
import 'inventory_screen.dart';
import 'connection_screen.dart';
import 'settings_screen.dart';
import 'mock_data_screen.dart';
import '../constants/app_config.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _focusSearchOnNextTab = false;
  String? _settingsScrollTarget;
  bool _isSidebarCollapsed = false;

  static const double _expandedWidth = 250;
  static const double _collapsedWidth = 72;
  static const Duration _animDuration = Duration(milliseconds: 250);
  static const Curve _animCurve = Curves.easeInOutCubic;
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  late final AppLifecycleListener _lifecycleListener;

  List<_NavItem> get _navItems {
    final settings = context.read<SettingsProvider>();
    return [
      _NavItem(Icons.dashboard_rounded, 'Dashboard'),
      _NavItem(Icons.people_rounded, 'Patients'),
      _NavItem(Icons.medical_services_rounded, 'Visits'),
      _NavItem(Icons.inventory_2_rounded, 'Inventory'),
      _NavItem(Icons.bar_chart_rounded, 'Analytics'),
      _NavItem(Icons.devices_rounded, 'Connect to Form App'),
      _NavItem(Icons.settings_rounded, 'Settings'),
      if (!AppConfig.isProduction && settings.isDeveloperMode)
        _NavItem(Icons.bug_report_rounded, 'Mock Data', isDev: true),
    ];
  }

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequest,
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardData();
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  Future<AppExitResponse> _handleExitRequest() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Close ISKOLINIC?'),
        content: const Text('Are you sure you want to close the application?'),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close App'),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      if (mounted) {
        // Disconnect from CRDT relay
        context.read<SyncProvider>().disconnect();

        // Stop local HTTP server
        await context.read<LocalServerProvider>().stopServer();
      }

      // Close database connection
      await DatabaseHelper.instance.close();

      return AppExitResponse.exit;
    }
    return AppExitResponse.cancel;
  }

  Future<void> _loadDashboardData() async {
    final patientProvider = context.read<PatientProvider>();
    final analyticsProvider = context.read<AnalyticsProvider>();
    final inventoryProvider = context.read<InventoryProvider>();

    await patientProvider.loadPatients();
    await analyticsProvider.loadAnalytics();
    await patientProvider.loadTodayVisits();
    await inventoryProvider.loadInventory();
  }

  Widget _buildBody() {
    final navItems = _navItems;
    // Safety check: if selected index is out of bounds (e.g. dev mode toggled off)
    if (_selectedIndex >= navItems.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _selectedIndex = 0);
      });
      return _buildDashboardHome();
    }

    switch (_selectedIndex) {
      case 0:
        return _buildDashboardHome();
      case 1:
        return PatientListScreen(autoFocusSearch: _focusSearchOnNextTab);
      case 2:
        return const VisitsScreen();
      case 3:
        return const InventoryScreen();
      case 4:
        return const AnalyticsScreen();
      case 5:
        return ConnectionScreen(
          onNavigateToSettings: () => setState(() {
            _selectedIndex = 6;
            _settingsScrollTarget = 'formAppManagement';
          }),
        );
      case 6:
        return SettingsScreen(scrollTarget: _settingsScrollTarget);
      case 7:
        return const DevToolsScreen();
      default:
        return _buildDashboardHome();
    }
  }

  Widget _buildDashboardHome() {
    return Consumer<PatientProvider>(
      builder: (context, patients, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Welcome back!',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDashboardFilters(patients),
              const SizedBox(height: 24),

              // Summary Cards
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.people_rounded,
                      label: 'Total Patients Recorded',
                      value: '${patients.dashboardTotalPatients}',
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF59E0B),
                          Color(0xFFFBBF24),
                        ], // Yellow gradient
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.calendar_today_rounded,
                      label: "Patient Visits Today",
                      value: '${patients.todayVisits}',
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF3B82F6),
                          Color(0xFF60A5FA),
                        ], // Blue gradient
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                "Quick Actions",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const PatientFormScreen(),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add Patient'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const VisitationFormScreen(),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: const Icon(Icons.medical_services_rounded, size: 18),
                    label: const Text('Add Visit'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _focusSearchOnNextTab = true;
                        _selectedIndex = 1;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Search Patients'),
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
                      await context.read<PatientProvider>().refreshAll();
                      if (context.mounted) {
                        await context.read<InventoryProvider>().loadInventory();
                      }
                      if (context.mounted) {
                        await context.read<AnalyticsProvider>().loadAnalytics();
                      }
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
                ],
              ),
              const SizedBox(height: 32),
              Text(
                "Today's Visitations",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              if (patients.dashboardVisits.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: AppTheme.glassCard(),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 48,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No visitations recorded today',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try adjusting your filters',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: AppTheme.glassCard(),
                  child: Column(
                    children: [
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: patients.dashboardVisits.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: AppTheme.dividerColor,
                        ),
                        itemBuilder: (context, index) {
                          final data = patients.dashboardVisits[index];
                          final patientName =
                              data['patientName'] as String? ?? '';
                          final firstName = data['firstName'] as String? ?? '';
                          final visit = Visitation.fromMap(data);
                          final inventoryProvider = context
                              .read<InventoryProvider>();

                          return ListTile(
                            onTap: () async {
                              final provider = context.read<PatientProvider>();
                              final patient = await DatabaseHelper.instance
                                  .getPatient(visit.patientId);
                              if (patient != null) {
                                await provider.selectPatient(patient);
                                if (context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (_) => const PatientDetailScreen(),
                                  );
                                }
                              }
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  index == 0 && patients.todayVisits == 1
                                  ? BorderRadius.circular(16)
                                  : index == 0
                                  ? BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                    )
                                  : (index ==
                                                patients.dashboardVisitPageSize -
                                                    1 &&
                                            patients.todayVisits ==
                                                patients
                                                    .dashboardVisitPageSize) ||
                                        (index == 1 &&
                                            patients.todayVisits == 2)
                                  ? BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    )
                                  : BorderRadius.zero,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: AppTheme.accentGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  firstName.isNotEmpty
                                      ? firstName[0].toUpperCase()
                                      : (patientName.isNotEmpty
                                            ? patientName[0].toUpperCase()
                                            : '?'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  patientName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  DateFormat('hh:mm a').format(visit.dateTime),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (visit.symptoms.isNotEmpty ||
                                      visit.customChiefComplaint.isNotEmpty)
                                    Text(
                                      'Symptoms: ${[...visit.symptoms, if (visit.customChiefComplaint.isNotEmpty) visit.customChiefComplaint].join(', ')}',
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (visit.treatment.isNotEmpty ||
                                      visit.suppliesUsed.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Intervention: ${[...visit.suppliesUsed.map((s) => s.contains(':') ? s.split(':')[1] : inventoryProvider.getFormattedSupplyName(s)), if (visit.treatment.isNotEmpty) visit.treatment].join(', ')}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 4),
                                    TextButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => VisitationFormScreen(
                                            patientId: visit.patientId,
                                            visitation: visit,
                                            hideChiefComplaintOptions: true,
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        'Add Missing Intervention Details',
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 0,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        alignment: Alignment.centerLeft,
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                        foregroundColor: AppTheme.danger,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (patients.totalDashboardVisitPages > 1)
                        _buildPagination(
                          patients,
                          patients.todayVisits,
                          patients.totalDashboardVisitPages,
                          patients.dashboardVisitPage *
                              patients.dashboardVisitPageSize,
                          (patients.dashboardVisitPage *
                                  patients.dashboardVisitPageSize) +
                              patients.dashboardVisits.length,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),

              // Alerts Section (Low Stock & Expiring)
              Consumer<InventoryProvider>(
                builder: (context, inventory, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Low Stock Column
                          Expanded(
                            child: _DashboardAlertSection(
                              title: "Low Stock Alerts",
                              items: inventory.lowStockItems,
                              icon: Icons.warning_amber_rounded,
                              accentColor: AppTheme.danger,
                              onTap: () => setState(() => _selectedIndex = 3),
                              subtitleBuilder: (item) =>
                                  'Current: ${item.quantity} (Low at: ${item.lowStockAmount})',
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Expiring Column
                          Expanded(
                            child: _DashboardAlertSection(
                              title: "Expiring Alerts",
                              items: inventory.expiringItems,
                              icon: Icons.timer_outlined,
                              accentColor: Colors.orange,
                              onTap: () => setState(() => _selectedIndex = 3),
                              subtitleBuilder: (item) {
                                final nearest =
                                    item.stocks
                                        .where((s) => s.expiryDate != null)
                                        .toList()
                                      ..sort(
                                        (a, b) => a.expiryDate!.compareTo(
                                          b.expiryDate!,
                                        ),
                                      );
                                if (nearest.isEmpty) {
                                  return 'No expiry date tracked';
                                }
                                final exp = nearest.first.expiryDate!;
                                return 'Earliest Expiry: ${exp.month}/${exp.year} (${nearest.first.amount} units)';
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardFilters(PatientProvider provider) {
    final List<String> grades = [
      'Pre-school',
      'Grade School',
      'Junior High School',
      'Senior High School',
      'College',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Filters:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        MenuBar(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(Colors.transparent),
            elevation: WidgetStateProperty.all(0),
          ),
          children: [
            SubmenuButton(
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                ),
                foregroundColor: WidgetStateProperty.all(AppTheme.accent),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                padding: WidgetStateProperty.all(const EdgeInsets.all(16)),
              ),
              leadingIcon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppTheme.accent,
              ),
              menuChildren: [
                ...grades.map((grade) {
                  final isSelected = provider.dashboardSelectedDepartments
                      .contains(grade);
                  return CheckboxMenuButton(
                    closeOnActivate: false,
                    value: isSelected,
                    onChanged: (val) {
                      if (val != null) {
                        provider.toggleDashboardFilter(grade, val);
                      }
                    },
                    child: Text(grade),
                  );
                }),
                if (provider.dashboardIncludeEmployee)
                  CheckboxMenuButton(
                    closeOnActivate: false,
                    value: provider.dashboardSelectedDepartments.contains(
                      'General',
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        provider.toggleDashboardFilter('General', val);
                      }
                    },
                    child: const Text('General'),
                  ),
              ],
              child: const Text('Department'),
            ),
            const SizedBox(width: 8),
            SubmenuButton(
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                ),
                foregroundColor: WidgetStateProperty.all(AppTheme.accent),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                padding: WidgetStateProperty.all(const EdgeInsets.all(16)),
              ),
              leadingIcon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppTheme.accent,
              ),
              menuChildren: [
                CheckboxMenuButton(
                  closeOnActivate: false,
                  value: provider.dashboardIncludeStudent,
                  onChanged: (val) {
                    if (val != null) {
                      provider.toggleDashboardFilter('Student', val);
                    }
                  },
                  child: const Text('Student'),
                ),
                CheckboxMenuButton(
                  closeOnActivate: false,
                  value: provider.dashboardIncludeEmployee,
                  onChanged: (val) {
                    if (val != null) {
                      provider.toggleDashboardFilter('Employee', val);
                    }
                  },
                  child: const Text('Employee'),
                ),
              ],
              child: const Text('Role'),
            ),
          ],
        ),
        const SizedBox(width: 16),
        TextButton.icon(
          onPressed: () {
            provider.clearDashboardFilters();
          },
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('Reset'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accent,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: AppTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(
    PatientProvider provider,
    int totalItems,
    int totalPages,
    int start,
    int end,
  ) {
    final currentPage = provider.dashboardVisitPage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.dividerColor, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${start + 1}–$end of $totalItems visits',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                onPressed: currentPage > 0
                    ? () => provider.firstDashboardVisitPage()
                    : null,
                icon: const Icon(Icons.first_page_rounded, size: 20),
                tooltip: 'First page',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage > 0
                    ? () => provider.prevDashboardVisitPage()
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                tooltip: 'Previous',
                splashRadius: 18,
              ),
              const SizedBox(width: 8),
              ..._buildPageNumbers(provider, totalPages),
              const SizedBox(width: 8),
              IconButton(
                onPressed: currentPage < totalPages - 1
                    ? () => provider.nextDashboardVisitPage()
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: 'Next',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage < totalPages - 1
                    ? () => provider.lastDashboardVisitPage()
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

  List<Widget> _buildPageNumbers(PatientProvider provider, int totalPages) {
    final current = provider.dashboardVisitPage;
    return [
      Container(
        width: 64,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          '${current + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();
    return Scaffold(
      body: Column(
        children: [
          // ── Top Bar ──
          Container(
            decoration: const BoxDecoration(color: AppTheme.sidebarBg),
            padding: const EdgeInsets.symmetric(vertical: 0),
            child: Row(
              children: [
                // Left: App Logo + Name (same width as sidebar)
                AnimatedContainer(
                  duration: _animDuration,
                  curve: _animCurve,
                  width: _isSidebarCollapsed ? _collapsedWidth : _expandedWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 18,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: AppTheme.dividerColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/app-icon-colored.png',
                          height: 44,
                        ),
                      ),
                      if (!_isSidebarCollapsed) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'ISKOLINIC',
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: GoogleFonts.audiowide(
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1B4697),
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Right portion: School Info + Date/Time + Sync
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        // App Info
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/app-icon-colored.png',
                            width: 36,
                            height: 36,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ISKOLINIC',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'School Health & Clinic Management',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // Date/Time
                        Text(
                          DateFormat('MMM. dd, yyyy').format(_now),
                          style: GoogleFonts.chivoMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          DateFormat('hh:mm:ss a').format(_now),
                          style: GoogleFonts.chivoMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            width: 1,
                            height: 28,
                            color: AppTheme.dividerColor,
                          ),
                        ),

                        // Sync Status
                        Consumer<SyncProvider>(
                          builder: (context, sync, _) {
                            final isConnected = sync.isConnected;
                            final isConnecting = sync.isConnecting;
                            final isSyncing = sync.isSyncing;

                            final Color bgColor;
                            final String label;
                            final IconData icon;

                            if (isSyncing && isConnected) {
                              return Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF3b82f6,
                                  ), // Using IskOlinic primary blue
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: IntrinsicWidth(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          14,
                                          6,
                                          14,
                                          4,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.cloud_sync_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Syncing',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const LinearProgressIndicator(
                                        minHeight: 2,
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            if (isConnected) {
                              bgColor = Colors.green;
                              label = 'Online';
                              icon = Icons.cloud_done_rounded;
                            } else if (isConnecting) {
                              bgColor = Colors.orange;
                              label = 'Connecting';
                              icon = Icons.cloud_sync_rounded;
                            } else {
                              bgColor = AppTheme.textMuted;
                              label = 'Offline';
                              icon = Icons.cloud_off_rounded;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Main Area: Sidebar + Content ──
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sidebar (nav only) ──
                AnimatedContainer(
                  duration: _animDuration,
                  curve: _animCurve,
                  width: _isSidebarCollapsed ? _collapsedWidth : _expandedWidth,
                  decoration: const BoxDecoration(
                    color: AppTheme.sidebarBg,
                    border: Border(
                      right: BorderSide(
                        color: AppTheme.dividerColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      // Nav Items
                      Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          final navItems = _navItems;
                          return Column(
                            children: List.generate(navItems.length, (i) {
                              final item = navItems[i];
                              final isSelected = _selectedIndex == i;

                              return Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: _isSidebarCollapsed ? 8 : 12,
                                  vertical: 2,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      _focusSearchOnNextTab = false;
                                      _selectedIndex = i;
                                      _settingsScrollTarget = null;
                                    }),
                                    borderRadius: BorderRadius.circular(12),
                                    hoverColor: AppTheme.textPrimary.withValues(
                                      alpha: 0.08,
                                    ),
                                    splashColor: AppTheme.textPrimary
                                        .withValues(alpha: 0.12),
                                    highlightColor: AppTheme.textPrimary
                                        .withValues(alpha: 0.05),
                                    child: AnimatedContainer(
                                      duration: _animDuration,
                                      curve: _animCurve,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: _isSidebarCollapsed
                                            ? 0
                                            : 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: isSelected
                                            ? AppTheme.accent.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.transparent,
                                        border: isSelected
                                            ? Border.all(
                                                color: AppTheme.accent
                                                    .withValues(alpha: 0.3),
                                              )
                                            : Border.all(
                                                color: Colors.transparent,
                                              ),
                                      ),
                                      child: _isSidebarCollapsed
                                          ? Center(
                                              child: Tooltip(
                                                message: item.label,
                                                preferBelow: false,
                                                child: Icon(
                                                  item.icon,
                                                  size: 20,
                                                  color: isSelected
                                                      ? AppTheme.accent
                                                      : AppTheme.textMuted,
                                                ),
                                              ),
                                            )
                                          : Row(
                                              children: [
                                                Icon(
                                                  item.icon,
                                                  size: 20,
                                                  color: isSelected
                                                      ? AppTheme.accent
                                                      : AppTheme.textMuted,
                                                ),
                                                const SizedBox(width: 12),
                                                Flexible(
                                                  child: Text(
                                                    item.label,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? AppTheme.accent
                                                          : AppTheme
                                                                .textSecondary,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                if (item.isDev) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.warning
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: AppTheme.warning
                                                            .withValues(
                                                              alpha: 0.4,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'DEV',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: AppTheme.warning,
                                                        letterSpacing: 1,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),

                      const Spacer(),

                      // ── Collapse / Expand Toggle ──
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => setState(
                              () => _isSidebarCollapsed = !_isSidebarCollapsed,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            hoverColor: AppTheme.textPrimary.withValues(
                              alpha: 0.08,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _isSidebarCollapsed ? 0 : 16,
                                vertical: 10,
                              ),
                              child: _isSidebarCollapsed
                                  ? Center(
                                      child: Tooltip(
                                        message: 'Expand Sidebar',
                                        preferBelow: false,
                                        child: AnimatedRotation(
                                          turns: 0,
                                          duration: _animDuration,
                                          child: const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 22,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Row(
                                      children: [
                                        AnimatedRotation(
                                          turns: 0,
                                          duration: _animDuration,
                                          child: const Icon(
                                            Icons.chevron_left_rounded,
                                            size: 22,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Flexible(
                                          child: Text(
                                            overflow: TextOverflow.clip,
                                            softWrap: false,
                                            'Collapse',
                                            style: TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Main Content ──
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final bool isDev;
  _NavItem(this.icon, this.label, {this.isDev = false});
}

class _DashboardAlertSection extends StatefulWidget {
  final String title;
  final List<InventoryItem> items;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final String Function(InventoryItem) subtitleBuilder;

  const _DashboardAlertSection({
    required this.title,
    required this.items,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    required this.subtitleBuilder,
  });

  @override
  State<_DashboardAlertSection> createState() => _DashboardAlertSectionState();
}

class _DashboardAlertSectionState extends State<_DashboardAlertSection> {
  int _currentPage = 0;
  static const int _pageSize = 3;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: AppTheme.glassCard(),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.green.shade400,
                  size: 36,
                ),
                const SizedBox(height: 8),
                Text(
                  'All clear — no alerts',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final totalPages = (widget.items.length / _pageSize).ceil();
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize) > widget.items.length
        ? widget.items.length
        : (start + _pageSize);
    final displayedItems = widget.items.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: widget.accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${widget.items.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            children: [
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayedItems.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppTheme.dividerColor),
                itemBuilder: (context, index) {
                  final item = displayedItems[index];
                  return ListTile(
                    onTap: widget.onTap,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.accentColor,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      item.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      widget.subtitleBuilder(item),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.textMuted,
                      size: 16,
                    ),
                  );
                },
              ),
              if (totalPages > 1)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _currentPage > 0
                            ? () => setState(() => _currentPage--)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_currentPage + 1} / $totalPages',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _currentPage < totalPages - 1
                            ? () => setState(() => _currentPage++)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final LinearGradient gradient;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
