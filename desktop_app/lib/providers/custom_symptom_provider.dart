import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/custom_symptom.dart';
import '../services/database_helper.dart';
import '../crdt/hlc.dart';
import '../crdt/node_id.dart';

class CustomSymptomProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<CustomSymptom> _traumaticSymptoms = [];
  List<CustomSymptom> _medicalSymptoms = [];
  List<CustomSymptom> _behavioralSymptoms = [];
  List<CustomSymptom> _interventionSymptoms = [];

  List<CustomSymptom> get traumaticSymptoms => _traumaticSymptoms;
  List<CustomSymptom> get medicalSymptoms => _medicalSymptoms;
  List<CustomSymptom> get behavioralSymptoms => _behavioralSymptoms;
  List<CustomSymptom> get interventionSymptoms => _interventionSymptoms;

  // Called to push changes after local write
  Future<void> Function()? onLocalChange;

  Future<void> loadSymptoms() async {
    final all = await _db.getAllCustomSymptoms();
    
    _traumaticSymptoms = all.where((s) => s.category == 'traumatic').toList();
    _medicalSymptoms = all.where((s) => s.category == 'medical').toList();
    _behavioralSymptoms = all.where((s) => s.category == 'behavioral').toList();
    _interventionSymptoms = all.where((s) => s.category == 'intervention').toList();
    
    notifyListeners();
  }

  Future<void> addCustomSymptom(String name, String category) async {
    final nodeId = await NodeId.get();
    final hlc = HLC.now(nodeId).pack();
    
    final symptom = CustomSymptom(
      id: const Uuid().v4(),
      name: name,
      category: category,
      hlc: hlc,
      nodeId: nodeId,
    );

    await _db.insertCustomSymptom(symptom);

    // Update local cache
    switch (category) {
      case 'traumatic':
        _traumaticSymptoms.add(symptom);
        break;
      case 'medical':
        _medicalSymptoms.add(symptom);
        break;
      case 'behavioral':
        _behavioralSymptoms.add(symptom);
        break;
      case 'intervention':
        _interventionSymptoms.add(symptom);
        break;
    }

    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> deleteCustomSymptom(String id) async {
    final nodeId = await NodeId.get();
    final hlc = HLC.now(nodeId).pack();

    await _db.deleteCustomSymptomSoft(id, hlc: hlc, nodeId: nodeId);

    // Update local cache
    _traumaticSymptoms.removeWhere((s) => s.id == id);
    _medicalSymptoms.removeWhere((s) => s.id == id);
    _behavioralSymptoms.removeWhere((s) => s.id == id);
    _interventionSymptoms.removeWhere((s) => s.id == id);

    notifyListeners();
    onLocalChange?.call();
  }
}
