import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient.dart';
import '../providers/patient_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';
import 'patient_detail_screen.dart';
import 'patient_form_screen.dart';

class PatientListScreen extends StatefulWidget {
  final bool autoFocusSearch;

  const PatientListScreen({super.key, this.autoFocusSearch = false});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final query = context.read<PatientProvider>().searchQuery;
    _searchController.text = query;
    if (widget.autoFocusSearch) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void didUpdateWidget(PatientListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoFocusSearch && !oldWidget.autoFocusSearch) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, provider, _) {
        final currentPage = provider.currentPage;
        final totalPages = provider.totalPages;
        final pageSize = provider.pageSize;
        final totalPatients = provider.totalPatients;

        final start = currentPage * pageSize;
        final end = (start + provider.patients.length);

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Patient Records',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.searchQuery.isNotEmpty
                        ? '$totalPatients search results'
                        : '$totalPatients total records',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  // Search Bar
                  SizedBox(
                    width: 400,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (query) => provider.setSearchQuery(query),
                      decoration: InputDecoration(
                        hintText: 'Search by name or ID number...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: provider.searchQuery.isNotEmpty
                            ? Tooltip(
                                message: 'Clear search',
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    provider.setSearchQuery('');
                                  },
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _showPatientForm(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add Patient'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryLight,
                      foregroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppTheme.accent),
                      ),
                      padding: const EdgeInsets.all(16),
                    ),
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
                        syncProvider.forceSync();
                      }
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Reload'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildRecordsFilters(provider),
              const SizedBox(height: 24),

              // Patient Table
              Expanded(
                child: provider.loading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.patients.isEmpty
                    ? _buildEmptyState(context)
                    : _buildPatientTable(context, provider.patients),
              ),

              // Pagination
              if (totalPages > 1) ...[
                const SizedBox(height: 16),
                _buildPagination(
                  provider,
                  totalPatients,
                  totalPages,
                  start,
                  end,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPagination(
    PatientProvider provider,
    int totalItems,
    int totalPages,
    int start,
    int end,
  ) {
    final currentPage = provider.currentPage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: AppTheme.glassCard(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${start + 1}–$end of $totalItems records',
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
              ..._buildPageNumbers(provider, totalPages),
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

  Widget _buildRecordsFilters(PatientProvider provider) {
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
          'Show only:',
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
                  final isSelected = provider.recordsSelectedDepartments
                      .contains(grade);
                  return CheckboxMenuButton(
                    closeOnActivate: false,
                    value: isSelected,
                    onChanged: (val) {
                      if (val != null) provider.toggleRecordsFilter(grade, val);
                    },
                    child: Text(grade),
                  );
                }),
                if (provider.recordsIncludeEmployee)
                  CheckboxMenuButton(
                    closeOnActivate: false,
                    value: provider.recordsSelectedDepartments.contains(
                      'General',
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        provider.toggleRecordsFilter('General', val);
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
                  value: provider.recordsIncludeStudent,
                  onChanged: (val) {
                    if (val != null) {
                      provider.toggleRecordsFilter('Student', val);
                    }
                  },
                  child: const Text('Student'),
                ),
                CheckboxMenuButton(
                  closeOnActivate: false,
                  value: provider.recordsIncludeEmployee,
                  onChanged: (val) {
                    if (val != null) {
                      provider.toggleRecordsFilter('Employee', val);
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
            _searchController.clear();
            provider.clearFilters();
          },
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('Reset Search & Filters'),
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

  List<Widget> _buildPageNumbers(PatientProvider provider, int totalPages) {
    final current = provider.currentPage;

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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 64,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No records found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientTable(BuildContext context, List<Patient> pagePatients) {
    return Container(
      decoration: AppTheme.glassCard(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: pagePatients.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppTheme.dividerColor),
          itemBuilder: (context, index) {
            final patient = pagePatients[index];
            return _PatientTile(
              patient: patient,
              onTap: () => _openPatientDetail(context, patient),
            );
          },
        ),
      ),
    );
  }

  void _showPatientForm(BuildContext context, {Patient? patient}) {
    showDialog(
      context: context,
      builder: (_) => PatientFormScreen(patient: patient),
    );
  }

  void _openPatientDetail(BuildContext context, Patient patient) async {
    final provider = context.read<PatientProvider>();
    await provider.selectPatient(patient);
    if (context.mounted) {
      showDialog(context: context, builder: (_) => const PatientDetailScreen());
    }
  }
}

class _PatientTile extends StatefulWidget {
  final Patient patient;
  final VoidCallback onTap;

  const _PatientTile({required this.patient, required this.onTap});

  @override
  State<_PatientTile> createState() => _PatientTileState();
}

class _PatientTileState extends State<_PatientTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _isHovered
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      widget.patient.firstName.isNotEmpty
                          ? widget.patient.firstName[0].toUpperCase()
                          : (widget.patient.patientName.isNotEmpty
                                ? widget.patient.patientName[0].toUpperCase()
                                : '?'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.patient.patientName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.patient.idNumber} • ${widget.patient.role} • ${widget.patient.department}${widget.patient.level.isNotEmpty ? " • ${widget.patient.level}" : ""}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
