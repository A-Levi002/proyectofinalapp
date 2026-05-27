import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../models/usuario_model.dart';

/// Pantalla que aparece al abrir la app cuando ya hay sesión guardada.
/// Requiere huella o PIN antes de entrar. Reemplaza al login normal.
class BienvenidaScreen extends StatefulWidget {
  final StorageService  storageService;
  final SupabaseService supabaseService;
  const BienvenidaScreen({
    required this.storageService,
    required this.supabaseService,
    super.key,
  });

  @override
  State<BienvenidaScreen> createState() => _BienvenidaScreenState();
}

class _BienvenidaScreenState extends State<BienvenidaScreen>
    with SingleTickerProviderStateMixin {

  final _localAuth = LocalAuthentication();
  bool _bioDisponible  = false;
  bool _bioConfigurada = false;
  bool _cargando       = false;
  bool _mostrarPin     = false;
  bool _ocultarPin     = true;
  final _pinCtrl = TextEditingController();

  UsuarioModel? _usuario;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.90, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fadeAnim  = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeIn);
    themeNotifier.addListener(_rebuild);
    _init();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _pinCtrl.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _init() async {
    _usuario = widget.storageService.obtenerUsuario();
    try {
      final disp  = await _localAuth.canCheckBiometrics;
      final tipos = await _localAuth.getAvailableBiometrics();
      final ci    = widget.storageService.obtenerCIBio();
      setState(() {
        _bioDisponible  = disp && tipos.isNotEmpty;
        _bioConfigurada = ci != null && ci.isNotEmpty;
      });
    } catch (_) {
      setState(() { _bioDisponible = false; _bioConfigurada = false; });
    }

    // Desbloquear automáticamente con huella si está configurada
    if (_bioDisponible && _bioConfigurada) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _autenticarConHuella();
    }
  }

  // ── Autenticar con huella ──
  Future<void> _autenticarConHuella() async {
    if (!_bioDisponible || !_bioConfigurada) return;
    setState(() => _cargando = true);
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Confirma tu identidad para ingresar',
        options: const AuthenticationOptions(
            biometricOnly: true, stickyAuth: true, useErrorDialogs: true),
      );
      if (!ok || !mounted) { setState(() => _cargando = false); return; }

      final pinGuardado = widget.storageService.obtenerPINBio();
      final ciGuardado  = widget.storageService.obtenerCIBio();
      if (pinGuardado == null || ciGuardado == null) {
        _snack('No hay sesión guardada. Usa CI y PIN.');
        setState(() => _cargando = false);
        return;
      }

      final res = await widget.supabaseService.login(
          ci: ciGuardado, pin: pinGuardado);
      if (!mounted) return;

      if (res['exito'] == true) {
        await widget.storageService.guardarUsuario(res['usuario']);
        await widget.storageService.desbloquearApp();
        _navegar();
      } else {
        _snack('Sesión expirada. Usa CI y PIN.');
        widget.storageService.limpiarBio();
        setState(() { _bioConfigurada = false; _cargando = false; });
      }
    } catch (e) {
      _snack('Error: $e');
      setState(() => _cargando = false);
    }
  }

  // ── Login con PIN ──
  Future<void> _loginConPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 4) { _snack('PIN debe tener 4 dígitos'); return; }
    final ci = widget.storageService.obtenerCiGuardado();
    if (ci == null) { _snack('Sin sesión guardada'); return; }

    setState(() => _cargando = true);
    try {
      final res = await widget.supabaseService.login(ci: ci, pin: pin);
      if (!mounted) return;
      if (res['exito'] == true) {
        await widget.storageService.guardarUsuario(res['usuario']);
        await widget.storageService.desbloquearApp();

        // Si aún no tenía bio guardado, guardar PIN ahora
        if (!_bioConfigurada) {
          await widget.storageService.guardarCIBio(ci);
          await widget.storageService.guardarPINBio(pin);
        }
        _navegar();
      } else {
        _snack(res['mensaje'] ?? 'PIN incorrecto');
      }
    } catch (e) {
      _snack('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _navegar() {
    final tipo = widget.storageService.obtenerTipoSesion();
    if (tipo == 'conductor') {
      Navigator.of(context).pushReplacementNamed('/panel-conductor');
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _cerrarSesionYCambiar() async {
    final dark = themeNotifier.isDark;
    final tipoActual = widget.storageService.obtenerTipoSesion();

    await showModalBottomSheet(
      context: context,
      backgroundColor: NothingTheme.surf(dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final prim = NothingTheme.prim(dark);
        final sec  = NothingTheme.sec(dark);
        final div  = NothingTheme.div(dark);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 3,
                decoration: BoxDecoration(color: div,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('CAMBIAR MODO', style: TextStyle(
                fontFamily: 'monospace', fontSize: 13,
                fontWeight: FontWeight.w900, letterSpacing: 2, color: prim)),
            const SizedBox(height: 6),
            Text('Selecciona la cuenta a la que quieres acceder',
                style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: sec)),
            const SizedBox(height: 24),

            _BottomSheetBtn(
              icon: Icons.person_outline,
              label: 'PASAJERO',
              sublabel: tipoActual == 'usuario' ? 'Cuenta activa' : 'Cambiar a pasajero',
              color: NothingTheme.accentBlue,
              disabled: tipoActual == 'usuario',
              dark: dark,
              onTap: tipoActual == 'usuario' ? null : () async {
                Navigator.pop(context);
                await widget.storageService.guardarTipoSesion('usuario');
                if (mounted) Navigator.of(context).pushReplacementNamed('/login');
              },
            ),
            const SizedBox(height: 12),

            _BottomSheetBtn(
              icon: Icons.directions_bus_outlined,
              label: 'CONDUCTOR',
              sublabel: tipoActual == 'conductor' ? 'Cuenta activa' : 'Cambiar a conductor',
              color: NothingTheme.accentOrange,
              disabled: tipoActual == 'conductor',
              dark: dark,
              onTap: tipoActual == 'conductor' ? null : () async {
                Navigator.pop(context);
                await widget.storageService.guardarTipoSesion('conductor');
                if (mounted) Navigator.of(context).pushReplacementNamed('/login-conductor');
              },
            ),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await widget.storageService.limpiarSesion();
                await widget.storageService.limpiarBio();
                if (mounted) Navigator.of(context).pushReplacementNamed('/login');
              },
              child: Text('Cerrar sesión completamente',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                      color: NothingTheme.error)),
            ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: NothingTheme.error,
        duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    final nombre   = _usuario?.nombre   ?? '';
    final apellido = _usuario?.apellido ?? '';

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _mostrarPin
                ? _buildPinView(dark, bg, prim, sec, div, surf)
                : _buildBioView(dark, bg, prim, sec, div, surf, nombre, apellido),
          ),
        ),
      ),
    );
  }

  Widget _buildBioView(bool dark, Color bg, Color prim, Color sec,
      Color div, Color surf, String nombre, String apellido) {
    return Padding(
      key: const ValueKey('bio'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(children: [
        const SizedBox(height: 56),

        // ── Logo + nombre app ──
        Center(child: Column(children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: div, width: 0.5),
              boxShadow: [BoxShadow(
                color: NothingTheme.accentGreen.withOpacity(0.12),
                blurRadius: 20, spreadRadius: 2,
              )],
            ),
            child: const Center(child: Icon(Icons.directions_bus_rounded,
                size: 36, color: NothingTheme.accentGreen)),
          ),
          const SizedBox(height: 16),
          Text('TRANSITAPP', style: TextStyle(
              fontFamily: 'monospace', fontSize: 20,
              fontWeight: FontWeight.w900, letterSpacing: 3,
              color: prim)),
          const SizedBox(height: 4),
          Text('BIENVENIDO DE VUELTA', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              letterSpacing: 2.5, color: sec)),
        ])),

        const Spacer(flex: 2),

        // ── Nombre del usuario ──
        if (nombre.isNotEmpty) ...[
          Text('HOLA,', style: TextStyle(
              fontFamily: 'monospace', fontSize: 11,
              letterSpacing: 3, color: sec)),
          const SizedBox(height: 4),
          Text('${nombre.toUpperCase()} ${apellido.toUpperCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 22,
                  fontWeight: FontWeight.w900, letterSpacing: 1,
                  color: prim)),
          const SizedBox(height: 32),
        ],

        // ── Huella / lock ──
        if (_cargando)
          const CircularProgressIndicator(
              color: NothingTheme.accentGreen, strokeWidth: 2)
        else if (_bioDisponible && _bioConfigurada)
          GestureDetector(
            onTap: _autenticarConHuella,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _pulseAnim.value, child: child),
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NothingTheme.accentGreen.withOpacity(0.10),
                  border: Border.all(
                      color: NothingTheme.accentGreen.withOpacity(0.35),
                      width: 1),
                ),
                child: const Icon(Icons.fingerprint, size: 56,
                    color: NothingTheme.accentGreen),
              ),
            ),
          )
        else
          Icon(Icons.lock_outline, size: 56, color: sec),

        const SizedBox(height: 16),

        if (!_cargando && _bioDisponible && _bioConfigurada)
          Text('TOCA PARA INGRESAR', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              letterSpacing: 3, color: sec))
        else if (!_cargando && (!_bioDisponible || !_bioConfigurada))
          Text('INGRESA CON TU PIN', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              letterSpacing: 3, color: sec)),

        const Spacer(flex: 2),

        _BtnAccion(
          label: 'USAR PIN',
          icon: Icons.pin_outlined,
          color: prim,
          surf: surf, div: div, prim: prim,
          filled: false,
          onTap: () => setState(() => _mostrarPin = true),
        ),
        const SizedBox(height: 10),
        _BtnAccion(
          label: 'CAMBIAR CUENTA',
          icon: Icons.swap_horiz,
          color: NothingTheme.error,
          surf: surf, div: div, prim: prim,
          filled: false,
          onTap: _cerrarSesionYCambiar,
        ),
        const SizedBox(height: 20),
        Center(child: Text('TransitApp v1.0.0', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            letterSpacing: 2, color: sec.withOpacity(0.4)))),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildPinView(bool dark, Color bg, Color prim, Color sec,
      Color div, Color surf) {
    return Padding(
      key: const ValueKey('pin'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          IconButton(
            icon: Icon(Icons.arrow_back, color: prim, size: 20),
            onPressed: () => setState(() { _mostrarPin = false; _pinCtrl.clear(); }),
            padding: EdgeInsets.zero,
          ),
          const Spacer(flex: 1),

          Center(child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: div, width: 0.5),
            ),
            child: const Center(child: Icon(Icons.directions_bus_rounded,
                size: 28, color: NothingTheme.accentGreen)),
          )),
          const SizedBox(height: 24),

          Center(child: Text('INGRESA TU PIN', style: TextStyle(
              fontFamily: 'monospace', fontSize: 13,
              fontWeight: FontWeight.w700, letterSpacing: 3, color: prim))),
          const SizedBox(height: 4),
          Center(child: Text('Para verificar tu identidad',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec))),

          const Spacer(flex: 1),

          Container(
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: div, width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _pinCtrl,
              obscureText: _ocultarPin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              style: TextStyle(fontFamily: 'monospace',
                  fontSize: 24, letterSpacing: 12, color: prim),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • •',
                hintStyle: TextStyle(fontFamily: 'monospace',
                    fontSize: 20, letterSpacing: 8, color: sec.withOpacity(0.4)),
                border: InputBorder.none,
                suffixIcon: IconButton(
                  icon: Icon(_ocultarPin
                      ? Icons.visibility_off : Icons.visibility,
                      size: 18, color: sec),
                  onPressed: () => setState(() => _ocultarPin = !_ocultarPin),
                ),
              ),
              onSubmitted: (_) => _loginConPin(),
            ),
          ),

          const SizedBox(height: 24),

          _BtnAccion(
            label: _cargando ? 'VERIFICANDO...' : 'CONFIRMAR',
            icon: Icons.check,
            color: NothingTheme.accentGreen,
            surf: surf, div: div, prim: prim,
            filled: true,
            onTap: _cargando ? null : _loginConPin,
          ),

          const Spacer(flex: 1),

          if (_bioDisponible && _bioConfigurada)
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() { _mostrarPin = false; _pinCtrl.clear(); });
                  Future.delayed(const Duration(milliseconds: 200),
                      _autenticarConHuella);
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.fingerprint,
                      size: 18, color: NothingTheme.accentGreen),
                  const SizedBox(width: 6),
                  Text('Usar huella', style: TextStyle(
                      fontFamily: 'monospace', fontSize: 11,
                      color: NothingTheme.accentGreen)),
                ]),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Botón reutilizable ──
