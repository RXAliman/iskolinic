import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/patient_provider.dart';
import '../models/visitation.dart';
import '../theme/app_theme.dart';
import 'patient_detail_screen.dart';
import 'visitation_form_screen.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatientProvider>().loadGlobalVisits();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, provider, _) {
        final currentPage = provider.globalVisitPage;
        final totalPages = provider.totalGlobalVisitPages;
        final pageSize = provider.globalVisitPageSize;
        final totalVisits = provider.totalGlobalVisits;

        final start = currentPage * pageSize;
        final end = (start + provider.globalVisitations.length);

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
                    'Visitations',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalVisits total visitations',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildVisitsFilters(provider),
              const SizedBox(height: 24),

              // Visits Table
              Expanded(
                child: provider.loading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.globalVisitations.isEmpty
                    ? _buildEmptyState(context)
                    : _buildVisitTable(context, provider.globalVisitations),
              ),

              // Pagination
              if (totalPages > 1) ...[
                const SizedBox(height: 16),
                _buildPagination(provider, totalVisits, totalPages, start, end),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisitsFilters(PatientProvider provider) {
    final List<String> grades = [
      'Pre-school',
      'Grade School',
      'Junior High School',
      'Senior High School',
      'College',
    ];
    final today = DateTime.now();
    final isToday =
        provider.visitsSelectedDate == null ||
        (provider.visitsSelectedDate!.year == today.year &&
            provider.visitsSelectedDate!.month == today.month &&
            provider.visitsSelectedDate!.day == today.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Navigation
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: AppTheme.glassCard(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => provider.previousVisitsDay(),
                    icon: const Icon(Icons.chevron_left_rounded, size: 24),
                    color: AppTheme.textPrimary,
                    splashRadius: 20,
                    tooltip: 'Previous Day',
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Pick a Date',
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              provider.visitsSelectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          provider.setVisitsDate(date);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 160,
                        child: Text(
                          DateFormat('MMMM dd, yyyy').format(
                            provider.visitsSelectedDate ?? DateTime.now(),
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: isToday ? null : () => provider.nextVisitsDay(),
                    icon: const Icon(Icons.chevron_right_rounded, size: 24),
                    color: isToday ? AppTheme.textMuted : AppTheme.textPrimary,
                    splashRadius: 20,
                    tooltip: 'Next Day',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => provider.setVisitsDate(DateTime.now()),
              icon: const Icon(Icons.today_rounded, size: 18),
              label: const Text('Today'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.dividerColor),
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const VisitationFormScreen(),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Visit'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryLight,
                foregroundColor: AppTheme.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.accent),
                ),
                padding: const EdgeInsets.all(16),
              ),
              onPressed: () => provider.loadGlobalVisits(),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Reload'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
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
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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
                      final isSelected = provider.visitsSelectedDepartments
                          .contains(grade);
                      return CheckboxMenuButton(
                        closeOnActivate: false,
                        value: isSelected,
                        onChanged: (val) {
                          if (val != null) {
                            provider.toggleVisitsFilter(grade, val);
                          }
                        },
                        child: Text(grade),
                      );
                    }),
                    if (provider.visitsIncludeEmployee)
                      CheckboxMenuButton(
                        closeOnActivate: false,
                        value: provider.visitsSelectedDepartments.contains(
                          'General',
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            provider.toggleVisitsFilter('General', val);
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
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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
                      value: provider.visitsIncludeStudent,
                      onChanged: (val) {
                        if (val != null) {
                          provider.toggleVisitsFilter('Student', val);
                        }
                      },
                      child: const Text('Student'),
                    ),
                    CheckboxMenuButton(
                      closeOnActivate: false,
                      value: provider.visitsIncludeEmployee,
                      onChanged: (val) {
                        if (val != null) {
                          provider.toggleVisitsFilter('Employee', val);
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
                provider.clearVisitsFilters();
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Reset Filters'),
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
    final currentPage = provider.globalVisitPage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: AppTheme.glassCard(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${start + 1}–$end of $totalItems visitations',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                onPressed: currentPage > 0
                    ? () => provider.firstGlobalVisitPage()
                    : null,
                icon: const Icon(Icons.first_page_rounded, size: 20),
                tooltip: 'First page',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage > 0
                    ? () => provider.prevGlobalVisitPage()
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
                    ? () => provider.nextGlobalVisitPage()
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: 'Next',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage < totalPages - 1
                    ? () => provider.lastGlobalVisitPage()
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
    final current = provider.globalVisitPage;
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
            Icons.medical_services_outlined,
            size: 64,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No visitations found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or date selection',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitTable(
    BuildContext context,
    List<Map<String, dynamic>> visits,
  ) {
    return Container(
      decoration: AppTheme.glassCard(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: visits.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppTheme.dividerColor),
          itemBuilder: (context, index) {
            final visit = visits[index];
            return _VisitTile(visit: visit);
          },
        ),
      ),
    );
  }
}

class _VisitTile extends StatefulWidget {
  final Map<String, dynamic> visit;

  const _VisitTile({required this.visit});

  @override
  State<_VisitTile> createState() => _VisitTileState();
}

class _VisitTileState extends State<_VisitTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final visitMap = widget.visit;
    final visitation = Visitation.fromMap(visitMap);

    final formattedDate = DateFormat(
      'MMM d, yyyy • h:mm a',
    ).format(visitation.dateTime);
    final symptoms = visitation.symptoms;
    final customComplaint = visitation.customChiefComplaint;

    final patientName = visitMap['patientName'] as String? ?? 'Unknown Patient';
    final department = visitMap['department'] as String? ?? 'Unknown';
    final role = visitMap['role'] as String? ?? 'Unknown';
    final level = visitMap['level'] as String? ?? '';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _isHovered
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.transparent,
        child: InkWell(
          onTap: () async {
            // Option to open patient detail when tapping the visit
            final patientId = visitMap['patientId'] as String;
            final provider = context.read<PatientProvider>();
            await provider.selectPatientById(patientId);
            if (context.mounted && provider.selectedPatient != null) {
              showDialog(
                context: context,
                builder: (_) => const PatientDetailScreen(),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                // Info
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$formattedDate • $role • $department${level.isNotEmpty ? " • $level" : ""}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Symptoms
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          ...symptoms.map(
                            (s) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (customComplaint.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                customComplaint,
                                style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
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
