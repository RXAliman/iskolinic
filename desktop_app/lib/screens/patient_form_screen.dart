import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../formatters/uppercase_text.dart';
import '../models/patient.dart';
import '../providers/patient_provider.dart';
import '../services/database_helper.dart';
import '../theme/app_theme.dart';

class PatientFormScreen extends StatefulWidget {
  final Patient? patient;
  final int initialTabIndex;

  const PatientFormScreen({super.key, this.patient, this.initialTabIndex = 0});

  @override
  State<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idFieldKey = GlobalKey<FormFieldState>();
  final _idFocusNode = FocusNode();
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _middleNameCtrl;
  late TextEditingController _customExtensionCtrl;
  String _selectedExtension = 'None';
  late TextEditingController _numberCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _guardianNameCtrl;
  late TextEditingController _guardianContactCtrl;

  DateTime? _selectedBirthdate;
  late TextEditingController _birthdateCtrl;
  String? _selectedSex;
  String? _selectedRole;
  String? _selectedDepartment;
  String? _selectedLevel;
  late TextEditingController _contactCtrl;
  late TextEditingController _guardian2NameCtrl;
  late TextEditingController _guardian2ContactCtrl;
  late TextEditingController _allergicToCtrl;
  late TextEditingController _patientRemarksCtrl;
  late TextEditingController _othersSpecifyCtrl;

  bool _suddenIllness = false;
  bool _initialMedication = false;
  bool _emergencyHospital = false;
  bool _procedure = false;
  bool _marikinaValley = false;
  bool _marikinaStVincent = false;
  bool _othersPermission = false;
  bool _hasAttemptedSave = false;
  String? _idErrorMessage;

  bool get isEditing => widget.patient != null;

  final List<String> _presetDiseases = [
    'Chicken Pox',
    'Dengue',
    'Diphtheria',
    'German Measles',
    'Hepatitis',
    'Measles',
    'Mumps',
    'Primary Complex',
    'Typhoid Fever',
    'Whooping Cough',
    'Asthma',
    'Diabetes',
    'Ear Disorder',
    'Epilepsy',
    'Eye Disorder',
    'Heart Disease',
    'Kidney Disease',
    'Tuberculosis',
    'G6PD',
  ];

  late List<Map<String, dynamic>> _pastMedicalHistory;
  late List<Map<String, dynamic>> _vaccinationHistory;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(
      text: widget.patient?.firstName ?? '',
    );
    _lastNameCtrl = TextEditingController(text: widget.patient?.lastName ?? '');
    _middleNameCtrl = TextEditingController(
      text: widget.patient?.middleName ?? '',
    );

    final ext = widget.patient?.extension ?? '';
    if (ext.isEmpty || ext == 'None') {
      _selectedExtension = 'None';
      _customExtensionCtrl = TextEditingController();
    } else if (['Jr.', 'Sr.', 'I', 'II', 'III'].contains(ext)) {
      _selectedExtension = ext;
      _customExtensionCtrl = TextEditingController();
    } else {
      _selectedExtension = 'Others';
      _customExtensionCtrl = TextEditingController(text: ext);
    }
    _numberCtrl = TextEditingController(text: widget.patient?.idNumber ?? '');
    _numberCtrl.addListener(() {
      if (_idErrorMessage != null) {
        setState(() => _idErrorMessage = null);
      }
    });

    _idFocusNode.addListener(() {
      if (!_idFocusNode.hasFocus && _numberCtrl.text.trim().isNotEmpty) {
        _validateIdUniqueness();
      }
    });
    _addressCtrl = TextEditingController(text: widget.patient?.address ?? '');
    _guardianNameCtrl = TextEditingController(
      text: widget.patient?.guardianName ?? '',
    );
    _guardianContactCtrl = TextEditingController(
      text: widget.patient?.guardianContact ?? '',
    );
    _selectedBirthdate = widget.patient?.birthdate;
    _birthdateCtrl = TextEditingController(
      text: _selectedBirthdate != null
          ? DateFormat('MMM dd, yyyy').format(_selectedBirthdate!)
          : '',
    );
    final sex = widget.patient?.sex ?? '';
    if (sex.isEmpty) {
      _selectedSex = null;
    } else if (['Male', 'Female', 'Intersex'].contains(sex)) {
      _selectedSex = sex;
    } else {
      _selectedSex = 'Intersex'; // fallback for backward compatibility
    }
    _contactCtrl = TextEditingController(
      text: widget.patient?.contactNumber ?? '',
    );

