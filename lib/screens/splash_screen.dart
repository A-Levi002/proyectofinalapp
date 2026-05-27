import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  final StorageService storageService;
  const SplashScreen({required this.storageService, super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _verificar();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _verificar() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    // 1. Primera vez → Onboarding
    if (widget.storageService.esPrimerLanzamiento()) {
      Navigator.of(context).pushReplacementNamed('/onboarding');
      return;
    }

    // 2. Tiene sesión → Bienvenida (requiere huella o PIN)
    if (widget.storageService.tieneToken()) {
      Navigator.of(context).pushReplacementNamed('/bienvenida');
      return;
    }

    // 3. Sin sesión activa → Onboarding (no al login de CI+PIN)
    Navigator.of(context).pushReplacementNamed('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final surf = NothingTheme.surf(dark);
    final div  = NothingTheme.div(dark);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: div, width: 0.5),
                    boxShadow: [BoxShadow(
                        color: NothingTheme.accentGreen.withOpacity(0.15),
                        blurRadius: 30, spreadRadius: 4)],
                  ),
                  child: const Center(child: Icon(
                      Icons.directions_bus_rounded,
                      size: 46, color: NothingTheme.accentGreen)),
                ),
                const SizedBox(height: 32),
                Text('TRANSIT', style: NothingTheme.heading.copyWith(
                    color: prim, fontSize: 36, letterSpacing: 4)),
                Text('APP', style: NothingTheme.heading.copyWith(
                    color: NothingTheme.accentGreen,
                    fontSize: 36, letterSpacing: 4)),
                const SizedBox(height: 56),
                SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: sec.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
