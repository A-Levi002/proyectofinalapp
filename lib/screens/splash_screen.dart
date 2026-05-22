import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  final StorageService storageService;

  const SplashScreen({required this.storageService, super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Configurar animaciones
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    
    _animationController.forward();
    
    _verificarSesion();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _verificarSesion() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final tieneToken = widget.storageService.tieneToken();

    if (tieneToken) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / Icono
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: NothingTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: NothingTheme.divider, width: 0.5),
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    size: 64,
                    color: NothingTheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                // Título
                const Text(
                  'TRANSIT',
                  style: NothingTheme.heading,
                ),
                const Text(
                  'APP',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: NothingTheme.accentGreen,
                  ),
                ),
                const SizedBox(height: 16),
                // Subtítulo
                Text(
                  'SISTEMA DE TRANSPORTE INTELIGENTE',
                  style: NothingTheme.label.copyWith(
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 48),
                // Cargando
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: NothingTheme.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'CARGANDO...',
                  style: NothingTheme.label.copyWith(
                    color: NothingTheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}