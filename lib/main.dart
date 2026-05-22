import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/nothing_theme.dart';
import 'services/storage_service.dart';
import 'services/supabase_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/registro_escanear_screen.dart';
import 'screens/generar_qr_screen.dart';
import 'screens/viajes_screen.dart';
import 'screens/perfil_screen.dart';
import 'screens/recarga_screen.dart';
import 'screens/validador_screen.dart';
import 'screens/registro_conductor_screen.dart';
import 'screens/panel_conductor_screen.dart';
import 'screens/panel_admin_contratos_screen.dart';
import 'screens/login_conductor_screen.dart';
import 'screens/ajustes_screen.dart';
import 'screens/trufis_screen.dart'; // ← NUEVO
import 'screens/editar_perfil_screen.dart'; // ← NUEVO

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('[APP] Inicializando Supabase...');
  try {
    await Supabase.initialize(
      url: 'https://nhjmudtkmqkxwhoeqjps.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5oam11ZHRrbXFreHdob2VxanBzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3OTM2OTAsImV4cCI6MjA5NDM2OTY5MH0.u-UlllE7vfdiOB5BBrcMbO--3HXjaYkYMFwoZTGJXqo',
    );
    print('[APP] ✓ Supabase inicializado correctamente');
  } catch (e) {
    print('[APP] ✗ Error al inicializar Supabase: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final storageService = StorageService();
  await storageService.init();

  runApp(MyApp(storageService: storageService));
}

class MyApp extends StatefulWidget {
  final StorageService storageService;
  const MyApp({required this.storageService, super.key});
  @override State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late SupabaseService _supabaseService;

  @override
  void initState() {
    super.initState();
    _supabaseService = SupabaseService(widget.storageService);
    themeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransitApp',
      debugShowCheckedModeBanner: false,
      theme: NothingTheme.themeLight,
      darkTheme: NothingTheme.theme,
      themeMode: themeNotifier.mode,
      home: SplashScreen(storageService: widget.storageService),
      routes: {
        '/splash':             (_) => SplashScreen(storageService: widget.storageService),
        '/login':              (_) => LoginScreen(supabaseService: _supabaseService, storageService: widget.storageService),
        '/home':               (_) => HomeScreen(storageService: widget.storageService),
        '/registro-escanear':  (_) => const RegistroEscanearScreen(),
        '/generar-qr':         (_) => GenerarQRScreen(storageService: widget.storageService),
        '/viajes':             (_) => ViajesScreen(storageService: widget.storageService),
        '/perfil':             (_) => PerfilScreen(storageService: widget.storageService),
        '/recarga':            (_) => RecargaScreen(storageService: widget.storageService),
        '/validador':          (_) => const ValidadorScreen(),
        '/registro-conductor': (_) => const RegistroConductorScreen(),
        '/panel-conductor':    (_) => const PanelConductorScreen(),
        '/admin/contratos':    (_) => const PanelAdminContratosScreen(),
        '/ajustes':            (_) => const AjustesScreen(),
        '/login-conductor':    (_) => LoginConductorScreen(supabaseService: _supabaseService, storageService: widget.storageService),
        '/trufis':             (_) => const TrufisScreen(), // ← NUEVO
        '/editar-perfil':      (_) => EditarPerfilScreen(storageService: widget.storageService), // ← NUEVO
      },
    );
  }
}
