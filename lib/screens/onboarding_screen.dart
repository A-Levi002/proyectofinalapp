import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  final StorageService storageService;
  const OnboardingScreen({required this.storageService, super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  int _paso = 0; // 0 = bienvenida, 1 = elegir tipo
  List<String> _cuentasRegistradas = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    themeNotifier.addListener(_rebuild);
    _cuentasRegistradas = widget.storageService.obtenerCuentasRegistradas();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }
  void _rebuild() => setState(() {});

  Future<void> _ir(String ruta, String tipo) async {
    await widget.storageService.marcarLanzamiento();
    await widget.storageService.guardarTipoSesion(tipo);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(ruta);
  }

  Future<void> _animarSiguiente() async {
    await _ctrl.reverse();
    setState(() => _paso = 1);
    _ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    return WillPopScope(
      onWillPop: () async {
        if (_paso == 1) {
          await _ctrl.reverse();
          setState(() => _paso = 0);
          _ctrl.forward();
          return false;
        }
        return true; // En paso 0 permite salir de la app
      },
      child: Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: _paso == 0
                ? _buildBienvenida(dark, bg, prim, sec, div, surf)
                : _buildElegir(dark, bg, prim, sec, div, surf),
          ),
        ),
      ),
    ),  // Scaffold
    );  // WillPopScope
  }

  // ── Paso 0: pantalla de bienvenida ──
  Widget _buildBienvenida(bool dark, Color bg, Color prim, Color sec, Color div, Color surf) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Logo / glifo
          _LogoTransit(dark: dark, size: 90),
          const SizedBox(height: 32),

          Text('TRANSIT', style: NothingTheme.heading.copyWith(
              color: prim, fontSize: 40, letterSpacing: 2)),
          Text('APP', style: NothingTheme.heading.copyWith(
              color: NothingTheme.accentGreen, fontSize: 40, letterSpacing: 2)),

          const SizedBox(height: 16),
          Container(height: 0.5, color: div),
          const SizedBox(height: 16),

          Text('Transporte público inteligente\npara Cochabamba.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 13, color: sec,
                  height: 1.6)),

          const Spacer(flex: 2),

          // Punto decorativo
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 6, height: 6,
                decoration: BoxDecoration(
                    color: NothingTheme.accentGreen,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: NothingTheme.accentGreen.withOpacity(0.5),
                        blurRadius: 8)])),
            const SizedBox(width: 8),
            Text('PRIMERA VEZ', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                letterSpacing: 3, color: sec)),
          ]),
          const SizedBox(height: 24),

          _OnboardBtn(
            label: 'COMENZAR',
            filled: true,
            color: prim,
            onTap: _animarSiguiente,
            dark: dark,
          ),
          const SizedBox(height: 12),
          _OnboardBtn(
            label: 'YA TENGO CUENTA',
            filled: false,
            color: prim,
            onTap: () async {
              await widget.storageService.marcarLanzamiento();
              Navigator.of(context).pushNamed('/login');
            },
            dark: dark,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Paso 1: elegir tipo de cuenta ──
  Widget _buildElegir(bool dark, Color bg, Color prim, Color sec, Color div, Color surf) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 1),

          _LogoTransit(dark: dark, size: 56),
          const SizedBox(height: 28),

          Text('¿CÓMO QUIERES\nUSAR LA APP?',
              textAlign: TextAlign.center,
              style: NothingTheme.heading.copyWith(
                  color: prim, fontSize: 26, letterSpacing: 1, height: 1.2)),
          const SizedBox(height: 8),
          Text('Puedes cambiar de modo en Ajustes.',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec)),

          const Spacer(flex: 1),

          // Card Pasajero
          _TipoCard(
            icon: Icons.person_outline,
            titulo: 'PASAJERO',
            desc: _cuentasRegistradas.contains('usuario')
                ? 'Ya tienes una cuenta de pasajero.'
                : 'Paga tu tarifa con QR, recarga saldo\ny sigue tus viajes.',
            color: NothingTheme.accentBlue,
            disabled: _cuentasRegistradas.contains('usuario'),
            dark: dark, div: div, surf: surf, prim: prim, sec: sec,
            onTap: _cuentasRegistradas.contains('usuario') ? null : () async {
              await widget.storageService.marcarLanzamiento();
              await widget.storageService.guardarTipoSesion('usuario');
              Navigator.of(context).pushNamed('/registro-escanear');
            },
          ),
          const SizedBox(height: 16),

          // Card Conductor
          _TipoCard(
            icon: Icons.directions_bus_outlined,
            titulo: 'CONDUCTOR',
            desc: _cuentasRegistradas.contains('conductor')
                ? 'Ya tienes una cuenta de conductor.'
                : 'Escanea QR de pasajeros,\ngestiona tus viajes y ganancias.',
            color: NothingTheme.accentOrange,
            disabled: _cuentasRegistradas.contains('conductor'),
            dark: dark, div: div, surf: surf, prim: prim, sec: sec,
            onTap: _cuentasRegistradas.contains('conductor') ? null : () async {
              await widget.storageService.marcarLanzamiento();
              await widget.storageService.guardarTipoSesion('conductor');
              Navigator.of(context).pushNamed('/registro-conductor');
            },
          ),

          const Spacer(flex: 1),

          // Volver
          GestureDetector(
            onTap: () async {
              await _ctrl.reverse();
              setState(() => _paso = 0);
              _ctrl.forward();
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.arrow_back_ios, size: 12, color: sec),
              const SizedBox(width: 4),
              Text('VOLVER', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 10,
                  letterSpacing: 2, color: sec)),
            ]),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Logo Transit ──
