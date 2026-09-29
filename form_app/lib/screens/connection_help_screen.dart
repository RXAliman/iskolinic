import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'qr_scan_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ConnectionHelpScreen extends StatefulWidget {
  const ConnectionHelpScreen({super.key});

  @override
  State<ConnectionHelpScreen> createState() => _ConnectionHelpScreenState();
}

class _ConnectionHelpScreenState extends State<ConnectionHelpScreen> {
  String _localIp = 'Detecting...';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _getHostIp();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  Future<void> _getHostIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      String? foundIp;

      // Try to find 192.168.x.x first
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.')) {
            foundIp = addr.address;
            break;
          }
        }
        if (foundIp != null) break;
      }

      // Fallback to any address if 192.168.x.x not found
      if (foundIp == null &&
          interfaces.isNotEmpty &&
          interfaces.first.addresses.isNotEmpty) {
        foundIp = interfaces.first.addresses.first.address;
      }

      if (mounted) {
        setState(() {
          _localIp = foundIp ?? 'No Wi-Fi detected';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localIp = 'Error detecting IP';
        });
      }
    }
  }

  String get _networkRange {
    if (_localIp.contains('.') && !_localIp.startsWith('Detecting')) {
      final parts = _localIp.split('.');
      if (parts.length == 4) {
        return '${parts[0]}.${parts[1]}.${parts[2]}.x';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppTheme.primaryLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 24 : 40,
              vertical: isMobile ? 40 : 60,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo and Version
                Image.asset(
                  'assets/app-logo-colored.png',
                  height: isMobile ? 80 : 120,
                ),
                if (_appVersion.isNotEmpty) ...[
                  SizedBox(height: isMobile ? 8 : 12),
                  Text(
                    'Form App Version $_appVersion',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
                SizedBox(height: isMobile ? 32 : 48),
                // Title
                Text(
                  'Network Setup',
                  style: isMobile
                      ? Theme.of(context).textTheme.headlineMedium
                      : Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Please follow these steps to connect to the clinic system',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),

                // Instructions Card
                Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  width: double.infinity,
                  padding: EdgeInsets.all(isMobile ? 24 : 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildStep(
                        icon: Icons.wifi_rounded,
                        title: 'Turn on Wi-Fi',
                        description:
                            'Ensure the tablet\'s Wi-Fi is enabled and connected.',
                      ),
                      const Divider(height: 40),
                      _buildStep(
                        icon: Icons.router_rounded,
                        title: 'Join Clinic Network',
                        description:
                            'Connect to the same Wi-Fi network as the clinic desktop app.',
                      ),
                      const Divider(height: 40),
                      _buildStep(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Verify Connection',
                        customDescription: _networkRange.isNotEmpty
                            ? Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Desktop IP should also start with ',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.cardLight,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppTheme.dividerColor,
                                      ),
                                    ),
                                    child: Text(
                                      _networkRange.replaceAll('.x', ''),
                                      style: GoogleFonts.chivoMono(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        description: _networkRange.isEmpty
                            ? 'Check if this IP matches the Desktop app range.'
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Troubleshooting Note
                Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            color: AppTheme.danger,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Troubleshooting Tips',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Turn off Mobile Data if the device has a SIM card.\n'
                        '• Disable any active VPN or Proxy settings.\n'
                        '• If detection fails, check if the Desktop app is "Running".',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.danger.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Continue Button
                Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  width: double.infinity,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const QrScanScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'I\'M CONNECTED, START SCANNING',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Refresh IP link
                TextButton.icon(
                  onPressed: _getHostIp,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'REFRESH IP DETECTION',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required IconData icon,
    required String title,
    String? description,
    Widget? customDescription,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.cardLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.textSecondary, size: 24),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              if (customDescription != null)
                customDescription
              else if (description != null)
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              if (trailing != null) ...[const SizedBox(height: 12), trailing],
            ],
          ),
        ),
      ],
    );
  }
}
