import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _currentPin = '';
  String _errorMessage = '';
  bool _isChecking = false;

  void _onKeyPress(String key) {
    if (_isChecking) return;
    if (_currentPin.length < 6) {
      setState(() {
        _currentPin += key;
        _errorMessage = '';
      });
      if (_currentPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onDelete() {
    if (_currentPin.isNotEmpty && !_isChecking) {
      setState(() {
        _currentPin = _currentPin.substring(0, _currentPin.length - 1);
        _errorMessage = '';
      });
    }
  }

  Future<void> _verifyPin() async {
    setState(() => _isChecking = true);
    
    // Small delay for UI feel
    await Future.delayed(const Duration(milliseconds: 200));
    
    final isValid = await AuthService.instance.verifyPin(_currentPin);
    
    if (mounted) {
      if (isValid) {
        widget.onUnlocked();
      } else {
        setState(() {
          _currentPin = '';
          _errorMessage = 'Incorrect PIN. Please try again.';
          _isChecking = false;
        });
      }
    }
  }

  void _showForgotPinDialog() {
    final passController = TextEditingController();
    final newPinController = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Admin Recovery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the Admin Recovery Password to reset the daily PIN.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passController,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Admin Password',
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'New 6-Digit PIN',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final success = await AuthService.instance.resetPinWithAdmin(
                  passController.text,
                  newPinController.text,
                );
                if (context.mounted) {
                  if (success) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PIN reset successfully')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invalid Admin Password'),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  }
                }
              },
              child: const Text('RESET PIN'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.backspace ||
                event.logicalKey == LogicalKeyboardKey.delete) {
              _onDelete();
              return KeyEventResult.handled;
            }
            final char = event.character;
            if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
              _onKeyPress(char);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.textPrimary.withValues(alpha: 0.95),
                AppTheme.textPrimary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 24),
            Text(
              'CLINIC ACCESS LOCKED',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 48),
            
            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final active = index < _currentPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    color: active ? AppTheme.accent : Colors.transparent,
                    boxShadow: active ? [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.5),
                        blurRadius: 10,
                      )
                    ] : null,
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 24),
            SizedBox(
              height: 20,
              child: Text(
                _errorMessage,
                style: const TextStyle(color: AppTheme.dangerLight, fontSize: 13),
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Keypad
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                padding: const EdgeInsets.all(0),
                children: [
                  for (var i = 1; i <= 9; i++) _buildKey(i.toString()),
                  const SizedBox(),
                  _buildKey('0'),
                  _buildIconKey(Icons.backspace_outlined, _onDelete),
                ],
              ),
            ),
            
            const SizedBox(height: 60),
            TextButton(
              onPressed: _showForgotPinDialog,
              child: Text(
                'FORGOT PIN?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildKey(String value) {
    return InkWell(
      onTap: () => _onKeyPress(value),
      borderRadius: BorderRadius.circular(50),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
        ),
        alignment: Alignment.center,
        child: Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildIconKey(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.6), size: 24),
      ),
    );
  }
}
