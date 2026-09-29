import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/desktop_connection_service.dart';
import '../theme/app_theme.dart';
import '../services/device_service.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _cameraController;
  bool _isProcessing = false;
  bool _cameraAvailable = true;
  String _deviceModel = 'Detecting...';

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadDeviceModel();
  }

  Future<void> _loadDeviceModel() async {
    final model = await DeviceService.instance.getDeviceModel();
    if (mounted) {
      setState(() => _deviceModel = model);
    }
  }

  Future<void> _initCamera() async {
    try {
      if (_cameraController != null) {
        await _cameraController!.stop();
        await _cameraController!.dispose();
      }
      _cameraController = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
    } catch (_) {
      setState(() => _cameraAvailable = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.stop();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    _cameraController?.stop();

    try {
      // Try to parse as JSON connection payload from the desktop app
      final data = jsonDecode(code);
      if (data is Map &&
          data.containsKey('host') &&
          data.containsKey('port') &&
          data.containsKey('token')) {
        final host = data['host'];
        final port = data['port'];

        final connected =
            await DesktopConnectionService.instance.connect(code);
        if (!mounted) return;
        if (connected) {
          _showSuccess();
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/loading');
          }
        } else {
          _showError(
            'Could not connect to $host:$port. '
            'Ensure the tablet and desktop are on the same network.',
          );
          _resumeScanning();
        }
      } else {
        _showError('Invalid QR code. Please scan the code from the desktop app.');
        _resumeScanning();
      }
    } catch (e) {
      // Not valid JSON
      if (!mounted) return;
      _showError('QR code error: $e');
      _resumeScanning();
    }
  }



  void _resumeScanning() {
    setState(() => _isProcessing = false);
    _cameraController?.start();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showSuccess() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Connected to desktop app!'),
        backgroundColor: AppTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Back Button ─────────────────────────────────────
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textMuted),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.cardLight,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Header ──────────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connect to Clinic',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan the QR code on the desktop app to connect',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // ── Camera preview ──────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _cameraAvailable && _cameraController != null
                      ? Stack(
                          children: [
                            MobileScanner(
                              controller: _cameraController!,
                              onDetect: (capture) {
                                final barcode = capture.barcodes.firstOrNull;
                                if (barcode?.rawValue != null) {
                                  _handleCode(barcode!.rawValue!);
                                }
                              },
                            ),
                            if (_isProcessing)
                              Container(
                                color: Colors.black54,
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Connecting...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppTheme.cardLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_off_rounded,
                                  size: 48,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Camera not available',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Device: $_deviceModel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

