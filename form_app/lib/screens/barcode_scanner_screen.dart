import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/desktop_connection_service.dart';
import '../services/persistent_form_service.dart';
import '../theme/app_theme.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _cameraController;
  bool _isProcessing = false;
  bool _cameraAvailable = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameraController = MobileScannerController(
        formats: const [
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _cameraAvailable = false);
    }
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    final code = barcode?.rawValue;
    if (code == null || code.isEmpty) return;

    _cameraController?.stop();
    if (!context.mounted) return;
    setState(() => _isProcessing = true);

    // Capture navigator before async gap
    final navigator = Navigator.of(context);

    // 1. Save ID to persistence
    PersistentFormService.instance.studentNumber = code;

    bool isPatientFound = false;
    try {
      final patientData = await DesktopConnectionService.instance
          .fetchPatientByIdNumber(code);
      if (patientData != null) {
        PersistentFormService.instance.updateFromMap(patientData);
        isPatientFound = true;
      }
    } catch (_) {
      // Ignore fetch errors, user can fill manually
    }

    if (!isPatientFound) {
      if (!mounted) return;
      
      final isCorrect = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Unregistered ID Scanned'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text('This ID number was scanned but no existing record was found. Is this ID number correct?'),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Rescan'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Correct'),
            ),
          ],
        ),
      );

      if (isCorrect != true) {
        // User wants to rescan
        setState(() => _isProcessing = false);
        _cameraController?.start();
        return;
      }
    }

    // 3. Navigate to form
    navigator.pushReplacementNamed('/form');
  }

  @override
  void dispose() {
    _cameraController?.stop();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview (base layer) ──
          if (_cameraController != null && _cameraAvailable)
            MobileScanner(
              controller: _cameraController!,
              onDetect: _onBarcodeDetected,
            ),

          // ── Scan overlay (simple semi-transparent borders, no ColorFiltered) ──
          _buildSimpleOverlay(context),

          // ── Top bar: back button ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 36,
              ),
              onPressed: () {
                _cameraController?.stop();
                Navigator.pop(context);
              },
            ),
          ),

          // ── Bottom section: instructions + skip button ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Instructions card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.document_scanner_outlined,
                            color: AppTheme.accent,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Scan ID Barcode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Remove ID cover if it isn\'t working',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Skip button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _cameraController?.stop();
                          PersistentFormService.instance.studentNumber = '';
                          Navigator.pushReplacementNamed(context, '/form');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        child: const Text(
                          "I don't have an ID Card",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Camera unavailable state ──
          if (!_cameraAvailable)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_rounded,
                      color: Colors.white30,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera unavailable',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _initCamera,
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Processing overlay ──
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accent),
                    SizedBox(height: 20),
                    Text(
                      'Searching Records...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Simple overlay that darkens the edges without using ColorFiltered/BlendMode
  /// which can interfere with camera texture rendering on some devices.
  Widget _buildSimpleOverlay(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scanWidth = screenWidth * 0.85;
    const scanHeight = 220.0;

    return Center(
      child: Container(
        width: scanWidth,
        height: scanHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.accent, width: 3),
        ),
      ),
    );
  }
}
