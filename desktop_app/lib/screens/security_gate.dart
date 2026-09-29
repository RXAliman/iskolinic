import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'initial_setup_screen.dart';
import 'lock_screen.dart';

class SecurityGate extends StatefulWidget {
  final Widget child;

  const SecurityGate({super.key, required this.child});

  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate> {
  bool? _isSetupComplete;
  bool _isUnlocked = false;

  @override
  void initState() {
    super.initState();
    _checkSecurityState();
  }

  Future<void> _checkSecurityState() async {
    final setup = await AuthService.instance.isSetupComplete();
    setState(() {
      _isSetupComplete = setup;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show a blank loader while checking storage
    if (_isSetupComplete == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Step 1: Initial Setup
    if (!_isSetupComplete!) {
      return InitialSetupScreen(
        onSetupComplete: () => setState(() => _isSetupComplete = true),
      );
    }

    // Step 2: Daily Lock Screen
    if (!_isUnlocked) {
      return LockScreen(
        onUnlocked: () => setState(() => _isUnlocked = true),
      );
    }

    // Step 3: The Main App
    return widget.child;
  }
}
