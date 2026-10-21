import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'api_service.dart';
import 'app_theme.dart';
import 'storage_service.dart';
import 'auth_secreens.dart';
import 'doctor_screens.dart';
import 'screens/patient/patient_home.dart';
import 'screens/client/client_home.dart';
import 'screens/service_admin/service_admin_home.dart';
import 'providers/notification_provider.dart';
import 'socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  GoogleFonts.config.allowRuntimeFetching = true;
  ApiService().init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const QueueMedApp(),
    ),
  );
}

final _navigatorKey = GlobalKey<NavigatorState>();

class QueueMedApp extends StatelessWidget {
  const QueueMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Mon Rendez-vous Qflow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/patient/home': (_) => const PatientHome(),
        '/client/home': (_) => const ClientHome(),
        '/doctor/home': (_) => const DoctorHome(),
        '/service-admin/home': (_) => const ServiceAdminHome(),
      },
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    ApiService().onSessionExpired = () {
      SocketService().disconnect();
      _navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
    };
    _check();
  }

  Future<void> _check() async {
    final token = await _storage.read(kAccessToken);
    if (!mounted) return;
    if (token == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    SocketService().connect(token);
    try {
      final res = await ApiService().getMe();
      final role = res.data['user']['role'] as String;
      if (!mounted) return;
      final routes = {
        'patient': '/patient/home',
        'client': '/client/home',
        'doctor': '/doctor/home',
        'service_admin': '/service-admin/home',
      };
      Navigator.pushReplacementNamed(context, routes[role] ?? '/client/home');
    } catch (_) {
      await _storage.delete(kAccessToken);
      await _storage.delete(kRefreshToken);
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
