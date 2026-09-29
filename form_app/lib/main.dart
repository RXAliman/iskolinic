import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/qr_scan_screen.dart';
import 'screens/connection_loading_screen.dart';
import 'screens/input_form_screen.dart';
import 'screens/barcode_scanner_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/connection_help_screen.dart';
import 'screens/id_method_screen.dart';
import 'screens/confirmation_screen.dart';
import 'theme/app_theme.dart';

import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Disable runtime fetching to ensure local bundled fonts are used
  GoogleFonts.config.allowRuntimeFetching = false;

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ClinicInputApp());
}

class ClinicInputApp extends StatelessWidget {
  const ClinicInputApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IskoLinic Form App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const ConnectionHelpScreen(),
      routes: {
        '/help': (_) => const ConnectionHelpScreen(),
        '/scan': (_) => const QrScanScreen(),
        '/loading': (_) => const ConnectionLoadingScreen(),
        '/welcome': (_) => const WelcomeScreen(),
        '/id-method': (_) => const IdentificationMethodScreen(),
        '/barcode': (_) => const BarcodeScannerScreen(),
        '/form': (_) => const InputFormScreen(),
        '/confirmation': (_) => const ConfirmationScreen(),
      },
    );
  }
}
