import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../models/patient.dart';
import '../models/visitation.dart';
import '../services/database_helper.dart';
import '../services/form_app_settings_service.dart';
import '../crdt/hlc.dart';
import '../crdt/node_id.dart';
import 'package:flutter/foundation.dart';

/// Lightweight HTTP server embedded in the desktop app.
///
/// Exposes REST endpoints that the tablet app uses to submit patient data
/// and fetch existing records over a private local network.
class LocalServerService {
  static final LocalServerService instance = LocalServerService._internal();
  factory LocalServerService() => instance;
  LocalServerService._internal();

  HttpServer? _server;
  String _authToken = '';
  String _localIp = '';
  int _port = 8080;
  final Map<String, ({DateTime lastSeen, String model})> _connectedDevices = {};
  static const _deviceTimeout = Duration(seconds: 60);

  // Edit Request Tracking
  final List<EditRequest> _editRequests = [];

  List<EditRequest> get pendingRequests =>
      _editRequests.where((r) => !r.isApproved && !r.isDenied).toList();

  bool get isRunning => _server != null;
  String get authToken => _authToken;
  String get localIp => _localIp;
  int get port => _port;

  /// Returns only devices that have made a request within the last 60 seconds.
  List<String> get connectedDeviceModels {
    final now = DateTime.now();
    _connectedDevices.removeWhere(
      (_, data) => now.difference(data.lastSeen) > _deviceTimeout,
    );
    return _connectedDevices.values.map((d) => d.model).toList();
  }

  /// JSON payload to encode in the QR code.
  String get qrPayload =>
      jsonEncode({'host': _localIp, 'port': _port, 'token': _authToken});

  /// Callback invoked when patient data changes (new patient/visitation).
  /// The desktop's PatientProvider should listen to this to refresh its UI.
  void Function()? onDataChanged;

  /// Callback invoked when the list of connected devices changes.
  void Function()? onDevicesChanged;

