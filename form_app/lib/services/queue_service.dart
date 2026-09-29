import 'desktop_connection_service.dart';

class QueueService {
  final _connection = DesktopConnectionService.instance;

  /// Submit a patient record to the desktop app via its local HTTP server.
  ///
  /// Throws an exception if not connected or if the request fails.
  Future<void> addToQueue({
    required String studentName,
    required String studentNumber,
    required String firstName,
    required String lastName,
    required String middleName,
    required String extension,
    required DateTime? birthdate,
    required String sex,
    required String contactNumber,
    required String address,
    required String guardianName,
    required String guardianContact,
    required String guardian2Name,
    required String guardian2Contact,
    required String allergicTo,
    required List<String> symptoms,
    required String customChiefComplaint,
    required String role,
    required String department,
    required String level,
    String? existingPatientId,
  }) async {
    if (!_connection.isConnected) {
      throw Exception(
        'Not connected to the desktop app. Please scan the QR code first.',
      );
    }

    // Re-verify connection before submitting
    final reachable = await _connection.checkConnection();
    if (!reachable) {
      throw Exception('Lost connection to the desktop app. Please reconnect.');
    }

    final data = {
      'patientName': studentName,
      'idNumber': studentNumber,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'extension': extension,
      'birthdate': birthdate?.toIso8601String(),
      'sex': sex,
      'contactNumber': contactNumber,
      'address': address,
      'guardianName': guardianName,
      'guardianContact': guardianContact,
      'guardian2Name': guardian2Name,
      'guardian2Contact': guardian2Contact,
      'allergicTo': allergicTo,
      'symptoms': symptoms,
      'customChiefComplaint': customChiefComplaint,
      'role': role,
      'department': department,
      'level': level,
      if (existingPatientId != null) 'existingPatientId': existingPatientId,
    };

    await DesktopConnectionService.instance.submitPatient(data);
  }
}
