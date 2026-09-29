import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../constants/symptoms.dart';
import '../providers/inventory_provider.dart';
import '../providers/custom_symptom_provider.dart';
import '../models/inventory_item.dart';
import '../models/custom_symptom.dart';
import '../theme/app_theme.dart';

import '../models/patient.dart';
import '../models/visitation.dart';
import '../providers/patient_provider.dart';
import 'patient_form_screen.dart';
import '../services/database_helper.dart';

class VisitationFormScreen extends StatefulWidget {
  final String? patientId;
  final Visitation? visitation;
  final bool hideChiefComplaintOptions;

  const VisitationFormScreen({
    super.key,
    this.patientId,
    this.visitation,
    this.hideChiefComplaintOptions = false,
  });

  @override
  State<VisitationFormScreen> createState() => _VisitationFormScreenState();
}

class _VisitationFormScreenState extends State<VisitationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _treatmentCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final _customChiefComplaintCtrl = TextEditingController();
  final _customInterventionCtrl = TextEditingController();
  final Set<String> _selectedSymptoms = {};

  static const List<String> _builtInInterventions = [
    'Sent home',
    'Rested in clinic',
    'Given medication',
    'Wound cleaned and dressed',
    'Referred to hospital',
    'Observation',
    'First aid given',
    'Warm compress',
    'Cold compress',
    'Topical/ointment given',
  ];
  final Set<String> _selectedSupplies = {};
  final Set<String> _fullyConsumedSupplies = {};

  Patient? _selectedPatient;
  bool _isLoadingPatient = false;

  bool _showAllTraumatic = true;
  bool _showAllMedical = true;
  bool _showAllBehavioral = true;
  bool _showAllSupplies = true;

  // ── Pagination ─────────────────────────────────────────────────
  static const int _pageSize = 20;
  Timer? _searchDebounce;

  // Symptom pagination state per category
  final Map<String, int> _symptomPage = {
    'traumatic': 0,
    'medical': 0,
    'behavioral': 0,
  };
  final Map<String, String> _symptomSearchQuery = {
    'traumatic': '',
    'medical': '',
    'behavioral': '',
  };
  final Map<String, int> _symptomTotalCount = {
    'traumatic': 0,
    'medical': 0,
    'behavioral': 0,
  };
  final Map<String, int> _symptomUnfilteredCount = {
    'traumatic': 0,
    'medical': 0,
    'behavioral': 0,
  };
  final Map<String, List<String>> _symptomBuiltInOnPage = {
    'traumatic': [],
    'medical': [],
    'behavioral': [],
  };
  final Map<String, List<CustomSymptom>> _symptomCustomOnPage = {
    'traumatic': [],
    'medical': [],
    'behavioral': [],
  };
  final Map<String, TextEditingController> _symptomSearchCtrls = {};

  // Supply pagination state per clinic group
  List<String> _clinicGroups = [];
  final Map<String, int> _supplyPage = {};
  final Map<String, String> _supplySearchQuery = {};
  final Map<String, int> _supplyTotalCount = {};
  final Map<String, int> _supplyUnfilteredCount = {};
  final Map<String, List<InventoryItem>> _supplyPageItems = {};
  final Map<String, TextEditingController> _supplySearchCtrls = {};
  bool _suppliesInitialized = false;

  @override
  void initState() {
    super.initState();

    if (widget.hideChiefComplaintOptions) {
      _showAllTraumatic = false;
      _showAllMedical = false;
      _showAllBehavioral = false;
    }

    if (widget.visitation != null) {
      _treatmentCtrl.text = widget.visitation!.treatment;
      _remarksCtrl.text = widget.visitation!.remarks;
      _selectedSymptoms.addAll(widget.visitation!.symptoms);
      _selectedSupplies.addAll(widget.visitation!.suppliesUsed);
      _fullyConsumedSupplies.addAll(widget.visitation!.consumedSupplies);
      _customChiefComplaintCtrl.text = widget.visitation!.customChiefComplaint;
    }

    final pId = widget.visitation?.patientId ?? widget.patientId;
    if (pId != null) {
      final provider = context.read<PatientProvider>();
      if (provider.selectedPatient?.id == pId) {
        _selectedPatient = provider.selectedPatient;
      } else {
        try {
          _selectedPatient = provider.patients.firstWhere((p) => p.id == pId);
        } catch (_) {
          _isLoadingPatient = true;
          DatabaseHelper.instance.getPatient(pId).then((p) {
            if (mounted) {
              setState(() {
                _selectedPatient = p;
                _isLoadingPatient = false;
              });
            }
          });
        }
      }
    }

    // Initialize symptom search controllers
    for (final cat in ['traumatic', 'medical', 'behavioral']) {
      _symptomSearchCtrls[cat] = TextEditingController();
    }

    // Load initial pages
    _loadAllSymptomPages();
    _loadClinicsAndSupplies();
  }

  @override
  void dispose() {
    _treatmentCtrl.dispose();
    _remarksCtrl.dispose();
    _customChiefComplaintCtrl.dispose();
    _customInterventionCtrl.dispose();
    _searchDebounce?.cancel();
    for (final ctrl in _symptomSearchCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _supplySearchCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // ── Symptom Helpers ────────────────────────────────────────────

  List<String> _getBuiltInSymptoms(String category) {
    switch (category) {
      case 'traumatic':
        return kTraumaticSymptoms;
      case 'medical':
        return kMedicalSymptoms;
      case 'behavioral':
        return kBehavioralSymptoms;
      default:
        return [];
    }
  }

  bool _getShowAll(String category) {
    switch (category) {
      case 'traumatic':
        return _showAllTraumatic;
      case 'medical':
        return _showAllMedical;
      case 'behavioral':
        return _showAllBehavioral;
      default:
        return true;
    }
  }

  void _toggleShowAll(String category) {
    setState(() {
      switch (category) {
        case 'traumatic':
          _showAllTraumatic = !_showAllTraumatic;
          break;
        case 'medical':
          _showAllMedical = !_showAllMedical;
          break;
        case 'behavioral':
          _showAllBehavioral = !_showAllBehavioral;
          break;
      }
    });
    if (_getShowAll(category)) {
      _loadSymptomPage(category);
    } else {
      // Clear search and reset pagination when collapsing
      _symptomSearchCtrls[category]?.clear();
      _symptomSearchQuery[category] = '';
      _symptomPage[category] = 0;
    }
  }

  void _toggleShowAllSupplies() {
    setState(() {
      _showAllSupplies = !_showAllSupplies;
    });
    if (_showAllSupplies) {
      for (final clinic in _clinicGroups) {
        _loadSupplyPage(clinic);
      }
    } else {
      // Clear search and reset pagination when collapsing
      for (final clinic in _clinicGroups) {
        _supplySearchCtrls[clinic]?.clear();
        _supplySearchQuery[clinic] = '';
        _supplyPage[clinic] = 0;
      }
    }
  }

  // ── Symptom Pagination ─────────────────────────────────────────

  Future<void> _loadAllSymptomPages() async {
    for (final cat in ['traumatic', 'medical', 'behavioral']) {
      await _loadSymptomPage(cat);
    }
  }

  Future<void> _loadSymptomPage(String category) async {
    final search = _symptomSearchQuery[category] ?? '';
    final page = _symptomPage[category] ?? 0;

    // Filter built-in symptoms by search
    final builtIn = _getBuiltInSymptoms(category);
    final filteredBuiltIn = search.isEmpty
        ? List<String>.from(builtIn)
        : builtIn
              .where((s) => s.toLowerCase().contains(search.toLowerCase()))
              .toList();
    filteredBuiltIn.sort(
      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );

    // Get total custom count from DB
    final customCount = await DatabaseHelper.instance.getCustomSymptomCount(
      category,
      query: search,
    );
    final totalCount = filteredBuiltIn.length + customCount;

    final unfilteredCustomCount = await DatabaseHelper.instance.getCustomSymptomCount(
      category,
      query: '',
    );
    final unfilteredTotal = builtIn.length + unfilteredCustomCount;

    // Calculate what to show on this page
    final startIndex = page * _pageSize;

    List<String> builtInOnPage = [];
    int customOffset = 0;
    int customLimit = _pageSize;

    if (startIndex < filteredBuiltIn.length) {
      // Some built-in items appear on this page
      final builtInEnd =
          (startIndex + _pageSize).clamp(0, filteredBuiltIn.length);
      builtInOnPage = filteredBuiltIn.sublist(startIndex, builtInEnd);
      customOffset = 0;
      customLimit = _pageSize - builtInOnPage.length;
    } else {
      // Only custom items on this page
      customOffset = startIndex - filteredBuiltIn.length;
    }

    // Fetch custom symptoms from DB with LIMIT/OFFSET
    List<CustomSymptom> customOnPage = [];
    if (customLimit > 0) {
      customOnPage =
          await DatabaseHelper.instance.getCustomSymptomsPaginated(
        category: category,
        limit: customLimit,
        offset: customOffset,
        query: search,
      );
    }

    if (mounted) {
      setState(() {
        _symptomTotalCount[category] = totalCount;
        _symptomUnfilteredCount[category] = unfilteredTotal;
        _symptomBuiltInOnPage[category] = builtInOnPage;
        _symptomCustomOnPage[category] = customOnPage;
      });
    }
  }

  void _onSymptomSearchChanged(String category, String query) {
    _symptomSearchQuery[category] = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _symptomPage[category] = 0;
      _loadSymptomPage(category);
    });
  }

  void _onSymptomPageChanged(String category, int page) {
    _symptomPage[category] = page;
    _loadSymptomPage(category);
  }

  // ── Supply Pagination ──────────────────────────────────────────

  Future<void> _loadClinicsAndSupplies() async {
    final clinics = await DatabaseHelper.instance.getDistinctClinics();

    for (final clinic in clinics) {
      _supplyPage.putIfAbsent(clinic, () => 0);
      _supplySearchQuery.putIfAbsent(clinic, () => '');
      _supplySearchCtrls.putIfAbsent(clinic, () => TextEditingController());
    }

    _clinicGroups = clinics;

    for (final clinic in clinics) {
      await _loadSupplyPage(clinic);
    }

    if (mounted) {
      setState(() {
        _suppliesInitialized = true;
      });
    }
  }

  Future<void> _loadSupplyPage(String clinic) async {
    final search = _supplySearchQuery[clinic] ?? '';
    final page = _supplyPage[clinic] ?? 0;

    final totalCount = await DatabaseHelper.instance.getInventoryCountByClinic(
      clinic,
      query: search,
    );

    final unfilteredCount = await DatabaseHelper.instance.getInventoryCountByClinic(
      clinic,
      query: '',
    );

    final items = await DatabaseHelper.instance.getInventoryByClinicPaginated(
      clinic: clinic,
      limit: _pageSize,
      offset: page * _pageSize,
      query: search,
    );

    if (mounted) {
      setState(() {
        _supplyTotalCount[clinic] = totalCount;
        _supplyUnfilteredCount[clinic] = unfilteredCount;
        _supplyPageItems[clinic] = items;
      });
    }
  }

  void _onSupplySearchChanged(String clinic, String query) {
    _supplySearchQuery[clinic] = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _supplyPage[clinic] = 0;
      _loadSupplyPage(clinic);
    });
  }

  void _onSupplyPageChanged(String clinic, int page) {
    _supplyPage[clinic] = page;
    _loadSupplyPage(clinic);
  }

  // ── Selected Helpers ───────────────────────────────────────────

  List<String> _getSelectedSymptomsForCategory(
    String category,
    CustomSymptomProvider customProvider,
  ) {
    final builtIn = _getBuiltInSymptoms(category);
    List<CustomSymptom> customList;
    switch (category) {
      case 'traumatic':
        customList = customProvider.traumaticSymptoms;
        break;
      case 'medical':
        customList = customProvider.medicalSymptoms;
        break;
      case 'behavioral':
        customList = customProvider.behavioralSymptoms;
        break;
      default:
        customList = [];
    }

    final result = <String>[];
    result.addAll(builtIn.where((s) => _selectedSymptoms.contains(s)));
    result.addAll(
      customList
          .where((s) => _selectedSymptoms.contains(s.name))
          .map((s) => s.name),
    );
    return result;
  }

  // ── Save ───────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a patient'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    if (_selectedSymptoms.isEmpty &&
        _customChiefComplaintCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least one symptom or enter a custom chief complaint',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final inventoryProvider = context.read<InventoryProvider>();

    // Transform selected supplies to ID:Name format for snapshotting
    final mappedSupplies = _selectedSupplies.map((supplyIdOrLegacy) {
      try {
        final item = inventoryProvider.allItems.firstWhere(
          (i) => i.id == supplyIdOrLegacy || i.itemName == supplyIdOrLegacy,
        );
        return "${item.id}:${item.itemName}";
      } catch (_) {
        return supplyIdOrLegacy;
      }
    }).toList();

    final consumedSupplies = mappedSupplies.where((supplyStr) {
      try {
        final idPart = supplyStr.contains(':')
            ? supplyStr.split(':')[0]
            : supplyStr;
        final item = inventoryProvider.allItems.firstWhere(
          (i) => i.id == idPart || i.itemName == idPart,
        );
        return item.itemType == 'piece' ||
            _fullyConsumedSupplies.contains(item.id) ||
            _fullyConsumedSupplies.contains(item.itemName);
      } catch (e) {
        return true; // Fallback context
      }
    }).toList();

    if (widget.visitation != null) {
      final updated = widget.visitation!.copyWith(
        symptoms: _selectedSymptoms.toList(),
        suppliesUsed: mappedSupplies,
        consumedSupplies: consumedSupplies,
        treatment: _treatmentCtrl.text.trim(),
        remarks: _remarksCtrl.text.trim(),
        customChiefComplaint: _customChiefComplaintCtrl.text.trim(),
      );
      await context.read<PatientProvider>().updateVisitation(updated);
    } else {
      await context.read<PatientProvider>().addVisitation(
        patientId: _selectedPatient!.id,
        symptoms: _selectedSymptoms.toList(),
        suppliesUsed: mappedSupplies,
        consumedSupplies: consumedSupplies,
        treatment: _treatmentCtrl.text.trim(),
        remarks: _remarksCtrl.text.trim(),
        customChiefComplaint: _customChiefComplaintCtrl.text.trim(),
      );
    }

    if (mounted) Navigator.pop(context);
  }

  // ── Custom Symptom Dialogs ─────────────────────────────────────

  void _showAddCustomSymptomDialog(String category) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Add Custom ${category[0].toUpperCase()}${category.substring(1)} Symptom',
        ),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Symptom Name'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                context.read<CustomSymptomProvider>().addCustomSymptom(
                  name,
                  category,
                );
                setState(() {
                  _selectedSymptoms.add(name);
                });
                Navigator.pop(ctx);
                // Reload page to reflect the new custom symptom
                _loadSymptomPage(category);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCustomSymptom(
    String id,
    String name,
    String category,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Custom Symptom'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _selectedSymptoms.remove(name);
              });
              await context
                  .read<CustomSymptomProvider>()
                  .deleteCustomSymptom(id);
              _loadSymptomPage(category);
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

  void _addCustomIntervention(
    BuildContext context,
    CustomSymptomProvider provider,
  ) {
    final text = _customInterventionCtrl.text.trim();
    if (text.isEmpty) return;

    final lowerText = text.toLowerCase();
    final existsInBuiltIn = _builtInInterventions.any(
      (element) => element.toLowerCase() == lowerText,
    );
    final existsInCustom = provider.interventionSymptoms.any(
      (element) => element.name.toLowerCase() == lowerText,
    );

    if (existsInBuiltIn || existsInCustom) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Intervention chip already exists'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    provider.addCustomSymptom(text, 'intervention');
    _customInterventionCtrl.clear();
  }

  void _confirmDeleteCustomIntervention(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Custom Quick Intervention'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context
                  .read<CustomSymptomProvider>()
                  .deleteCustomSymptom(id);
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

  Widget _buildInterventionChip(
    String text, {
    required bool isCustom,
    String? id,
  }) {
    Widget chip = ActionChip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
      padding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(
          color: AppTheme.accent,
        ),
      ),
      onPressed: () {
        final ctrl = _treatmentCtrl;
        final currentText = ctrl.text.trim();
        if (currentText.isEmpty) {
          ctrl.text = text;
        } else {
          if (currentText.endsWith(',')) {
            ctrl.text = '$currentText $text';
          } else {
            ctrl.text = '$currentText, $text';
          }
        }
        ctrl.selection = TextSelection.collapsed(
          offset: ctrl.text.length,
        );
      },
    );

    if (isCustom && id != null) {
      chip = Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => _confirmDeleteCustomIntervention(id, text),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.danger, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.remove,
                  size: 12,
                  color: AppTheme.danger,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return chip;
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPatient) {
      return const Dialog(
        child: SizedBox(
          width: 600,
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Dialog(
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
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
                    Icons.medical_services_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.visitation != null
                      ? 'Edit Visitation'
                      : 'Record Visitation',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Scrollable Form Area
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
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
                      // Patient Search (Autocomplete)
                      Autocomplete<Patient>(
                        initialValue: TextEditingValue(
                          text: _selectedPatient?.patientName ?? '',
                        ),
                        displayStringForOption: (option) => option.patientName,
                        optionsBuilder: (textEditingValue) async {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Patient>.empty();
                          }
                          final query = textEditingValue.text;
                          return await DatabaseHelper.instance
                              .searchPatientsPaginated(
                                query: query,
                                limit: 10, // top 10 matches
                                offset: 0, // offset 0
                              );
                        },
                        onSelected: (selection) {
                          setState(() {
                            _selectedPatient = selection;
                          });
                        },
                        fieldViewBuilder:
                            (
                              context,
                              controller,
                              focusNode,
                              onEditingComplete,
                            ) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      readOnly: widget.patientId != null,
                                      decoration: InputDecoration(
                                        label: RichText(
                                          text: TextSpan(
                                            text: 'Patient Name / ID Number ',
                                            style: GoogleFonts.inter(
                                              color: AppTheme.textPrimary,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: '*',
                                                style: GoogleFonts.inter(
                                                  color: AppTheme.danger,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        prefixIcon: Icon(
                                          Icons.person_search_rounded,
                                        ),
                                      ),
                                      onEditingComplete: onEditingComplete,
                                    ),
                                  ),
                                  if (widget.patientId == null &&
                                      _selectedPatient == null) ...[
                                    const SizedBox(width: 16),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final newPatient =
                                            await showDialog<Patient>(
                                              context: context,
                                              builder: (_) =>
                                                  const PatientFormScreen(),
                                            );
                                        if (newPatient != null && mounted) {
                                          setState(() {
                                            _selectedPatient = newPatient;
                                          });
                                          controller.text =
                                              newPatient.patientName;
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.accent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.all(16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.person_add_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Add Patient'),
                                    ),
                                  ],
                                ],
                              );
                            },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 400,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return Builder(
                                      builder: (context) {
                                        final bool highlight =
                                            AutocompleteHighlightedOption.of(
                                              context,
                                            ) ==
                                            index;
                                        if (highlight) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (context.mounted) {
                                                  Scrollable.ensureVisible(
                                                    context,
                                                    alignment: 0.5,
                                                  );
                                                }
                                              });
                                        }
                                        return Container(
                                          color: highlight
                                              ? AppTheme.accent.withValues(
                                                  alpha: 0.1,
                                                )
                                              : Colors.transparent,
                                          child: ListTile(
                                            title: Text(option.patientName),
                                            subtitle: Text(option.idNumber),
                                            onTap: () => onSelected(option),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_selectedPatient != null) ...[
                        const SizedBox(height: 24),
                        // Symptoms label
                        RichText(
                          text: TextSpan(
                            text: 'Chief Complaints / Symptoms ',
                            style: Theme.of(context).textTheme.titleMedium,
                            children: [
                              TextSpan(
                                text: '*',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Consumer<CustomSymptomProvider>(
                          builder: (context, customSymptomProvider, _) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSymptomSection(
                                  title: 'Traumatic',
                                  category: 'traumatic',
                                  customProvider: customSymptomProvider,
                                ),
                                const SizedBox(height: 12),
                                _buildSymptomSection(
                                  title: 'Medical',
                                  category: 'medical',
                                  customProvider: customSymptomProvider,
                                ),
                                const SizedBox(height: 12),
                                _buildSymptomSection(
                                  title: 'Behavioral',
                                  category: 'behavioral',
                                  customProvider: customSymptomProvider,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customChiefComplaintCtrl,
                          maxLength: 150,
                          decoration: const InputDecoration(
                            labelText: 'Other Chief Complaint',
                            hintText: 'Enter any complaint not listed above',
                            prefixIcon: Icon(Icons.edit_note_rounded),
                            counterText: '',
                          ),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(150),
                          ],
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                        ),
                        const SizedBox(height: 10),
                        const Divider(),
                        const SizedBox(height: 10),
                        // Interventions
                        Text(
                          'Interventions',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),

                        Consumer<InventoryProvider>(
                          builder: (context, inventory, _) {
                            return _buildSuppliesSection(
                              selectedItems: _selectedSupplies,
                              inventoryProvider: inventory,
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Treatment
                        TextFormField(
                          controller: _treatmentCtrl,
                          maxLength: 150,
                          decoration: const InputDecoration(
                            labelText: 'Other Intervention Details',
                            prefixIcon: Icon(Icons.healing_outlined),
                            counterText: '',
                          ),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(150),
                          ],
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Consumer<CustomSymptomProvider>(
                            builder: (context, customSymptomProvider, _) {
                              final customInterventions =
                                  customSymptomProvider.interventionSymptoms;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ..._builtInInterventions.map(
                                        (text) => _buildInterventionChip(
                                          text,
                                          isCustom: false,
                                        ),
                                      ),
                                      ...customInterventions.map(
                                        (symptom) => _buildInterventionChip(
                                          symptom.name,
                                          isCustom: true,
                                          id: symptom.id,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _customInterventionCtrl,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Add Custom Quick Intervention',
                                            hintText:
                                                'Type and press enter or click +',
                                            prefixIcon:
                                                Icon(Icons.add_task_rounded),
                                            isDense: true,
                                          ),
                                          onSubmitted: (value) {
                                            _addCustomIntervention(
                                              context,
                                              customSymptomProvider,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle,
                                          color: AppTheme.accent,
                                        ),
                                        onPressed: () {
                                          _addCustomIntervention(
                                            context,
                                            customSymptomProvider,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // Remarks
                        TextFormField(
                          controller: _remarksCtrl,
                          maxLength: 150,
                          decoration: const InputDecoration(
                            labelText: 'Remarks',
                            prefixIcon: Icon(Icons.notes_outlined),
                            counterText: '',
                          ),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(150),
                          ],
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                        ),
                        const SizedBox(height: 28),

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
                              child: const Text('Save Visit'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Symptom Section Builder ────────────────────────────────────

  Widget _buildSymptomSection({
    required String title,
    required String category,
    required CustomSymptomProvider customProvider,
  }) {
    final showAll = _getShowAll(category);
    final totalCount = _symptomTotalCount[category] ?? 0;
    final unfilteredCount = _symptomUnfilteredCount[category] ?? 0;
    final currentPage = _symptomPage[category] ?? 0;
    final totalPages = totalCount > 0 ? (totalCount / _pageSize).ceil() : 1;
    final needsPagination = totalCount > _pageSize;
    final showSearchBar = unfilteredCount > _pageSize;

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
              Builder(
                builder: (context) {
                  final selectedCount = _getSelectedSymptomsForCategory(category, customProvider).length;
                  return Text(
                    selectedCount > 0 ? '$title ($selectedCount)' : title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  );
                }
              ),
              TextButton(
                onPressed: () => _toggleShowAll(category),
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
                  style: TextStyle(fontSize: 12, color: AppTheme.accent),
                ),
              ),
            ],
          ),
          if (showAll) ...[
            if (showSearchBar) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _symptomSearchCtrls[category],
                decoration: InputDecoration(
                  hintText: 'Search $title symptoms...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon:
                      (_symptomSearchQuery[category] ?? '').isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _symptomSearchCtrls[category]!.clear();
                                _onSymptomSearchChanged(category, '');
                              },
                            )
                          : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (q) => _onSymptomSearchChanged(category, q),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Built-in symptoms on this page
                ...(_symptomBuiltInOnPage[category] ?? []).map(
                  (name) => _buildSymptomChip(
                    name: name,
                    isCustom: false,
                  ),
                ),
                // Custom symptoms on this page
                ...(_symptomCustomOnPage[category] ?? []).map(
                  (symptom) => _buildSymptomChip(
                    name: symptom.name,
                    isCustom: true,
                    customSymptomId: symptom.id,
                    category: category,
                  ),
                ),
                // Add custom symptom button
                ActionChip(
                  label: const Text('Add', style: TextStyle(fontSize: 13)),
                  avatar: const Icon(Icons.add, size: 16),
                  onPressed: () => _showAddCustomSymptomDialog(category),
                  backgroundColor: AppTheme.cardLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: AppTheme.dividerColor),
                ),
              ],
            ),
            if (needsPagination)
              _buildPaginationControls(
                currentPage: currentPage,
                totalPages: totalPages,
                onPageChanged: (p) => _onSymptomPageChanged(category, p),
              ),
          ] else ...[
            // Collapsed: show only selected items for this category
            Builder(
              builder: (context) {
                final selected = _getSelectedSymptomsForCategory(
                  category,
                  customProvider,
                );
                if (selected.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selected
                        .map(
                          (name) => _buildSymptomChip(
                            name: name,
                            isCustom: !_getBuiltInSymptoms(category)
                                .contains(name),
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ── Supplies Section Builder ───────────────────────────────────

  Widget _buildSuppliesSection({
    required Set<String> selectedItems,
    required InventoryProvider inventoryProvider,
  }) {
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
                selectedItems.isNotEmpty
                    ? 'Clinic Supplies Used (${selectedItems.length})'
                    : 'Clinic Supplies Used',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              TextButton(
                onPressed: _toggleShowAllSupplies,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _showAllSupplies ? 'Hide Options' : 'Show Options',
                  style: TextStyle(fontSize: 12, color: AppTheme.accent),
                ),
              ),
            ],
          ),
          if (_showAllSupplies) ...[
            if (!_suppliesInitialized)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              ..._clinicGroups.map(
                (clinic) => _buildClinicGroup(clinic, selectedItems, inventoryProvider),
              ),
          ] else ...[
            _buildCollapsedSupplies(selectedItems, inventoryProvider),
          ],
        ],
      ),
    );
  }

  Widget _buildClinicGroup(
    String clinic,
    Set<String> selectedItems,
    InventoryProvider inventoryProvider,
  ) {
    final totalCount = _supplyTotalCount[clinic] ?? 0;
    final unfilteredCount = _supplyUnfilteredCount[clinic] ?? 0;
    final currentPage = _supplyPage[clinic] ?? 0;
    final totalPages = totalCount > 0 ? (totalCount / _pageSize).ceil() : 1;
    final needsPagination = totalCount > _pageSize;
    final showSearchBar = unfilteredCount > _pageSize;
    final items = _supplyPageItems[clinic] ?? [];
    final displayClinic = clinic.isEmpty ? 'Other' : clinic;

    final selectedCount = inventoryProvider.allItems
        .where((item) =>
            item.clinic == clinic &&
            (selectedItems.contains(item.id) || selectedItems.contains(item.itemName)))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            selectedCount > 0 ? '$displayClinic ($selectedCount)' : displayClinic,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (showSearchBar) ...[
          TextField(
            controller: _supplySearchCtrls[clinic],
            decoration: InputDecoration(
              hintText: 'Search $displayClinic supplies...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: (_supplySearchQuery[clinic] ?? '').isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _supplySearchCtrls[clinic]!.clear();
                        _onSupplySearchChanged(clinic, '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (q) => _onSupplySearchChanged(clinic, q),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => _buildItemChip(
                  item: item,
                  isSupplies: true,
                  selectedItems: selectedItems,
                  accentColor: AppTheme.accent,
                ),
              )
              .toList(),
        ),
        if (needsPagination)
          _buildPaginationControls(
            currentPage: currentPage,
            totalPages: totalPages,
            onPageChanged: (p) => _onSupplyPageChanged(clinic, p),
          ),
        if (clinic != _clinicGroups.last) const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCollapsedSupplies(
    Set<String> selectedItems,
    InventoryProvider inventoryProvider,
  ) {
    final selectedInvItems = inventoryProvider.allItems
        .where(
          (item) =>
              selectedItems.contains(item.id) ||
              selectedItems.contains(item.itemName),
        )
        .toList();

    if (selectedInvItems.isEmpty) return const SizedBox.shrink();

    // Group by clinic
    final groups = <String, List<InventoryItem>>{};
    for (final item in selectedInvItems) {
      final c = item.clinic.isEmpty ? 'Other' : item.clinic;
      groups.putIfAbsent(c, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                '${entry.key} (${entry.value.length})',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value
                  .map(
                    (item) => _buildItemChip(
                      item: item,
                      isSupplies: true,
                      selectedItems: selectedItems,
                      accentColor: AppTheme.accent,
                    ),
                  )
                  .toList(),
            ),
            if (entry.key != groups.keys.last) const SizedBox(height: 12),
          ],
        );
      }).toList(),
    );
  }

  // ── Symptom Chip Builder ───────────────────────────────────────

  Widget _buildSymptomChip({
    required String name,
    required bool isCustom,
    String? customSymptomId,
    String? category,
  }) {
    final isSelected = _selectedSymptoms.contains(name);

    Widget chip = FilterChip(
      showCheckmark: false,
      label: Text(
        name,
        style: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: isSelected,
      onSelected: (sel) {
        setState(() {
          if (sel) {
            _selectedSymptoms.add(name);
          } else {
            _selectedSymptoms.remove(name);
          }
        });
      },
      selectedColor: AppTheme.accent,
      backgroundColor: AppTheme.cardLight,
      side: BorderSide(
        color: isSelected ? AppTheme.accent : AppTheme.dividerColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    // Show delete badge on custom symptoms (only in expanded view with id+category)
    if (isCustom && customSymptomId != null && category != null) {
      chip = Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => _confirmDeleteCustomSymptom(
                customSymptomId,
                name,
                category,
              ),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.danger, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.remove,
                  size: 12,
                  color: AppTheme.danger,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return chip;
  }

  // ── Pagination Controls ────────────────────────────────────────

  Widget _buildPaginationControls({
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onPageChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: currentPage > 0
                ? () => onPageChanged(currentPage - 1)
                : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Page ${currentPage + 1} of $totalPages',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: currentPage < totalPages - 1
                ? () => onPageChanged(currentPage + 1)
                : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ── Item Chip (Supplies) ───────────────────────────────────────

  Widget _buildItemChip({
    required dynamic item,
    required bool isSupplies,
    required Set<String> selectedItems,
    required Color accentColor,
  }) {
    final String name = isSupplies
        ? (item as InventoryItem).itemName
        : item as String;
    final String id = isSupplies ? (item as InventoryItem).id : name;
    final isSelected =
        selectedItems.contains(id) || selectedItems.contains(name);
    final bool isOutOfStock =
        isSupplies && (item as InventoryItem).quantity == 0;
    final bool isDisabled = isOutOfStock && !isSelected;

    Widget chipLabel = Text(
      isSupplies ? '$name (${(item as InventoryItem).quantity})' : name,
      style: TextStyle(
        color: isDisabled
            ? AppTheme.textMuted
            : isSelected
            ? Colors.white
            : AppTheme.textSecondary,
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    Widget chip = FilterChip(
      showCheckmark: false,
      label: chipLabel,
      selected: isSelected,
      onSelected: isDisabled
          ? null
          : (sel) {
              setState(() {
                if (sel) {
                  selectedItems.add(id);
                } else {
                  selectedItems.remove(id);
                  selectedItems.remove(name); // Legacy cleanup
                }
              });
            },
      selectedColor: accentColor,
      backgroundColor: isDisabled
          ? AppTheme.cardLight.withValues(alpha: 0.5)
          : AppTheme.cardLight,
      disabledColor: AppTheme.cardLight.withValues(alpha: 0.5),
      side: BorderSide(
        color: isDisabled
            ? AppTheme.dividerColor.withValues(alpha: 0.5)
            : isSelected
            ? accentColor
            : AppTheme.dividerColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    if (isSupplies && (item as InventoryItem).isLowStock) {
      chip = Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.yellow,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.priority_high_rounded,
                size: 10,
                color: Colors.black,
              ),
            ),
          ),
        ],
      );
    }

    // Multi-use item types that need a "fully consumed?" checkbox
    const multiUseTypes = {'bottle', 'roll', 'box', 'pack', 'pair', 'set'};

    if (isSupplies &&
        isSelected &&
        multiUseTypes.contains((item as InventoryItem).itemType)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          const SizedBox(width: 4),
          Container(
            height: 32,
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppTheme.cardLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value:
                      _fullyConsumedSupplies.contains(id) ||
                      _fullyConsumedSupplies.contains(name),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _fullyConsumedSupplies.add(id);
                      } else {
                        _fullyConsumedSupplies.remove(id);
                        _fullyConsumedSupplies.remove(name); // Legacy cleanup
                      }
                    });
                  },
                  activeColor: AppTheme.danger,
                  visualDensity: VisualDensity.compact,
                ),
                const Text('Fully consumed?', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      );
    }

    return chip;
  }
}
