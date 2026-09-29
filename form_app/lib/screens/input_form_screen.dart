import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../constants/symptoms.dart';
import '../formatters/uppercase_text.dart';
import '../services/desktop_connection_service.dart';
import '../services/queue_service.dart';
import '../services/persistent_form_service.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';

class InputFormScreen extends StatefulWidget {
  const InputFormScreen({super.key});

  @override
  State<InputFormScreen> createState() => _InputFormScreenState();
}

class _InputFormScreenState extends State<InputFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _queueService = QueueService();
  final _idFocusNode = FocusNode();
  bool _isSubmitting = false;
  bool _isAutofilling = false;
  bool _hasAttemptedSubmit = false;
  bool _isPartialResult = false;
  bool _isRequestingEdit = false;
  String? _idErrorMessage;

  /// Whether autofill has populated the form with an existing patient's data.
  bool get _isAutofilled =>
      PersistentFormService.instance.existingPatientId != null;

  // ── Patient fields ───────────────────────────────────────────────
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _customExtensionCtrl = TextEditingController();
  String _selectedExtension = 'None';
  final _numberCtrl = TextEditingController();
  DateTime? _selectedBirthdate;
  String? _selectedSex;
  String? _selectedRole;
  String? _selectedDepartment;
  String? _selectedLevel;
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _guardianNameCtrl = TextEditingController();
  final _guardianContactCtrl = TextEditingController();
  final _guardian2NameCtrl = TextEditingController();
  final _guardian2ContactCtrl = TextEditingController();
  final _allergicToCtrl = TextEditingController();
  final _customChiefComplaintCtrl = TextEditingController();

  // ── Visitation fields ────────────────────────────────────────────
  final Set<String> _selectedSymptoms = {};
  bool _showAllTraumatic = true;
  bool _showAllMedical = true;
  bool _showAllBehavioral = true;

  @override
  void initState() {
    super.initState();
    final p = PersistentFormService.instance;

    // Initialize state from persistence
    _firstNameCtrl.text = p.firstName;
    _lastNameCtrl.text = p.lastName;
    _middleNameCtrl.text = p.middleName;
    _numberCtrl.text = p.studentNumber;
    _contactCtrl.text = p.contactNumber;
    _addressCtrl.text = p.address;
    _guardianNameCtrl.text = p.guardianName;
    _guardianContactCtrl.text = p.guardianContact;
    _guardian2NameCtrl.text = p.guardian2Name;
    _guardian2ContactCtrl.text = p.guardian2Contact;
    _customExtensionCtrl.text = p.customExtension;
    _allergicToCtrl.text = p.allergicTo;
    _customChiefComplaintCtrl.text = p.customChiefComplaint;

    _selectedExtension = p.extension;
    _selectedBirthdate = p.birthdate;
    _selectedSex = p.sex;
    _selectedRole = p.role;
    _selectedDepartment = p.department;
    _selectedLevel = p.level.isEmpty ? null : p.level;
    _selectedSymptoms.addAll(p.selectedSymptoms);
    _isPartialResult = p.isPartial;

    // Add listeners to sync UI -> Persistent Service
    _firstNameCtrl.addListener(() => p.firstName = _firstNameCtrl.text);
    _lastNameCtrl.addListener(() => p.lastName = _lastNameCtrl.text);
    _middleNameCtrl.addListener(() => p.middleName = _middleNameCtrl.text);
    _customExtensionCtrl.addListener(
      () => p.customExtension = _customExtensionCtrl.text,
    );
    _numberCtrl.addListener(() {
      p.studentNumber = _numberCtrl.text;
      if (_idErrorMessage != null) {
        setState(() => _idErrorMessage = null);
      }
    });
    _contactCtrl.addListener(() => p.contactNumber = _contactCtrl.text);
    _addressCtrl.addListener(() => p.address = _addressCtrl.text);
    _guardianNameCtrl.addListener(
      () => p.guardianName = _guardianNameCtrl.text,
    );
    _guardianContactCtrl.addListener(
      () => p.guardianContact = _guardianContactCtrl.text,
    );
    _guardian2NameCtrl.addListener(
      () => p.guardian2Name = _guardian2NameCtrl.text,
    );
    _guardian2ContactCtrl.addListener(
      () => p.guardian2Contact = _guardian2ContactCtrl.text,
    );
    _allergicToCtrl.addListener(() => p.allergicTo = _allergicToCtrl.text);
    _customChiefComplaintCtrl.addListener(
      () => p.customChiefComplaint = _customChiefComplaintCtrl.text,
    );

    // Trigger lookup when ID field loses focus
    _idFocusNode.addListener(() {
      if (!_idFocusNode.hasFocus && _numberCtrl.text.isNotEmpty) {
        _searchPatient(_numberCtrl.text);
      }
    });
  }

  Future<void> _searchPatient(String id, {String? requestId}) async {
    if (id.isEmpty || _isAutofilling) return;

    setState(() => _isAutofilling = true);

    try {
      final data = await DesktopConnectionService.instance
          .fetchPatientByIdNumber(id, requestId: requestId);
      if (data != null && mounted) {
        PersistentFormService.instance.updateFromMap(data);
        setState(() {
          _isPartialResult = PersistentFormService.instance.isPartial;
        });

        // Refresh UI from persistence
        final p = PersistentFormService.instance;
        _firstNameCtrl.text = p.firstName;
        _lastNameCtrl.text = p.lastName;
        _middleNameCtrl.text = p.middleName;
        _contactCtrl.text = p.contactNumber;
        _addressCtrl.text = p.address;
        _guardianNameCtrl.text = p.guardianName;
        _guardianContactCtrl.text = p.guardianContact;
        _guardian2NameCtrl.text = p.guardian2Name;
        _guardian2ContactCtrl.text = p.guardian2Contact;
        _customExtensionCtrl.text = p.customExtension;
        _allergicToCtrl.text = p.allergicTo;
        _customChiefComplaintCtrl.text = p.customChiefComplaint;

        setState(() {
          _selectedExtension = p.extension;
          _selectedBirthdate = p.birthdate;
          _selectedSex = p.sex;
          _selectedRole = p.role;
          _selectedDepartment = p.department;
          _selectedLevel = p.level.isEmpty ? null : p.level;
          _selectedSymptoms.clear();
          _selectedSymptoms.addAll(p.selectedSymptoms);
        });

        if (requestId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access approved! Full details loaded.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Patient details loaded.')),
          );
        }
      }
    } catch (_) {
      // Ignore errors
    } finally {
      if (mounted) setState(() => _isAutofilling = false);
    }
  }

  Future<void> _requestEditAccess() async {
    final idNumber = _numberCtrl.text;
    if (idNumber.isEmpty) return;

    setState(() => _isRequestingEdit = true);

    try {
      final request = await DesktopConnectionService.instance.requestEdit(
        idNumber,
      );
      if (request == null) {
        setState(() => _isRequestingEdit = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send edit request.')),
          );
        }
        return;
      }

      final requestId = request['id'] as String;
      bool approved = false;
      bool denied = false;
      bool cancelled = false;

      // Show persistent dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.security_rounded, color: AppTheme.accent),
                SizedBox(width: 12),
                Text('Request Pending'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Your request to edit your full details is pending. Please wait for the clinic staff to approve your request.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ID Number: $idNumber',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel Request'),
              ),
            ],
          ),
        ),
      );

      // Polling loop
      while (!approved && !denied && !cancelled && mounted) {
        await Future.delayed(const Duration(seconds: 2));
        if (cancelled) break;

        final status = await DesktopConnectionService.instance
            .checkEditRequestStatus(requestId);
        if (status != null && mounted) {
          if (status['isApproved'] == true) {
            approved = true;
          } else if (status['isDenied'] == true) {
            denied = true;
          }
        }
      }

      if (mounted) {
        if (approved) {
          if (Navigator.canPop(context)) Navigator.pop(context); // Close dialog
          await _searchPatient(
            idNumber,
            requestId: requestId,
          ); // Refetch full data
        } else if (denied) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request denied by administrator.')),
          );
        }
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isRequestingEdit = false);
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _customExtensionCtrl.dispose();
    _numberCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    _guardianNameCtrl.dispose();
    _guardianContactCtrl.dispose();
    _guardian2NameCtrl.dispose();
    _guardian2ContactCtrl.dispose();
    _allergicToCtrl.dispose();
    _customChiefComplaintCtrl.dispose();
    _idFocusNode.dispose();
    super.dispose();
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _firstNameCtrl.clear();
    _lastNameCtrl.clear();
    _middleNameCtrl.clear();
    _customExtensionCtrl.clear();
    _numberCtrl.clear();
    _contactCtrl.clear();
    _addressCtrl.clear();
    _guardianNameCtrl.clear();
    _guardianContactCtrl.clear();
    _guardian2NameCtrl.clear();
    _guardian2ContactCtrl.clear();
    _allergicToCtrl.clear();
    _customChiefComplaintCtrl.clear();
    PersistentFormService.instance.clear();
    setState(() {
      _selectedExtension = 'None';
      _selectedBirthdate = null;
      _selectedSex = null;
      _selectedRole = null;
      _selectedDepartment = null;
      _selectedLevel = null;
      _selectedSymptoms.clear();
      _hasAttemptedSubmit = false;
      _isPartialResult = false;
    });
  }

  Future<void> _submit() async {
    setState(() => _hasAttemptedSubmit = true);

    // Tablet validation for ID uniqueness (only for new patients)
    if (PersistentFormService.instance.existingPatientId == null) {
      final idNumber = _numberCtrl.text.trim();
      if (idNumber.isNotEmpty) {
        setState(() => _isSubmitting = true);
        try {
          final existing = await DesktopConnectionService.instance
              .fetchPatientByIdNumber(idNumber);
          if (existing != null && mounted) {
            setState(() {
              _idErrorMessage = 'This ID is already registered. Please use it.';
              _isSubmitting = false;
            });
            _formKey.currentState!.validate();
            return;
          }
        } catch (_) {
          // Ignore lookup errors, let the server handle it
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
      }
    }

    bool isValid = _formKey.currentState!.validate();

    // Only manually validate birthdate if it's visible (not in partial/restricted view)
    if (!_isPartialResult && _selectedBirthdate == null) {
      setState(() {}); // trigger rebuild to show error text
      isValid = false;
    }

    if (!isValid) return;

    if (!mounted) return;

    if (_selectedSymptoms.isEmpty &&
        _customChiefComplaintCtrl.text.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.danger,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Warning'),
            ],
          ),
          content: const Text(
            'Please select at least one symptom or describe your complaint in the "Other Chief Complaints" field.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Build full name: "LAST, FIRST MIDDLE EXT"
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final middleName = _middleNameCtrl.text.trim();
    String ext = '';
    if (_selectedExtension == 'Others') {
      ext = _customExtensionCtrl.text.trim();
    } else if (_selectedExtension != 'None') {
      ext = _selectedExtension;
    }
    final studentName = '$lastName, $firstName $middleName $ext'
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    String finalSex = _selectedSex ?? '';

    // Check connection FIRST
    setState(() => _isSubmitting = true);
    final isConnected = await DesktopConnectionService.instance
        .checkConnection();
    setState(() => _isSubmitting = false);

    if (!isConnected) {
      _showConnectionLostDialog();
      return;
    }

    if (!mounted) return;

    // Show confirmation dialog AFTER connection check
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                color: AppTheme.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Confirm Submission'),
          ],
        ),
        content: const Text(
          'By submitting this form, you agree that the information provided is true and correct.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      await _queueService.addToQueue(
        studentName: studentName,
        studentNumber: _numberCtrl.text.trim(),
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        extension: ext,
        birthdate: _selectedBirthdate,
        sex: finalSex,
        contactNumber: _contactCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        guardianName: _guardianNameCtrl.text.trim(),
        guardianContact: _guardianContactCtrl.text.trim(),
        guardian2Name: _guardian2NameCtrl.text.trim(),
        guardian2Contact: _guardian2ContactCtrl.text.trim(),
        allergicTo: _allergicToCtrl.text.trim(),
        symptoms: _selectedSymptoms.toList(),
        customChiefComplaint: _customChiefComplaintCtrl.text.trim(),
        role: _selectedRole ?? '',
        department: _selectedDepartment ?? '',
        level: _selectedLevel ?? '',
        existingPatientId: PersistentFormService.instance.existingPatientId,
      );

      if (!mounted) return;
      _resetForm();
      Navigator.pushReplacementNamed(context, '/confirmation');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // If the error message indicates a connection issue, show the special dialog
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('connection') || errorMsg.contains('reachable')) {
        _showConnectionLostDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Displays a dialog when the connection to the desktop app is lost.
  void _showConnectionLostDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: AppTheme.danger,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Connection Lost'),
          ],
        ),
        content: const Text(
          'The connection to the clinic desktop app has been lost. Please ensure the tablet is still on the correct Wi-Fi network.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pushReplacementNamed(context, '/scan');
            },
            child: const Text('Reset Connection'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              _submit(); // Retry submission
            },
            child: const Text('Retry Connection'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isMobile ? 70 : 90,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: isMobile ? 50 : 70,
        leading: Center(
          child: IconButton(
            onPressed: () =>
                Navigator.popUntil(context, ModalRoute.withName('/welcome')),
            icon: const Icon(Icons.chevron_left_rounded),
            iconSize: 28,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.cardLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: isMobile ? 32 : 40,
              height: isMobile ? 32 : 40,
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.medical_information_rounded,
                size: isMobile ? 16 : 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Patient & Visit Form',
                style: isMobile
                    ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      )
                    : Theme.of(context).textTheme.headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              // ═══════════════════════════════════════════════════
              //  SECTION 1 — Patient Information
              // ═══════════════════════════════════════════════════
              const _SectionHeader(
                icon: Icons.person_outline_rounded,
                title: 'Personal Information',
              ),
              const SizedBox(height: 16),
              const Text(
                "Fields with asterisks (*) are required to be filled up.",
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),

              // ID Number (At the top now)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: IgnorePointer(
                      ignoring: _isAutofilled,
                      child: TextFormField(
                        controller: _numberCtrl,
                        focusNode: _idFocusNode,
                        readOnly: _isAutofilled,
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
                        prefixIcon: const Icon(Icons.badge_outlined),
                        counterText: '',
                        suffixIcon: _isAutofilling
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _isAutofilled
                                ? const Icon(
                                    Icons.lock_rounded,
                                    size: 18,
                                    color: AppTheme.textMuted,
                                  )
                                : null,
                      ),
                      onFieldSubmitted: (v) => _searchPatient(v),
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(16),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        return _idErrorMessage;
                      },
                    ),
                    ),
                  ),
                  if (_isAutofilled) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              title: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppTheme.danger.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppTheme.danger,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Clear Form?'),
                                ],
                              ),
                              content: const Text(
                                'This will remove all entered data. Are you sure you want to clear the form?',
                              ),
                              actions: [
                                OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.danger,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) _resetForm();
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 14),

              // First Name & Last Name
              Flex(
                direction: ResponsiveLayout.isMobile(context)
                    ? Axis.vertical
                    : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                    child: TextFormField(
                      readOnly: _isPartialResult,
                      controller: _firstNameCtrl,
                      maxLength: 30,
                      decoration: InputDecoration(
                        label: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              const TextSpan(
                                text: 'First Name ',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              const TextSpan(
                                text: '*',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ],
                          ),
                        ),
                        prefixIcon: const Icon(Icons.person_outline),
                        counterText: '',
                      ),
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(30),
                      ],
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  SizedBox(
                    width: ResponsiveLayout.isMobile(context) ? 0 : 12,
                    height: ResponsiveLayout.isMobile(context) ? 14 : 0,
                  ),
                  Expanded(
                    flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                    child: TextFormField(
                      readOnly: _isPartialResult,
                      controller: _lastNameCtrl,
                      maxLength: 30,
                      decoration: InputDecoration(
                        label: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Last Name ',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              const TextSpan(
                                text: '*',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ],
                          ),
                        ),
                        prefixIcon: const Icon(Icons.person_outline),
                        counterText: '',
                      ),
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(30),
                      ],
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Middle Name & Extension
              Flex(
                direction: ResponsiveLayout.isMobile(context)
                    ? Axis.vertical
                    : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: ResponsiveLayout.isMobile(context) ? 0 : 2,
                    child: TextFormField(
                      readOnly: _isPartialResult,
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
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  SizedBox(
                    width: ResponsiveLayout.isMobile(context) ? 0 : 12,
                    height: ResponsiveLayout.isMobile(context) ? 14 : 0,
                  ),
                  if (ResponsiveLayout.isMobile(context))
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildExtensionDropdown()),
                        if (_selectedExtension == 'Others') ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: _buildCustomExtensionField(),
                          ),
                        ],
                      ],
                    )
                  else ...[
                    Expanded(
                      flex: _selectedExtension == 'Others' ? 1 : 2,
                      child: _buildExtensionDropdown(),
                    ),
                    if (_selectedExtension == 'Others') ...[
                      const SizedBox(width: 12),
                      Expanded(flex: 1, child: _buildCustomExtensionField()),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 14),

              if (!_isPartialResult) ...[
                // Role & Department
                Flex(
                  direction: ResponsiveLayout.isMobile(context)
                      ? Axis.vertical
                      : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                      child: _buildRoleDropdown(),
                    ),
                    SizedBox(
                      width: ResponsiveLayout.isMobile(context) ? 0 : 16,
                      height: ResponsiveLayout.isMobile(context) ? 14 : 0,
                    ),
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                      child: _buildDepartmentDropdown(),
                    ),
                  ],
                ),

                if (_selectedRole == 'Student' &&
                    _selectedDepartment != null &&
                    _selectedDepartment != 'General') ...[
                  const SizedBox(height: 14),
                  _buildLevelDropdown(),
                ],
                const SizedBox(height: 14),

                // Birthdate & Sex
                Flex(
                  direction: ResponsiveLayout.isMobile(context)
                      ? Axis.vertical
                      : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                      child: _buildBirthdateField(),
                    ),
                    SizedBox(
                      width: ResponsiveLayout.isMobile(context) ? 0 : 12,
                      height: ResponsiveLayout.isMobile(context) ? 14 : 0,
                    ),
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                      child: _buildSexDropdown(),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

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
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

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
                const SizedBox(height: 14),

                // Guardian 1: Name & Contact
                Flex(
                  direction: ResponsiveLayout.isMobile(context)
                      ? Axis.vertical
                      : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
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
                    SizedBox(
                      width: ResponsiveLayout.isMobile(context) ? 0 : 12,
                      height: ResponsiveLayout.isMobile(context) ? 14 : 0,
                    ),
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                      child: TextFormField(
                        controller: _guardianContactCtrl,
                        maxLength: 20,
                        decoration: const InputDecoration(
                          labelText: 'Parent / Guardian Contact',
                          prefixIcon: Icon(Icons.phone_outlined),
                          counterText: '',
                        ),
                        inputFormatters: [LengthLimitingTextInputFormatter(20)],
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Guardian 2: Name & Contact
                Flex(
                  direction: ResponsiveLayout.isMobile(context)
                      ? Axis.vertical
                      : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
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
                    SizedBox(
                      width: ResponsiveLayout.isMobile(context) ? 0 : 12,
                      height: ResponsiveLayout.isMobile(context) ? 14 : 0,
                    ),
                    Expanded(
                      flex: ResponsiveLayout.isMobile(context) ? 0 : 1,
                      child: TextFormField(
                        controller: _guardian2ContactCtrl,
                        maxLength: 20,
                        decoration: const InputDecoration(
                          labelText: 'Second Guardian Contact',
                          prefixIcon: Icon(Icons.phone_outlined),
                          counterText: '',
                        ),
                        inputFormatters: [LengthLimitingTextInputFormatter(20)],
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Allergic To
                TextFormField(
                  controller: _allergicToCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Allergies',
                    hintText: 'The patient is allergic to...',
                    prefixIcon: Icon(Icons.coronavirus_outlined),
                  ),
                  inputFormatters: [UpperCaseTextFormatter()],
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
                const SizedBox(height: 32),
              ],

              // ═══════════════════════════════════════════════════
              //  SECTION 2 — Chief Complaints / Symptoms
              // ═══════════════════════════════════════════════════
              const _SectionHeader(
                icon: Icons.medical_services_outlined,
                title: 'Chief Complaints / Symptoms',
              ),
              const SizedBox(height: 16),

              // Traumatic
              _buildSymptomSection(
                title: 'Traumatic',
                allItems: kTraumaticSymptoms,
                showAll: _showAllTraumatic,
                onToggle: () =>
                    setState(() => _showAllTraumatic = !_showAllTraumatic),
              ),
              const SizedBox(height: 12),

              // Medical
              _buildSymptomSection(
                title: 'Medical',
                allItems: kMedicalSymptoms,
                showAll: _showAllMedical,
                onToggle: () =>
                    setState(() => _showAllMedical = !_showAllMedical),
              ),
              const SizedBox(height: 12),

              // Behavioral
              _buildSymptomSection(
                title: 'Behavioral',
                allItems: kBehavioralSymptoms,
                showAll: _showAllBehavioral,
                onToggle: () =>
                    setState(() => _showAllBehavioral = !_showAllBehavioral),
              ),

              const SizedBox(height: 16),

              // Custom Chief Complaint Field
              TextFormField(
                controller: _customChiefComplaintCtrl,
                decoration: const InputDecoration(
                  labelText: 'Other Chief Complaints',
                  hintText: 'Enter other symptoms or complaints here...',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
                inputFormatters: [UpperCaseTextFormatter()],
                minLines: 1,
                maxLines: null,
                keyboardType: TextInputType.multiline,
              ),

              const SizedBox(height: 32),

              if (_isPartialResult) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.privacy_tip_outlined,
                        color: AppTheme.accent,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Restricted View',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'In order to view and edit your personal information, you need to request access from the clinic staff.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isRequestingEdit
                            ? null
                            : _requestEditAccess,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          elevation: 0,
                        ),
                        child: const Text('Request Access'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Submit button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit Form'),
                ),
              ),
              const SizedBox(height: 12),
              // ── Clear form button ──────────────────────────────
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        title: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: AppTheme.danger,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text('Clear Form?'),
                          ],
                        ),
                        content: const Text(
                          'This will remove all entered data. Are you sure you want to clear the form?',
                        ),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.danger,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) _resetForm();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Clear Form'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Form Field Builders ───────────────────────────────────────────

  Widget _buildExtensionDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedExtension,
      decoration: const InputDecoration(
        labelText: 'Extension',
        prefixIcon: Icon(Icons.badge_outlined),
      ),
      items: ['None', 'JR.', 'SR.', 'I', 'II', 'III', 'Others'].map((e) {
        return DropdownMenuItem(
          value: e,
          child: Text(e, style: GoogleFonts.inter(fontWeight: FontWeight.w400)),
        );
      }).toList(),
      onChanged: _isPartialResult
          ? null
          : (val) {
              if (val != null) {
                setState(() => _selectedExtension = val);
                PersistentFormService.instance.extension = val;
              }
            },
    );
  }

  Widget _buildCustomExtensionField() {
    return TextFormField(
      readOnly: _isPartialResult,
      controller: _customExtensionCtrl,
      maxLength: 5,
      decoration: const InputDecoration(labelText: 'Specify', counterText: ''),
      inputFormatters: [
        UpperCaseTextFormatter(),
        LengthLimitingTextInputFormatter(5),
      ],
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
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
                style: GoogleFonts.inter(color: AppTheme.textSecondary),
              ),
              const TextSpan(
                text: "*",
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        prefixIcon: const Icon(Icons.work_outline),
      ),
      items: ['Student', 'Employee'].map((r) {
        return DropdownMenuItem(
          value: r,
          child: Text(
            r,
            style: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 14),
          ),
        );
      }).toList(),
      validator: (v) => v == null ? 'Required' : null,
      onChanged: (val) {
        setState(() {
          _selectedRole = val;
          PersistentFormService.instance.role = val ?? '';
          if (val == 'Student' && _selectedDepartment == 'General') {
            _selectedDepartment = null;
            PersistentFormService.instance.department = null;
          }
          if (val != 'Student') {
            _selectedLevel = null;
            PersistentFormService.instance.level = '';
          }
        });
      },
    );
  }

  Widget _buildLevelDropdown() {
    return DropdownButtonFormField<String>(
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
              const TextSpan(
                text: 'Level ',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const TextSpan(
                text: "*",
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        prefixIcon: const Icon(Icons.layers_outlined),
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
            levels = ['First Year', 'Second Year', 'Third Year', 'Fourth Year'];
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
        if (val != null) {
          setState(() => _selectedLevel = val);
          PersistentFormService.instance.level = val;
        }
      },
    );
  }

  Widget _buildDepartmentDropdown() {
    return DropdownButtonFormField<String>(
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
                style: GoogleFonts.inter(color: AppTheme.textSecondary),
              ),
              const TextSpan(
                text: "*",
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        prefixIcon: const Icon(Icons.school_outlined),
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
          PersistentFormService.instance.department = val;
          PersistentFormService.instance.level = '';
        });
      },
    );
  }

  Widget _buildBirthdateField() {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate:
              _selectedBirthdate ?? DateTime(now.year - 18, now.month, now.day),
          firstDate: DateTime(1920),
          lastDate: now,
        );
        if (picked != null) {
          setState(() => _selectedBirthdate = picked);
          PersistentFormService.instance.birthdate = picked;
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          label: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(fontWeight: FontWeight.w400),
              children: [
                const TextSpan(
                  text: 'Birthdate ',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const TextSpan(
                  text: '*',
                  style: TextStyle(color: AppTheme.danger),
                ),
              ],
            ),
          ),
          prefixIcon: const Icon(Icons.cake_outlined),
          errorText: (_hasAttemptedSubmit && _selectedBirthdate == null)
              ? 'Required'
              : null,
        ),
        child: Text(
          _selectedBirthdate != null
              ? DateFormat('MMM dd, yyyy').format(_selectedBirthdate!)
              : 'Select Date',
          style: TextStyle(
            color: _selectedBirthdate != null
                ? AppTheme.textPrimary
                : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildSexDropdown() {
    return DropdownButtonFormField<String>(
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
              const TextSpan(
                text: 'Sex ',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const TextSpan(
                text: '*',
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        prefixIcon: const Icon(Icons.wc_outlined),
        errorText: (_hasAttemptedSubmit && _selectedSex == null)
            ? 'Required'
            : null,
      ),
      items: ['Male', 'Female', 'Intersex'].map((s) {
        return DropdownMenuItem(
          value: s,
          child: Text(s, style: GoogleFonts.inter(fontWeight: FontWeight.w400)),
        );
      }).toList(),
      validator: (v) => v == null ? 'Required' : null,
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedSex = val);
          PersistentFormService.instance.sex = val;
        }
      },
    );
  }

  // ── Symptom category section (adapted from desktop visitation form) ──
  Widget _buildSymptomSection({
    required String title,
    required List<String> allItems,
    required bool showAll,
    required VoidCallback onToggle,
  }) {
    final displayItems = showAll
        ? allItems
        : allItems.where((item) => _selectedSymptoms.contains(item)).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: AppTheme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              TextButton(
                onPressed: onToggle,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  showAll ? 'Hide Options' : 'Show Options',
                  style: const TextStyle(fontSize: 12, color: AppTheme.accent),
                ),
              ),
            ],
          ),
          if (displayItems.isNotEmpty) const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: displayItems.map((symptom) {
              final isSelected = _selectedSymptoms.contains(symptom);
              return FilterChip(
                showCheckmark: false,
                label: Text(
                  symptom,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSymptoms.add(symptom);
                      PersistentFormService.instance.addSymptom(symptom);
                    } else {
                      _selectedSymptoms.remove(symptom);
                      PersistentFormService.instance.removeSymptom(symptom);
                    }
                  });
                },
                selectedColor: AppTheme.accent,
                backgroundColor: AppTheme.cardLight,
                side: BorderSide(
                  color: isSelected ? AppTheme.accent : AppTheme.dividerColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Section header widget ────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.08),
            AppTheme.accent.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppTheme.accent),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppTheme.accentDim),
          ),
        ],
      ),
    );
  }
}