class _BtnAccion extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color, surf, div, prim;
  final bool filled;
  final VoidCallback? onTap;

  const _BtnAccion({required this.label, required this.icon,
      required this.color, required this.surf, required this.div,
      required this.prim, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: filled ? Colors.transparent : color.withOpacity(0.35),
              width: 0.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: filled ? Colors.black : color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 2,
              color: filled ? Colors.black : color)),
        ]),
      ),
    );
  }
}

// ── Botón para BottomSheet ──
class _BottomSheetBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final bool disabled;
  final bool dark;
  final VoidCallback? onTap;

  const _BottomSheetBtn({required this.icon, required this.label,
      required this.sublabel, required this.color, required this.disabled,
      required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: disabled ? surf.withOpacity(0.5) : surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: div, width: 0.5),
        ),
        child: Row(children: [
          Icon(icon, size: 24, color: disabled ? sec.withOpacity(0.5) : color),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontFamily: 'monospace',
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: disabled ? sec.withOpacity(0.5) : prim)),
              const SizedBox(height: 2),
              Text(sublabel, style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9,
                  color: disabled ? sec.withOpacity(0.4) : sec)),
            ],
          )),
          if (disabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: NothingTheme.accentGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('ACTIVA', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: NothingTheme.accentGreen)),
            )
          else
            Icon(Icons.arrow_forward_ios, size: 12,
                color: NothingTheme.sec(dark)),
        ]),
      ),
    );
  }
}