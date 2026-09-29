import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../providers/sync_provider.dart';

class InitialSetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const InitialSetupScreen({super.key, required this.onSetupComplete});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _adminPassController = TextEditingController();
  final _syncSecretController = TextEditingController();

  bool _obscurePin = true;
  bool _obscureAdmin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    _adminPassController.dispose();
    _syncSecretController.dispose();
    super.dispose();
  }

  Future<void> _handleSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.completeSetup(
        pin: _pinController.text,
        adminPassword: _adminPassController.text,
        syncSecret: _syncSecretController.text,
      );

      // Re-initialize the sync service with the newly created secret
      if (mounted) {
        Provider.of<SyncProvider>(context, listen: false).reconnectWithNewSecret();
      }

      widget.onSetupComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryLight,
              AppTheme.cardLight,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo or Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: AppTheme.accentCard(),
                    child: const Icon(
                      Icons.security_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Security Setup',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Configure your IskoLinic credentials. This setup is performed only once.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 40),
                  
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── PIN Section ──────────────────────────────────
                        _buildSectionLabel('DAILY ACCESS PIN (6 DIGITS)'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _pinController,
                                obscureText: _obscurePin,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: '6-Digit PIN',
                                  prefixIcon: const Icon(Icons.pin_rounded),
                                  counterText: '',
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscurePin ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.length != 6) return 'Enter exactly 6 digits';
                                  if (int.tryParse(v) == null) return 'Must be numeric';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _confirmPinController,
                                obscureText: _obscurePin,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: 'Confirm PIN',
                                  prefixIcon: const Icon(Icons.check_circle_outline),
                                  counterText: '',
                                ),
                                validator: (v) {
                                  if (v != _pinController.text) return 'PINs do not match';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // ── Admin Section ────────────────────────────────
                        _buildSectionLabel('RECOVERY PASSWORD'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminPassController,
                          obscureText: _obscureAdmin,
                          decoration: InputDecoration(
                            labelText: 'Admin Password',
                            prefixIcon: const Icon(Icons.admin_panel_settings_rounded),
                            helperText: 'Used to reset the PIN if forgotten.',
                            suffixIcon: IconButton(
                              icon: Icon(_obscureAdmin ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscureAdmin = !_obscureAdmin),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // ── Sync Section ─────────────────────────────────
                        _buildSectionLabel('CLOUD SYNC SECRET'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _syncSecretController,
                          decoration: InputDecoration(
                            labelText: 'Relay Sync Key',
                            prefixIcon: const Icon(Icons.vignette_rounded),
                            helperText: 'Shared secret for data synchronization.',
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        
                        const SizedBox(height: 48),
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSetup,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('COMPLETE SECURITY SETUP'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppTheme.accent,
        letterSpacing: 1.2,
      ),
    );
  }
}