class _LogoTransit extends StatelessWidget {
  final bool dark;
  final double size;
  const _LogoTransit({required this.dark, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: NothingTheme.surf(dark),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: NothingTheme.div(dark), width: 0.5),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20, spreadRadius: 2)],
      ),
      child: Center(
        child: Icon(Icons.directions_bus_rounded,
            size: size * 0.52,
            color: NothingTheme.accentGreen),
      ),
    );
  }
}

// ── Botón onboarding ──
class _OnboardBtn extends StatelessWidget {
  final String label;
  final bool filled, dark;
  final Color color;
  final VoidCallback onTap;
  const _OnboardBtn({required this.label, required this.filled,
      required this.color, required this.onTap, required this.dark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: filled ? Colors.transparent : color.withOpacity(0.4),
              width: 0.5),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 2,
              color: filled
                  ? (NothingTheme.bg(dark))
                  : color)),
        ),
      ),
    );
  }
}

// ── Card de tipo de usuario ──
class _TipoCard extends StatelessWidget {
  final IconData icon;
  final String titulo, desc;
  final Color color;
  final bool dark;
  final bool disabled;
  final Color div, surf, prim, sec;
  final VoidCallback? onTap;

  const _TipoCard({required this.icon, required this.titulo,
      required this.desc, required this.color, required this.dark,
      required this.div, required this.surf, required this.prim,
      required this.sec, required this.onTap, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? sec : color;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surf,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: disabled ? div : color.withOpacity(0.35),
                width: disabled ? 0.5 : 1),
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: effectiveColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: effectiveColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(titulo, style: TextStyle(
                      fontFamily: 'monospace', fontSize: 14,
                      fontWeight: FontWeight.w900, letterSpacing: 1.5,
                      color: disabled ? sec : prim)),
                  if (disabled) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NothingTheme.accentGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('YA REGISTRADO', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 7,
                          fontWeight: FontWeight.w700, letterSpacing: 1,
                          color: NothingTheme.accentGreen)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(
                    fontFamily: 'monospace', fontSize: 10,
                    color: sec, height: 1.5)),
              ],
            )),
            if (!disabled)
              Icon(Icons.arrow_forward_ios, size: 12, color: color),
          ]),
        ),
      ),
    );
  }
}