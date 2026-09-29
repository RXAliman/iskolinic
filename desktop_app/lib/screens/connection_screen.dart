import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/local_server_provider.dart';
import '../theme/app_theme.dart';

/// Desktop "Connection" tab — shows a QR code the tablet can scan to connect.
class ConnectionScreen extends StatelessWidget {
  /// Callback to navigate to the Settings tab (Form App Management section).
  final VoidCallback? onNavigateToSettings;

  const ConnectionScreen({super.key, this.onNavigateToSettings});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalServerProvider>(
      builder: (context, server, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Form App Connection',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scan the QR code below from the form app to connect',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (onNavigateToSettings != null)
                    ElevatedButton.icon(
                      onPressed: onNavigateToSettings,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Form App Settings'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Main content row ────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: QR Code card
                  _buildQrCard(context, server),
                  const SizedBox(width: 32),

                  // Right: Server info + devices
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildConnectionInfoCard(context, server),
                        if (server.pendingRequests.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _buildRequestsCard(context, server),
                        ],
                        if (server.connectedDeviceModels.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _buildDevicesCard(context, server),
                        ] else ...[
                          const SizedBox(height: 20),
                          _buildInstructionsCard(context),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Large QR code display card.
  Widget _buildQrCard(BuildContext context, LocalServerProvider server) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // QR Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.qr_code_2_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'CONNECTION QR CODE',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // QR Code
          if (server.isRunning)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: QrImageView(
                data: server.qrPayload,
                version: QrVersions.auto,
                size: 240,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0F172A),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0F172A),
                ),
                backgroundColor: Colors.white,
              ),
            )
          else
            Container(
              width: 264,
              height: 264,
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 48,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Server not running',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Hint text
          Text(
            'Point the device camera here',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Server connection details (IP, port, token preview).
  Widget _buildConnectionInfoCard(
    BuildContext context,
    LocalServerProvider server,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection Details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.dns_rounded,
            label: 'Local Server',
            value: server.isRunning ? 'Running' : 'Stopped',
            valueColor: server.isRunning ? Colors.green : AppTheme.textMuted,
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.vpn_key_rounded,
            label: 'Connection Token',
            value: server.isRunning
                ? '${server.authToken.substring(0, 8)}…'
                : '—',
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.wifi_rounded,
            label: 'Host IP Address',
            value: server.isRunning ? server.localIp : '—',
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.settings_input_component_rounded,
            label: 'Server Port',
            value: server.isRunning ? server.port.toString() : '—',
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onPressed: server.isRunning
                ? () {
                    server.regenerateToken();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Token regenerated. Existing tablet connections are now invalid.',
                        ),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Regenerate Token'),
          ),
        ],
      ),
    );
  }

  /// List of currently connected tablet devices.
  Widget _buildDevicesCard(BuildContext context, LocalServerProvider server) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Connected Devices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => server.refreshDevices(),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh list',
                color: AppTheme.accent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...server.connectedDeviceModels.map(
            (model) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tablet_rounded,
                      size: 18,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      model,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// List of pending edit requests from tablets.
  Widget _buildRequestsCard(BuildContext context, LocalServerProvider server) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.security_rounded,
                color: AppTheme.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Pending Edit Requests',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.accentDim,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => server.clearRequests(),
                child: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: server.pendingRequests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final req = server.pendingRequests[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ID: ${req.idNumber}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'From: ${req.deviceModel}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => server.denyRequest(req.id),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                          ),
                          child: const Text('Deny'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => server.approveRequest(req.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Instructions card for clinic staff.
  Widget _buildInstructionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'How to Connect',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppTheme.accentDim),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InstructionStep(
            number: '1',
            text:
                'Make sure the tablet/smartphone is connected to the clinic router Wi-Fi.',
          ),
          const SizedBox(height: 8),
          _InstructionStep(
            number: '2',
            text: 'Open the form app and follow the given instructions.',
          ),
          const SizedBox(height: 8),
          _InstructionStep(
            number: '3',
            text: 'Point the camera at the QR code on the left.',
          ),
          const SizedBox(height: 8),
          _InstructionStep(
            number: '4',
            text: 'The device will automatically connect and verify.',
          ),
        ],
      ),
    );
  }
}

/// Displays a label-value row with an icon.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textMuted),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.chivoMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Numbered instruction step widget.
class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;

  const _InstructionStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