    final role = widget.patient?.role ?? '';
    _selectedRole = role.isEmpty ? null : role;
    final department = widget.patient?.department ?? '';
    _selectedDepartment = department.isEmpty ? null : department;
    final level = widget.patient?.level ?? '';
    _selectedLevel = level.isEmpty ? null : level;
    _guardian2NameCtrl = TextEditingController(
      text: widget.patient?.guardian2Name ?? '',
    );
    _guardian2ContactCtrl = TextEditingController(
      text: widget.patient?.guardian2Contact ?? '',
    );
    _allergicToCtrl = TextEditingController(
      text: widget.patient?.allergicTo ?? '',
    );
    _patientRemarksCtrl = TextEditingController(
      text: widget.patient?.patientRemarks ?? '',
    );

    // Initialize Medical History
    _pastMedicalHistory = [];
    final existingMedical = widget.patient?.pastMedicalHistory ?? [];
    final existingMap = {
      for (var item in existingMedical) item['disease'] as String: item,
    };

    for (final disease in _presetDiseases) {
      if (existingMap.containsKey(disease)) {
        _pastMedicalHistory.add(
          Map<String, dynamic>.from(existingMap[disease]!),
        );
        existingMap.remove(disease);
      } else {
        _pastMedicalHistory.add({
          'disease': disease,
          'past': false,
          'present': false,
        });
      }
    }
    for (final customDisease in existingMap.values) {
      _pastMedicalHistory.add(Map<String, dynamic>.from(customDisease));
    }

