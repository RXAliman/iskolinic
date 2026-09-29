import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/patient_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/custom_symptom_provider.dart';
import 'providers/local_server_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/security_gate.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for Windows desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const AppRoot());
}

/// Root widget that manages the splash → main app transition.
///
/// Shows the [SplashScreen] first, which handles update checks and service
/// initialization. Once initialization completes, it rebuilds with the full
/// [ClinicApp] including all providers.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  PatientProvider? _patientProvider;
  SyncProvider? _syncProvider;
  InventoryProvider? _inventoryProvider;
  CustomSymptomProvider? _customSymptomProvider;
  LocalServerProvider? _localServerProvider;
  SettingsProvider? _settingsProvider;

  void _onInitComplete({
    required PatientProvider patientProvider,
    required SyncProvider syncProvider,
    required InventoryProvider inventoryProvider,
    required CustomSymptomProvider customSymptomProvider,
    required LocalServerProvider localServerProvider,
    required SettingsProvider settingsProvider,
  }) {
    setState(() {
      _patientProvider = patientProvider;
      _syncProvider = syncProvider;
      _inventoryProvider = inventoryProvider;
      _customSymptomProvider = customSymptomProvider;
      _localServerProvider = localServerProvider;
      _settingsProvider = settingsProvider;
    });
  }

  @override
  Widget build(BuildContext context) {
    // While services are initializing, show the splash screen
    if (_patientProvider == null) {
      return MaterialApp(
        title: 'IskoLinic App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: SplashScreen(onInitComplete: _onInitComplete),
      );
    }

    // Once initialized, show the full app with providers
    return ClinicApp(
      patientProvider: _patientProvider!,
      syncProvider: _syncProvider!,
      inventoryProvider: _inventoryProvider!,
      customSymptomProvider: _customSymptomProvider!,
      localServerProvider: _localServerProvider!,
      settingsProvider: _settingsProvider!,
    );
  }
}

class ClinicApp extends StatelessWidget {
  final PatientProvider patientProvider;
  final SyncProvider syncProvider;
  final InventoryProvider inventoryProvider;
  final CustomSymptomProvider customSymptomProvider;
  final LocalServerProvider localServerProvider;
  final SettingsProvider settingsProvider;

  const ClinicApp({
    super.key,
    required this.patientProvider,
    required this.syncProvider,
    required this.inventoryProvider,
    required this.customSymptomProvider,
    required this.localServerProvider,
    required this.settingsProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: patientProvider),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider.value(value: syncProvider),
        ChangeNotifierProvider.value(value: inventoryProvider),
        ChangeNotifierProvider.value(value: customSymptomProvider),
        ChangeNotifierProvider.value(value: localServerProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: MaterialApp(
        title: 'IskoLinic App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SecurityGate(child: DashboardScreen()),
      ),
    );
  }
}