  /// Start the HTTP server on all network interfaces.
  Future<void> start({int port = 8080}) async {
    if (_server != null) return; // Already running

    _port = port;
    _authToken = const Uuid().v4();
    _localIp = await _detectLocalIp();

    final router = Router();

    // Health check endpoint
    router.get('/api/health', (shelf.Request request) {
      return shelf.Response.ok(
        jsonEncode({
          'status': 'ok',
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Get all patients (non-deleted)
    router.get('/api/patients', (shelf.Request request) async {
      try {
        final patients = await DatabaseHelper.instance.getPatients();
        final list = patients.map((p) => p.toMap()).toList();
        // Convert numeric isDeleted to bool for JSON
        for (final map in list) {
          map['isDeleted'] = (map['isDeleted'] as int?) == 1;
        }
        return shelf.Response.ok(
          jsonEncode(list),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Search patient by ID number (exact match)
    router.get('/api/patients/search', (shelf.Request request) async {
      try {
        final idNumber = request.url.queryParameters['idNumber'];
        if (idNumber == null || idNumber.isEmpty) {
          return shelf.Response.badRequest(
            body: jsonEncode({'error': 'idNumber query parameter is required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final patient = await DatabaseHelper.instance.getPatientByIdNumber(
          idNumber,
        );
        if (patient == null) {
          return shelf.Response.notFound(
            jsonEncode({'error': 'Patient not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final requestId = request.url.queryParameters['requestId'];
        bool hasApproval = false;

        if (requestId != null && requestId.isNotEmpty) {
          try {
            final req = _editRequests.firstWhere((r) => r.id == requestId);
            if (req.isApproved && req.idNumber == idNumber) {
              hasApproval = true;
            }
          } catch (_) {
            // Request not found or not approved
          }
        }

        final map = patient.toMap();
        map['isDeleted'] = (map['isDeleted'] as int?) == 1;

        if (!hasApproval) {
          // REDACT SENSITIVE INFO
          final publicFields = [
            'id',
            'firstName',
            'lastName',
            'middleName',
            'extension',
            'patientName',
            'idNumber',
            'role',
            'department',
          ];
          map.removeWhere((key, value) => !publicFields.contains(key));
          map['isPartial'] = true;
        } else {
          map['isPartial'] = false;
        }

        return shelf.Response.ok(
          jsonEncode(map),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Request Edit Access
    router.post('/api/edit-requests', (shelf.Request request) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final idNumber = data['idNumber'] as String?;

        if (idNumber == null) return shelf.Response.badRequest();

        final remoteIp =
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'unknown';
        final deviceModel = request.headers['x-device-model'] ?? 'Tablet';

        // Remove old requests for this device/patient to avoid clutter
        _editRequests.removeWhere(
          (r) => r.remoteIp == remoteIp && r.idNumber == idNumber,
        );

        final editReq = EditRequest(
          id: const Uuid().v4(),
          idNumber: idNumber,
          deviceModel: deviceModel,
          remoteIp: remoteIp,
          createdAt: DateTime.now(),
        );

        _editRequests.add(editReq);
        onDevicesChanged?.call(); // Refresh UI

        return shelf.Response.ok(
          jsonEncode(editReq.toMap()),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return shelf.Response.internalServerError(body: e.toString());
      }
    });

    // Poll Edit Request Status
    router.get('/api/edit-requests/<id>', (
      shelf.Request request,
      String id,
    ) async {
      try {
        final req = _editRequests.firstWhere((r) => r.id == id);
        return shelf.Response.ok(
          jsonEncode(req.toMap()),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (_) {
        return shelf.Response.notFound(jsonEncode({'error': 'Not found'}));
      }
    });

    // Add a new patient + visitation from the tablet form
    router.post('/api/patients', (shelf.Request request) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final nodeId = await NodeId.get();
        final clock = HLC.now(nodeId).send();
        final hlcStr = clock.pack();
        final now = DateTime.now();

        final existingId = data['existingPatientId'] as String?;
        Patient? existingRecord;
        if (existingId != null && existingId.isNotEmpty) {
          existingRecord = await DatabaseHelper.instance.getPatient(existingId);
        }

        // Fallback to idNumber lookup if GUID is missing or not found
        if (existingRecord == null) {
          final idNumber = data['idNumber'] as String? ?? '';
          if (idNumber.isNotEmpty) {
            existingRecord =
                await DatabaseHelper.instance.getPatientByIdNumber(idNumber);
          }
        }

        final patientId = existingRecord?.id ?? const Uuid().v4();

        // Build patientName from parts: "LAST, FIRST MIDDLE EXT"
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        final middleName = data['middleName'] as String? ?? '';
        final ext = data['extension'] as String? ?? '';
        final patientName =
            data['patientName'] as String? ??
            '$lastName, $firstName $middleName $ext'.trim().replaceAll(
              RegExp(r'\s+'),
              ' ',
            );

        final patient = Patient(
          id: patientId,
          firstName: firstName,
          lastName: lastName,
          middleName: middleName,
          extension: ext,
          patientName: patientName,
          idNumber: data['idNumber'] as String? ?? '',
          birthdate:
              (data['birthdate'] != null &&
                  (data['birthdate'] as String).isNotEmpty)
              ? DateTime.tryParse(data['birthdate'] as String)
              : existingRecord?.birthdate,
          sex: (data['sex'] != null && (data['sex'] as String).isNotEmpty)
              ? data['sex'] as String
              : existingRecord?.sex ?? '',
          contactNumber:
              (data['contactNumber'] != null &&
                  (data['contactNumber'] as String).isNotEmpty)
              ? data['contactNumber'] as String
              : existingRecord?.contactNumber ?? '',
          address:
              (data['address'] != null &&
                  (data['address'] as String).isNotEmpty)
              ? data['address'] as String
              : existingRecord?.address ?? '',
          guardianName:
              (data['guardianName'] != null &&
                  (data['guardianName'] as String).isNotEmpty)
              ? data['guardianName'] as String
              : existingRecord?.guardianName ?? '',
          guardianContact:
              (data['guardianContact'] != null &&
                  (data['guardianContact'] as String).isNotEmpty)
              ? data['guardianContact'] as String
              : existingRecord?.guardianContact ?? '',
          guardian2Name:
              (data['guardian2Name'] != null &&
                  (data['guardian2Name'] as String).isNotEmpty)
              ? data['guardian2Name'] as String
              : existingRecord?.guardian2Name ?? '',
          guardian2Contact:
              (data['guardian2Contact'] != null &&
                  (data['guardian2Contact'] as String).isNotEmpty)
              ? data['guardian2Contact'] as String
              : existingRecord?.guardian2Contact ?? '',
          allergicTo:
              (data['allergicTo'] != null &&
                  (data['allergicTo'] as String).isNotEmpty)
              ? data['allergicTo'] as String
              : existingRecord?.allergicTo ?? '',
          role: (data['role'] != null && (data['role'] as String).isNotEmpty)
              ? data['role'] as String
              : existingRecord?.role ?? '',
          department:
              (data['department'] != null &&
                  (data['department'] as String).isNotEmpty)
              ? data['department'] as String
              : existingRecord?.department ?? '',
          level: (data['level'] != null && (data['level'] as String).isNotEmpty)
              ? data['level'] as String
              : existingRecord?.level ?? '',
          pastMedicalHistory: existingRecord?.pastMedicalHistory ?? [],
          vaccinationHistory: existingRecord?.vaccinationHistory ?? [],
          patientRemarks: existingRecord?.patientRemarks ?? '',
          permissions: existingRecord?.permissions ?? {},
          createdAt: existingRecord?.createdAt ?? now,
          updatedAt: now,
          hlc: hlcStr,
          nodeId: nodeId,
        );

        if (existingRecord != null) {
          await DatabaseHelper.instance.updatePatient(patient);
        } else {
          await DatabaseHelper.instance.insertPatient(patient);
        }

        // If symptoms or custom chief complaints are included, create a visitation record too
        final symptoms = data['symptoms'] as List<dynamic>?;
        final customChiefComplaint =
            data['customChiefComplaint'] as String? ?? '';

        if ((symptoms != null && symptoms.isNotEmpty) ||
            customChiefComplaint.isNotEmpty) {
          final visitation = Visitation(
            id: const Uuid().v4(),
            patientId: patientId,
            symptoms: symptoms?.cast<String>() ?? [],
            customChiefComplaint: customChiefComplaint,
            hlc: HLC.now(nodeId).send().pack(),
            nodeId: nodeId,
          );
          await DatabaseHelper.instance.insertVisitation(visitation);
        }

        // Notify desktop UI to refresh
        onDataChanged?.call();

        return shelf.Response(
          201,
          body: jsonEncode({'id': patientId, 'status': 'created'}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e, stack) {
        debugPrint('Error in POST /api/patients: $e');
        debugPrint(stack.toString());
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': e.toString(), 'stack': stack.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // ── Form App Config & Assets ─────────────────────────────────────────

    // Get form app configuration (asset metadata for cache invalidation)
    router.get('/api/form-config', (shelf.Request request) {
      try {
        final config = FormAppSettingsService.instance.getConfig();
        return shelf.Response.ok(
          jsonEncode(config),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Serve custom logo image
    router.get('/api/assets/logo', (shelf.Request request) {
      return _serveAssetFile('logo');
    });

    // Serve custom background image
    router.get('/api/assets/background', (shelf.Request request) {
      return _serveAssetFile('background');
    });

    // Serve custom video by index
    router.get('/api/assets/videos/<index>',
        (shelf.Request request, String index) {
      final idx = int.tryParse(index);
      if (idx == null) {
        return shelf.Response.badRequest(
          body: jsonEncode({'error': 'Invalid video index'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return _serveAssetFile('video', idx);
    });

    // Auth middleware — validates Bearer token on every request
    shelf.Middleware authMiddleware() {
      return (shelf.Handler innerHandler) {
        return (shelf.Request request) {
          // Track connected devices
          final remoteIp =
              (request.context['shelf.io.connection_info']
                      as HttpConnectionInfo?)
                  ?.remoteAddress
                  .address;
          final deviceModel = request.headers['x-device-model'] ?? 'Tablet';

          if (remoteIp != null) {
            final isNew = !_connectedDevices.containsKey(remoteIp);
            _connectedDevices[remoteIp] = (
              lastSeen: DateTime.now(),
              model: deviceModel,
            );
            if (isNew) {
              onDevicesChanged?.call();
            }
          }

          final authHeader = request.headers['authorization'];
          if (authHeader == null || authHeader != 'Bearer $_authToken') {
            return shelf.Response(
              401,
              body: jsonEncode({'error': 'Unauthorized'}),
              headers: {'Content-Type': 'application/json'},
            );
          }
          return innerHandler(request);
        };
      };
    }

    // CORS middleware for development
    shelf.Middleware corsMiddleware() {
      return (shelf.Handler innerHandler) {
        return (shelf.Request request) async {
          final response = await innerHandler(request);
          return response.change(
            headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
              'Access-Control-Allow-Headers': 'Authorization, Content-Type',
            },
          );
        };
      };
    }

    final pipeline = const shelf.Pipeline()
        .addMiddleware(corsMiddleware())
        .addMiddleware(authMiddleware())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(pipeline, '0.0.0.0', _port);
      _server!.autoCompress = true;
      // ignore: avoid_print
      print('[LocalServer] Running on http://$_localIp:$_port');
    } catch (e) {
      // If default port is taken, try an alternative
      try {
        _port = 8081;
        _server = await shelf_io.serve(pipeline, '0.0.0.0', _port);
        _server!.autoCompress = true;
        // ignore: avoid_print
        print(
          '[LocalServer] Running on http://$_localIp:$_port (fallback port)',
        );
      } catch (e2) {
        // ignore: avoid_print
        print('[LocalServer] Failed to start: $e2');
      }
    }
  }

  /// Stop the HTTP server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Regenerate the auth token. All existing tablet connections are invalidated.
  void regenerateToken() {
    _authToken = const Uuid().v4();
    _connectedDevices.clear();
    _editRequests.clear();
    onDevicesChanged?.call();
  }

  void approveRequest(String id) {
    final index = _editRequests.indexWhere((r) => r.id == id);
    if (index != -1) {
      _editRequests[index].isApproved = true;
      onDevicesChanged?.call();
    }
  }

  void denyRequest(String id) {
    final index = _editRequests.indexWhere((r) => r.id == id);
    if (index != -1) {
      _editRequests[index].isDenied = true;
      onDevicesChanged?.call();
    }
  }

  void clearRequests() {
    _editRequests.clear();
    onDevicesChanged?.call();
  }

  /// Serve a form app asset file as an HTTP response.
  shelf.Response _serveAssetFile(String assetType, [int? index]) {
    final file = FormAppSettingsService.instance.getAssetFile(assetType, index);
    if (file == null || !file.existsSync()) {
      return shelf.Response.notFound(
        jsonEncode({'error': 'Asset not configured'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final ext = p.extension(file.path).toLowerCase();
    final contentType = _mimeTypeForExtension(ext);

    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': contentType,
        'Content-Length': file.lengthSync().toString(),
      },
    );
  }

  /// Map file extensions to MIME types for serving assets.
  String _mimeTypeForExtension(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  /// Detect the local IP address on the LAN (not loopback).
  ///
  /// Prioritises 192.168.x.x (typical home/office router range) over other
  /// private ranges so that VPN or virtual adapters on 10.x.x.x don't win.
  Future<String> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Collect all non-loopback IPv4 addresses
      final allAddresses = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          allAddresses.add(addr.address);
        }
      }

      // ignore: avoid_print
      print('[LocalServer] Detected IPs: $allAddresses');

      // Priority 1: 192.168.x.x — typical local router
      for (final ip in allAddresses) {
        if (ip.startsWith('192.168.')) return ip;
      }
      // Priority 2: 172.16-31.x.x — private range
      for (final ip in allAddresses) {
        if (ip.startsWith('172.')) return ip;
      }
      // Priority 3: 10.x.x.x — can be VPN or corporate, lowest priority
      for (final ip in allAddresses) {
        if (ip.startsWith('10.')) return ip;
      }
      // Fallback: first available address
      if (allAddresses.isNotEmpty) return allAddresses.first;
    } catch (_) {}
    return '127.0.0.1';
  }
}

class EditRequest {
  final String id;
  final String idNumber;
  final String deviceModel;
  final String remoteIp;
  bool isApproved;
  bool isDenied;
  final DateTime createdAt;

  EditRequest({
    required this.id,
    required this.idNumber,
    required this.deviceModel,
    required this.remoteIp,
    this.isApproved = false,
    this.isDenied = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'idNumber': idNumber,
    'deviceModel': deviceModel,
    'remoteIp': remoteIp,
    'isApproved': isApproved,
    'isDenied': isDenied,
    'createdAt': createdAt.toIso8601String(),
  };
}
