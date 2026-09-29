import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../providers/patient_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import 'visitation_form_screen.dart';
import 'patient_form_screen.dart';
import '../models/patient.dart';

class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  int _selectedIndex = 0;

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, provider, _) {
        final patient = provider.selectedPatient;
        if (patient == null) {
          return const Dialog(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No patient selected'),
            ),
          );
        }

        return Dialog(
          child: Container(
            width: 840,
            height: 640,
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppTheme.accentGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          patient.firstName.isNotEmpty
                              ? patient.firstName[0].toUpperCase()
                              : (patient.patientName.isNotEmpty
                                    ? patient.patientName[0].toUpperCase()
                                    : '?'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.patientName,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Row(
                            children: [
                              Text(
                                patient.idNumber,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: patient.idNumber),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'ID Number ${patient.idNumber} copied',
                                      ),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                      width: 300,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Copy ID Number',
                                color: AppTheme.textMuted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Sidebar Menu ---
                      SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SidebarItem(
                              title: 'Basic Information',
                              icon: Icons.person_outline_rounded,
                              isSelected: _selectedIndex == 0,
                              onTap: () => setState(() => _selectedIndex = 0),
                            ),
                            const SizedBox(height: 8),
                            _SidebarItem(
                              title: 'Visitation History',
                              icon: Icons.history_rounded,
                              isSelected: _selectedIndex == 1,
                              onTap: () => setState(() => _selectedIndex = 1),
                            ),
                            const SizedBox(height: 8),
                            _SidebarItem(
                              title: 'Medical Information',
                              icon: Icons.medical_information_rounded,
                              isSelected: _selectedIndex == 2,
                              onTap: () => setState(() => _selectedIndex = 2),
                            ),
                            const SizedBox(height: 8),
                            _SidebarItem(
                              title: 'Permissions',
                              icon: Icons.verified_user_outlined,
                              isSelected: _selectedIndex == 3,
                              onTap: () => setState(() => _selectedIndex = 3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppTheme.dividerColor,
                      ),
                      const SizedBox(width: 16),

                      if (_selectedIndex == 0)
                        // --- Patient Info Content ---
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) =>
                                            PatientFormScreen(patient: patient),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: AppTheme.accent,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Edit'),
                                  ),
                                  const SizedBox(width: 16),
                                  TextButton.icon(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete Patient'),
                                          content: Text(
                                            'Are you sure you want to delete ${patient.patientName}? This will also delete all visitation records.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.danger,
                                              ),
                                              onPressed: () {
                                                context
                                                    .read<PatientProvider>()
                                                    .deletePatient(patient.id);
                                                Navigator.pop(
                                                  ctx,
                                                ); // close dialog
                                                Navigator.pop(
                                                  context,
                                                ); // close details screen
                                              },
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: AppTheme.danger,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Delete'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _InfoCell(
                                              icon:
                                                  Icons.person_outline_outlined,
                                              label: 'Role',
                                              value: patient.role.trim() != ''
                                                  ? patient.role
                                                  : '—',
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons.groups,
                                              label: 'Department',
                                              value:
                                                  patient.department.trim() !=
                                                      ''
                                                  ? patient.department
                                                  : '—',
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (patient.level.isNotEmpty) ...[
                                        const SizedBox(height: 20),
                                        _InfoCell(
                                          icon: Icons.layers_outlined,
                                          label: 'Level',
                                          value: patient.level,
                                        ),
                                      ],
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons.cake_outlined,
                                              label: 'Birthdate',
                                              value: patient.birthdate != null
                                                  ? DateFormat(
                                                      'MMM dd, yyyy',
                                                    ).format(patient.birthdate!)
                                                  : '—',
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons
                                                  .accessibility_new_outlined,
                                              label: 'Age',
                                              value: patient.birthdate != null
                                                  ? '${_calculateAge(patient.birthdate!)} years old'
                                                  : '—',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons.wc_outlined,
                                              label: 'Sex',
                                              value: patient.sex.isNotEmpty
                                                  ? patient.sex
                                                  : '—',
                                            ),
                                          ),
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons.phone_outlined,
                                              label: 'Contact',
                                              value:
                                                  patient
                                                      .contactNumber
                                                      .isNotEmpty
                                                  ? patient.contactNumber
                                                  : '—',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _InfoCell(
                                        icon: Icons.home_outlined,
                                        label: 'Address',
                                        value: patient.address.isNotEmpty
                                            ? patient.address
                                            : '—',
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons
                                                  .family_restroom_outlined,
                                              label: 'Parent / Guardian Name',
                                              value:
                                                  patient
                                                      .guardianName
                                                      .isNotEmpty
                                                  ? patient.guardianName
                                                  : '—',
                                            ),
                                          ),
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons.phone_outlined,
                                              label:
                                                  'Parent / Guardian Contact',
                                              value:
                                                  patient
                                                      .guardianContact
                                                      .isNotEmpty
                                                  ? patient.guardianContact
                                                  : '—',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons
                                                  .family_restroom_outlined,
                                              label: 'Second Guardian Name',
                                              value:
                                                  patient
                                                      .guardian2Name
                                                      .isNotEmpty
                                                  ? patient.guardian2Name
                                                  : '—',
                                            ),
                                          ),
                                          Expanded(
                                            child: _InfoCell(
                                              icon: Icons.phone_outlined,
                                              label: 'Second Guardian Contact',
                                              value:
                                                  patient
                                                      .guardian2Contact
                                                      .isNotEmpty
                                                  ? patient.guardian2Contact
                                                  : '—',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_selectedIndex == 1)
                        // --- Visitation History Content ---
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => VisitationFormScreen(
                                      patientId: patient.id,
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: AppTheme.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add Visit'),
                              ),
                              const SizedBox(height: 24),
                              // Visitation List
                              Expanded(
                                child: provider.visitations.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.medical_services_outlined,
                                              size: 48,
                                              color: AppTheme.textMuted,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'No visits recorded',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: provider.visitations.length,
                                        itemBuilder: (context, index) {
                                          final visit =
                                              provider.visitations[index];
                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            padding: const EdgeInsets.all(16),
                                            decoration:
                                                DateUtils.isSameDay(
                                                  visit.dateTime,
                                                  DateTime.now(),
                                                )
                                                ? AppTheme.glassCard().copyWith(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          0,
                                                        ),
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: AppTheme.accent,
                                                        width: 4,
                                                      ),
                                                      right: BorderSide(
                                                        color: AppTheme
                                                            .dividerColor,
                                                        width: 1,
                                                      ),
                                                      top: BorderSide(
                                                        color: AppTheme
                                                            .dividerColor,
                                                        width: 1,
                                                      ),
                                                      bottom: BorderSide(
                                                        color: AppTheme
                                                            .dividerColor,
                                                        width: 1,
                                                      ),
                                                    ),
                                                  )
                                                : AppTheme.glassCard(),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .calendar_today_rounded,
                                                      size: 14,
                                                      color: AppTheme.accent,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      DateFormat(
                                                        'MMM dd, yyyy – hh:mm a',
                                                      ).format(visit.dateTime),
                                                      style: const TextStyle(
                                                        color: AppTheme.accent,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    if (DateUtils.isSameDay(
                                                      visit.dateTime,
                                                      DateTime.now(),
                                                    )) ...[
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          backgroundColor:
                                                              Colors.white,
                                                          foregroundColor:
                                                              AppTheme.accent,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            side: BorderSide(
                                                              color: AppTheme
                                                                  .accent,
                                                            ),
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          showDialog(
                                                            context: context,
                                                            builder: (_) =>
                                                                VisitationFormScreen(
                                                                  patientId:
                                                                      patient
                                                                          .id,
                                                                  visitation:
                                                                      visit,
                                                                ),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Edit/View',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        foregroundColor:
                                                            AppTheme.danger,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          side: BorderSide(
                                                            color:
                                                                AppTheme.danger,
                                                          ),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        backgroundColor:
                                                            Colors.white,
                                                      ),
                                                      onPressed: () async {
                                                        final confirm = await showDialog<bool>(
                                                          context: context,
                                                          builder: (ctx) => AlertDialog(
                                                            title: const Text(
                                                              'Delete Visitation',
                                                            ),
                                                            content: const Text(
                                                              'Are you sure you want to delete this visitation record?',
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      ctx,
                                                                      false,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      'Cancel',
                                                                    ),
                                                              ),
                                                              ElevatedButton(
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor:
                                                                      AppTheme
                                                                          .danger,
                                                                ),
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      ctx,
                                                                      true,
                                                                    ),
                                                                child: const Text(
                                                                  'Delete',
                                                                  style: TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );

                                                        if (confirm == true &&
                                                            context.mounted) {
                                                          context
                                                              .read<
                                                                PatientProvider
                                                              >()
                                                              .deleteVisitation(
                                                                visit,
                                                              );
                                                        }
                                                      },
                                                      child: const Text(
                                                        'Delete',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),

                                                // Symptoms chips
                                                if (visit.symptoms.isNotEmpty)
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: visit.symptoms
                                                        .map(
                                                          (s) => Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: AppTheme
                                                                  .accent
                                                                  .withValues(
                                                                    alpha: 0.15,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              s,
                                                              style: const TextStyle(
                                                                color: AppTheme
                                                                    .accent,
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                if (visit.customChiefComplaint.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text(
                                                        'Other: ',
                                                        style: TextStyle(
                                                          color: AppTheme.textMuted,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          visit.customChiefComplaint,
                                                          style: const TextStyle(
                                                            color: AppTheme.textPrimary,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                if (visit
                                                        .treatment
                                                        .isNotEmpty ||
                                                    visit
                                                        .suppliesUsed
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Intervention/s: ',
                                                        style: TextStyle(
                                                          color: AppTheme
                                                              .textMuted,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          [
                                                            ...visit.suppliesUsed.map(
                                                              (s) => s.contains(':')
                                                                  ? s.split(':')[1]
                                                                  : context
                                                                      .read<InventoryProvider>()
                                                                      .getFormattedSupplyName(
                                                                        s,
                                                                      ),
                                                            ),
                                                            if (visit.treatment.isNotEmpty)
                                                              visit.treatment,
                                                          ].join(', '),
                                                          style: const TextStyle(
                                                            color: AppTheme.textPrimary,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                if (visit
                                                    .remarks
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Remarks: ',
                                                        style: TextStyle(
                                                          color: AppTheme
                                                              .textMuted,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          visit.remarks,
                                                          style: const TextStyle(
                                                            color: AppTheme
                                                                .textPrimary,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 16),
                              if (provider.visitations.isNotEmpty &&
                                  provider.totalVisitPages > 1)
                                _buildPagination(
                                  provider,
                                  provider.totalVisitations,
                                  provider.totalVisitPages,
                                  provider.currentVisitPage *
                                      provider.visitPageSize,
                                  (provider.currentVisitPage *
                                          provider.visitPageSize) +
                                      provider.visitations.length,
                                ),
                            ],
                          ),
                        ),
                      if (_selectedIndex == 2)
                        // --- Medical History Content ---
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => PatientFormScreen(
                                          patient: patient,
                                          initialTabIndex: 1,
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: AppTheme.accent,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      size: 20,
                                    ),
                                    label: const Text('Edit Medical Info'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Allergies',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        patient.allergicTo.isNotEmpty
                                            ? patient.allergicTo
                                            : 'No known allergies.',
                                        style: TextStyle(
                                          color: patient.allergicTo.isNotEmpty
                                              ? AppTheme.textPrimary
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Divider(),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Past Medical History',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 12),
                                      if (patient.pastMedicalHistory.isEmpty)
                                        const Text(
                                          'No history recorded.',
                                          style: TextStyle(
                                            color: AppTheme.textMuted,
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).cardColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: AppTheme.dividerColor,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              const Row(
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      'Disease',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 1,
                                                    child: Center(
                                                      child: Text(
                                                        'Past',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 1,
                                                    child: Center(
                                                      child: Text(
                                                        'Present',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const Divider(),
                                              ...patient.pastMedicalHistory.map((
                                                m,
                                              ) {
                                                return Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        m['disease'].toString(),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 1,
                                                      child: Center(
                                                        child: Checkbox(
                                                          value:
                                                              m['past'] == true,
                                                          onChanged:
                                                              null, // Read-only
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 1,
                                                      child: Center(
                                                        child: Checkbox(
                                                          value:
                                                              m['present'] ==
                                                              true,
                                                          onChanged:
                                                              null, // Read-only
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }), // map
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 14),
                                      const Divider(),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Vaccination History',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 12),
                                      if (patient.vaccinationHistory.isEmpty)
                                        const Text(
                                          'No vaccines recorded.',
                                          style: TextStyle(
                                            color: AppTheme.textMuted,
                                          ),
                                        )
                                      else
                                        ...patient.vaccinationHistory.map((m) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.vaccines_outlined,
                                                  color: AppTheme.accent,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    m['name'].toString(),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  m['dateGiven'] != null
                                                      ? DateFormat(
                                                          'MMM dd, yyyy',
                                                        ).format(
                                                          DateTime.parse(
                                                            m['dateGiven'],
                                                          ),
                                                        )
                                                      : 'Unknown Date',
                                                  style: const TextStyle(
                                                    color: AppTheme.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      const SizedBox(height: 14),
                                      const Divider(),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Other Patient Remarks',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        patient.patientRemarks.isNotEmpty
                                            ? patient.patientRemarks
                                            : 'No remarks.',
                                        style: TextStyle(
                                          color:
                                              patient.patientRemarks.isNotEmpty
                                              ? AppTheme.textPrimary
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_selectedIndex == 3)
                        Expanded(child: _buildPermissionsTab(context, patient)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermissionsTab(BuildContext context, Patient patient) {
    final p = patient.permissions;
    final suddenIllness = p['suddenIllness'] == true;
    final initialMedication = p['initialMedication'] == true;
    final emergencyHospital = p['emergencyHospital'] == true;
    final procedure = p['procedure'] == true;
    final marikinaValley = p['marikinaValley'] == true;
    final marikinaStVincent = p['marikinaStVincent'] == true;
    final othersPermission = p['others'] == true;
    final othersSpecify = p['othersSpecify']?.toString() ?? '';

    Widget buildCheck(String text, bool checked) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          children: [
            Icon(
              checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: checked ? AppTheme.textMuted : AppTheme.dividerColor,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: checked ? AppTheme.textPrimary : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) =>
                      PatientFormScreen(patient: patient, initialTabIndex: 2),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.accent),
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text('Edit Permissions'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permission granted for:',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                buildCheck(
                  'Treatment of sudden illness or injuries',
                  suddenIllness,
                ),
                buildCheck(
                  "Giving of initial medication for child's illness while in school",
                  initialMedication,
                ),
                buildCheck(
                  'School authorities to take the child to the nearest hospital if emergency',
                  emergencyHospital,
                ),
                if (emergencyHospital)
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildCheck(
                          'Marikina Valley Medical Center',
                          marikinaValley,
                        ),
                        buildCheck(
                          'Marikina St. Vincent Hospital',
                          marikinaStVincent,
                        ),
                        buildCheck(
                          'Others: ${othersPermission ? othersSpecify : ""}'
                              .trim(),
                          othersPermission,
                        ),
                      ],
                    ),
                  ),
                buildCheck(
                  'Treatment/Procedure is deemed necessary',
                  procedure,
                ),
              ],
            ),
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
    final currentPage = provider.currentVisitPage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: AppTheme.glassCard(),
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
                    ? () => provider.firstVisitPage()
                    : null,
                icon: const Icon(Icons.first_page_rounded, size: 20),
                tooltip: 'First page',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage > 0
                    ? () => provider.prevVisitPage()
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
                    ? () => provider.nextVisitPage()
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                tooltip: 'Next',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: currentPage < totalPages - 1
                    ? () => provider.lastVisitPage()
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
    final current = provider.currentVisitPage;
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
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: AppTheme.textMuted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppTheme.accent : AppTheme.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