    _vaccinationHistory =
        widget.patient?.vaccinationHistory
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];

    final p = widget.patient?.permissions ?? {};
    _suddenIllness = p['suddenIllness'] == true;
    _initialMedication = p['initialMedication'] == true;
    _emergencyHospital = p['emergencyHospital'] == true;
    _procedure = p['procedure'] == true;
    _marikinaValley = p['marikinaValley'] == true;
    _marikinaStVincent = p['marikinaStVincent'] == true;
    _othersPermission = p['others'] == true;
    _othersSpecifyCtrl = TextEditingController(
      text: p['othersSpecify']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _customExtensionCtrl.dispose();
    _birthdateCtrl.dispose();
    _numberCtrl.dispose();
    _addressCtrl.dispose();
    _guardianNameCtrl.dispose();
    _guardianContactCtrl.dispose();
    _contactCtrl.dispose();
    _guardian2NameCtrl.dispose();
    _guardian2ContactCtrl.dispose();
    _allergicToCtrl.dispose();
    _patientRemarksCtrl.dispose();
    _othersSpecifyCtrl.dispose();
    _idFocusNode.dispose();
    super.dispose();
  }

  Future<void> _validateIdUniqueness() async {
    final idNumber = _numberCtrl.text.trim();
    if (idNumber.isEmpty) {
      if (_idErrorMessage != null) {
        setState(() => _idErrorMessage = null);
        _idFieldKey.currentState?.validate();
      }
      return;
    }

    final existing = await DatabaseHelper.instance.getPatientByIdNumber(
      idNumber,
    );

    if (existing != null && existing.id != widget.patient?.id) {
      setState(() => _idErrorMessage = 'ID Number already exists');
    } else {
      if (_idErrorMessage != null) {
        setState(() => _idErrorMessage = null);
      }
    }
    // Re-validate ONLY the ID field to show/hide the error message immediately
    _idFieldKey.currentState?.validate();
  }

  Future<void> _save() async {
    final provider = context.read<PatientProvider>();
    setState(() => _hasAttemptedSave = true);

    // Async validation for ID number uniqueness
    await _validateIdUniqueness();

    if (!mounted) return;

    // Check custom required validation for Birthdate
    bool isValid = _formKey.currentState!.validate();
    if (_selectedBirthdate == null) {
      isValid = false;
    }
    if (!isValid) return;

    if (!mounted) return;

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final middleName = _middleNameCtrl.text.trim();

    String ext = '';
    if (_selectedExtension == 'Others') {
      ext = _customExtensionCtrl.text.trim();
    } else if (_selectedExtension != 'None') {
      ext = _selectedExtension;
    }

    final patientName = '$lastName, $firstName $middleName $ext'
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    String finalSex = _selectedSex ?? '';
    String finalRole = _selectedRole ?? '';
    String finalDepartment = _selectedDepartment ?? '';
    String finalLevel = _selectedLevel ?? '';

    final permissionsMap = {
      'suddenIllness': _suddenIllness,
      'initialMedication': _initialMedication,
      'emergencyHospital': _emergencyHospital,
      'procedure': _procedure,
      'marikinaValley': _marikinaValley,
      'marikinaStVincent': _marikinaStVincent,
      'others': _othersPermission,
      'othersSpecify': _othersSpecifyCtrl.text.trim(),
    };

    if (isEditing) {
      final updated = widget.patient!.copyWith(
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        extension: ext,
        patientName: patientName,
        idNumber: _numberCtrl.text.trim(),
        birthdate: _selectedBirthdate,
        sex: finalSex,
        contactNumber: _contactCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        guardianName: _guardianNameCtrl.text.trim(),
        guardianContact: _guardianContactCtrl.text.trim(),
        guardian2Name: _guardian2NameCtrl.text.trim(),
        guardian2Contact: _guardian2ContactCtrl.text.trim(),
        pastMedicalHistory: _pastMedicalHistory
            .where((m) => m['past'] == true || m['present'] == true)
            .toList(),
        vaccinationHistory: _vaccinationHistory
            .where((m) => m['name'].toString().trim().isNotEmpty)
            .toList(),
        allergicTo: _allergicToCtrl.text.trim(),
        patientRemarks: _patientRemarksCtrl.text.trim(),
        permissions: permissionsMap,
        role: finalRole,
        department: finalDepartment,
        level: finalLevel,
      );
      await provider.updatePatient(updated);
      if (mounted) Navigator.pop(context);
    } else {
      final patient = Patient(
        id: const Uuid().v4(),
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        extension: ext,
        patientName: patientName,
        idNumber: _numberCtrl.text.trim(),
        birthdate: _selectedBirthdate,
        sex: finalSex,
        contactNumber: _contactCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        guardianName: _guardianNameCtrl.text.trim(),
        guardianContact: _guardianContactCtrl.text.trim(),
        guardian2Name: _guardian2NameCtrl.text.trim(),
        guardian2Contact: _guardian2ContactCtrl.text.trim(),
        pastMedicalHistory: _pastMedicalHistory
            .where((m) => m['past'] == true || m['present'] == true)
            .toList(),
        vaccinationHistory: _vaccinationHistory
            .where((m) => m['name'].toString().trim().isNotEmpty)
            .toList(),
        allergicTo: _allergicToCtrl.text.trim(),
        patientRemarks: _patientRemarksCtrl.text.trim(),
        permissions: permissionsMap,
        role: finalRole,
        department: finalDepartment,
        level: finalLevel,
      );
      await provider.addPatient(patient);
      if (mounted) Navigator.pop(context, patient);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Dialog(
        child: DefaultTabController(
          length: 3,
          initialIndex: widget.initialTabIndex,
          child: Container(
            width: 760,
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
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
                        child: Icon(
                          isEditing
                              ? Icons.edit_rounded
                              : Icons.person_add_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        isEditing ? 'Edit Record' : 'New Record',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    tabs: [
                      Tab(text: 'Personal Information'),
                      Tab(text: 'Medical Information'),
                      Tab(text: 'Permissions'),
                    ],
                    labelColor: Colors.white,
                    labelStyle: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontFamily: GoogleFonts.inter().fontFamily,
                      fontWeight: FontWeight.normal,
                    ),
                    indicator: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    dividerColor: AppTheme.accent,
                    dividerHeight: 2,
                    indicatorSize: TabBarIndicatorSize.tab,
                  ),
                  const SizedBox(height: 16),

                  // Tabbed Fields
                  Flexible(
                    child: TabBarView(
                      children: [
                        _buildPersonalTab(),
                        _buildMedicalTab(),
                        _buildPermissionsTab(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _save,
                        child: Text(isEditing ? 'Save' : 'Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0, top: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            // Name Row 1: First Name & Last Name
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameCtrl,
                    maxLength: 30,
                    decoration: InputDecoration(
                      label: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontWeight: FontWeight.w400),
                          children: [
                            TextSpan(
                              text: 'First Name ',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            TextSpan(
                              text: '*',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                        ),
                      ),
                      prefixIcon: Icon(Icons.person_outline),
                      counterText: '',
                    ),
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(30),
                    ],
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameCtrl,
                    maxLength: 30,
                    decoration: InputDecoration(
                      label: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontWeight: FontWeight.w400),
                          children: [
                            TextSpan(
                              text: 'Last Name ',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            TextSpan(
                              text: '*',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                        ),
                      ),
                      prefixIcon: Icon(Icons.person_outline),
                      counterText: '',
                    ),
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(30),
                    ],
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Name Row 2: Middle Name & Extension
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _middleNameCtrl,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Middle Name',
                      prefixIcon: Icon(Icons.person_outline),
                      counterText: '',
                    ),
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(30),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: _selectedExtension == 'Others' ? 1 : 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedExtension,
                    decoration: const InputDecoration(
                      labelText: 'Extension',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: ['None', 'JR.', 'SR.', 'I', 'II', 'III', 'Others']
                        .map((e) {
                          return DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: GoogleFonts.inter(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          );
                        })
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedExtension = val);
                      }
                    },
                  ),
                ),
                if (_selectedExtension == 'Others') ...[
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _customExtensionCtrl,
                      maxLength: 5,
                      decoration: const InputDecoration(
                        labelText: 'Specify',
                        counterText: '',
                      ),
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ID Number
            TextFormField(
              key: _idFieldKey,
              controller: _numberCtrl,
              focusNode: _idFocusNode,
              maxLength: 16,
              decoration: InputDecoration(
                label: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(fontWeight: FontWeight.w400),
                    children: [
                      TextSpan(
                        text: 'ID Number ',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: AppTheme.danger),
                      ),
                    ],
                  ),
                ),
                prefixIcon: Icon(Icons.badge_outlined),
                counterText: '',
              ),
              inputFormatters: [
                UpperCaseTextFormatter(),
                LengthLimitingTextInputFormatter(16),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                return _idErrorMessage;
              },
            ),
            const SizedBox(height: 16),

            // Role & Department
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    hint: Text(
                      'Select role',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    decoration: InputDecoration(
                      label: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Role ',
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: "*",
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                        ),
                      ),
                      prefixIcon: Icon(Icons.work_outline),
                    ),
                    items: ['Student', 'Employee'].map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text(
                          r,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                          ),
                        ),
                      );
                    }).toList(),
                    validator: (v) => v == null ? 'Required' : null,
                    onChanged: (val) {
                      setState(() {
                        _selectedRole = val;
                        // Reset department if switching to a role
                        // where current selection is invalid
                        if (val == 'Student' &&
                            _selectedDepartment == 'General') {
                          _selectedDepartment = null;
                        }
                        if (val != 'Student') {
                          _selectedLevel = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDepartment,
                    hint: Text(
                      'Select department',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    decoration: InputDecoration(
                      label: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Department ',
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: "*",
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                        ),
                      ),
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    items:
                        [
                          if (_selectedRole == 'Employee') 'General',
                          'Pre-school',
                          'Grade School',
                          'Junior High School',
                          'Senior High School',
                          'College',
                        ].map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(
                              d,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }).toList(),
                    validator: (v) => v == null ? 'Required' : null,
                    onChanged: (val) {
                      setState(() {
                        _selectedDepartment = val;
                        _selectedLevel = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_selectedRole == 'Student' && _selectedDepartment != null) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedLevel,
                hint: Text(
                  'Select level',
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                decoration: InputDecoration(
                  label: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Level ',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: "*",
                          style: TextStyle(color: AppTheme.danger),
                        ),
                      ],
                    ),
                  ),
                  prefixIcon: Icon(Icons.layers_outlined),
                ),
                items: () {
                  List<String> levels = [];
                  switch (_selectedDepartment) {
                    case 'Pre-school':
                      levels = ['Nursery', 'Pre-Kinder', 'Kinder'];
                      break;
                    case 'Grade School':
                      levels = [
                        'Grade 1',
                        'Grade 2',
                        'Grade 3',
                        'Grade 4',
                        'Grade 5',
                        'Grade 6',
                      ];
                      break;
                    case 'Junior High School':
                      levels = ['Grade 7', 'Grade 8', 'Grade 9', 'Grade 10'];
                      break;
                    case 'Senior High School':
                      levels = ['Grade 11', 'Grade 12'];
                      break;
                    case 'College':
                      levels = [
                        'First Year',
                        'Second Year',
                        'Third Year',
                        'Fourth Year',
                      ];
                      break;
                  }
                  return levels.map((l) {
                    return DropdownMenuItem(
                      value: l,
                      child: Text(
                        l,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }).toList();
                }(),
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (val) {
                  setState(() => _selectedLevel = val);
                },
              ),
              const SizedBox(height: 16),
            ],

            // Birthdate & Sex
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _birthdateCtrl,
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedBirthdate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedBirthdate = picked;
                          _birthdateCtrl.text = DateFormat(
                            'MMM dd, yyyy',
                          ).format(picked);
                        });
                      }
                    },
                    validator: (v) =>
                        (_hasAttemptedSave && _selectedBirthdate == null)
                        ? 'Required'
                        : null,
                    decoration: InputDecoration(
                      label: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontWeight: FontWeight.w400),
                          children: [
                            TextSpan(
                              text: 'Birthdate ',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            TextSpan(
                              text: '*',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                        ),
                      ),
                      prefixIcon: const Icon(Icons.cake_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSex,
                    hint: Text(
                      'Select Biological Sex',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    decoration: InputDecoration(
                      label: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontWeight: FontWeight.w400),
                          children: [
                            TextSpan(
                              text: 'Sex ',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            TextSpan(
                              text: '*',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ],
                        ),
                      ),
                      prefixIcon: const Icon(Icons.wc_outlined),
                    ),
                    items: ['Male', 'Female', 'Intersex'].map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w400),
                        ),
                      );
                    }).toList(),
                    validator: (v) => v == null ? 'Required' : null,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSex = val);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Contact Number
            TextFormField(
              controller: _contactCtrl,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: 'Contact Number',
                prefixIcon: Icon(Icons.phone_outlined),
                counterText: '',
              ),
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
            ),
            const SizedBox(height: 16),

            // Address
            TextFormField(
              controller: _addressCtrl,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.home_outlined),
                counterText: '',
              ),
              inputFormatters: [
                UpperCaseTextFormatter(),
                LengthLimitingTextInputFormatter(150),
              ],
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _guardianNameCtrl,
                    maxLength: 65,
                    decoration: const InputDecoration(
                      labelText: 'Parent / Guardian Name',
                      prefixIcon: Icon(Icons.family_restroom_outlined),
                      counterText: '',
                    ),
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(65),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _guardianContactCtrl,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'Parent / Guardian Contact',
                      prefixIcon: Icon(Icons.phone_outlined),
                      counterText: '',
                    ),
                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _guardian2NameCtrl,
                    maxLength: 65,
                    decoration: const InputDecoration(
                      labelText: 'Second Guardian Name',
                      prefixIcon: Icon(Icons.family_restroom_outlined),
                      counterText: '',
                    ),
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(65),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _guardian2ContactCtrl,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'Second Guardian Contact',
                      prefixIcon: Icon(Icons.phone_outlined),
                      counterText: '',
                    ),
                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicalTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0, top: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAllergiesSection(),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildMedicalHistorySection(),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildVaccinationSection(),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildPatientRemarksSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildAllergiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Allergies', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextFormField(
          controller: _allergicToCtrl,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'The patient is allergic to...',
            prefixIcon: Icon(Icons.coronavirus_outlined),
          ),
          inputFormatters: [UpperCaseTextFormatter()],
        ),
      ],
    );
  }

  Widget _buildPatientRemarksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Other Patient Remarks',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _patientRemarksCtrl,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Remarks',
            prefixIcon: Icon(Icons.note_alt_outlined),
          ),
          inputFormatters: [UpperCaseTextFormatter()],
        ),
      ],
    );
  }

  Widget _buildMedicalHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Past Medical History',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _pastMedicalHistory.insert(0, {
                    'disease': '',
                    'past': false,
                    'present': false,
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
              label: const Text('Add Item', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Disease',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Text(
                        'Past',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Text(
                        'Present',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40), // spacer for delete button
                ],
              ),
              const Divider(),
              ...List.generate(_pastMedicalHistory.length, (index) {
                final item = _pastMedicalHistory[index];
                final isPreset = _presetDiseases.contains(item['disease']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: isPreset
                            ? Text(item['disease'])
                            : TextFormField(
                                initialValue: item['disease'],
                                decoration: const InputDecoration(
                                  hintText: 'Enter disease name',
                                  isDense: true,
                                ),
                                onChanged: (val) => item['disease'] = val,
                              ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Checkbox(
                            value: item['past'] == true,
                            onChanged: (val) {
                              setState(() => item['past'] = val);
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Checkbox(
                            value: item['present'] == true,
                            onChanged: (val) {
                              setState(() => item['present'] = val);
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: !isPreset
                            ? IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppTheme.danger,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _pastMedicalHistory.removeAt(index);
                                  });
                                },
                              )
                            : null,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVaccinationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Vaccination History',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _vaccinationHistory.add({'name': '', 'dateGiven': null});
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
              label: const Text('Add Vaccine', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_vaccinationHistory.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                'No vaccines added',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          )
        else
          ..._vaccinationHistory.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: item['name'],
                      decoration: const InputDecoration(
                        labelText: 'Vaccine Name',
                        prefixIcon: Icon(Icons.vaccines_outlined),
                      ),
                      onChanged: (val) => item['name'] = val,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: item['dateGiven'] != null
                              ? DateTime.parse(item['dateGiven'])
                              : DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            item['dateGiven'] = date.toIso8601String();
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date Given',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          item['dateGiven'] != null
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(DateTime.parse(item['dateGiven']))
                              : 'Select Date',
                          style: TextStyle(
                            color: item['dateGiven'] != null
                                ? AppTheme.textPrimary
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppTheme.danger,
                    ),
                    onPressed: () {
                      setState(() {
                        _vaccinationHistory.removeAt(index);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPermissionsTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0, top: 8.0, bottom: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permission granted for:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: Text(
                'Treatment of sudden illness or injuries',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                ),
              ),
              value: _suddenIllness,
              activeColor: AppTheme.accent,
              onChanged: (val) => setState(() => _suddenIllness = val == true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: Text(
                "Giving of initial medication for child's illness while in school",
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                ),
              ),
              value: _initialMedication,
              activeColor: AppTheme.accent,
              onChanged: (val) =>
                  setState(() => _initialMedication = val == true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: Text(
                'School authorities to take the child to the nearest hospital if emergency',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                ),
              ),
              value: _emergencyHospital,
              activeColor: AppTheme.accent,
              onChanged: (val) => setState(() {
                _emergencyHospital = val == true;
                if (!_emergencyHospital) {
                  _marikinaValley = false;
                  _marikinaStVincent = false;
                  _othersPermission = false;
                  _othersSpecifyCtrl.clear();
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32.0),
              child: Column(
                children: [
                  CheckboxListTile(
                    title: Text(
                      'Marikina Valley Medical Center',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    value: _marikinaValley,
                    activeColor: AppTheme.accent,
                    onChanged: _emergencyHospital
                        ? (val) => setState(() => _marikinaValley = val == true)
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    title: Text(
                      'Marikina St. Vincent Hospital',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    value: _marikinaStVincent,
                    activeColor: AppTheme.accent,
                    onChanged: _emergencyHospital
                        ? (val) =>
                              setState(() => _marikinaStVincent = val == true)
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    title: Text(
                      'Others (specify)',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    value: _othersPermission,
                    activeColor: AppTheme.accent,
                    onChanged: _emergencyHospital
                        ? (val) => setState(() {
                            _othersPermission = val == true;
                            if (!_othersPermission) {
                              _othersSpecifyCtrl.clear();
                            }
                          })
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_othersPermission)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 32.0,
                        right: 16.0,
                        top: 4.0,
                        bottom: 8.0,
                      ),
                      child: TextFormField(
                        controller: _othersSpecifyCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Enter hospital name',
                          isDense: true,
                        ),
                        inputFormatters: [UpperCaseTextFormatter()],
                      ),
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              title: Text(
                'Treatment/Procedure is deemed necessary',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                ),
              ),
              value: _procedure,
              activeColor: AppTheme.accent,
              onChanged: (val) => setState(() => _procedure = val == true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }
}
