import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class LoginScreen extends StatefulWidget {
  final SupabaseService supabaseService;
  final StorageService  storageService;

  const LoginScreen({
    required this.supabaseService,
    required this.storageService,
    super.key,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _ciCtrl  = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _ocultarPin = true;
  bool _cargando   = false;

  // Biometría
  final _localAuth   = LocalAuthentication();
  bool _bioDisponible  = false;
  bool _bioConfigurada = false;
  // CI guardado del último login exitoso para bio
  String? _ciGuardado;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    themeNotifier.addListener(_rebuild);
    _verificarBiometria();
  }

  @override
  void dispose() {
    _ciCtrl.dispose();
    _pinCtrl.dispose();
    _pulseCtrl.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // ── Verificar si el dispositivo soporta biometría ──
  Future<void> _verificarBiometria() async {
    try {
      final disponible = await _localAuth.canCheckBiometrics;
      final tipos      = await _localAuth.getAvailableBiometrics();
      final ciGuardado = widget.storageService.obtenerCIBio();

      setState(() {
        _bioDisponible   = disponible && tipos.isNotEmpty;
        _bioConfigurada  = ciGuardado != null && ciGuardado.isNotEmpty;
        _ciGuardado      = ciGuardado;
      });
    } catch (_) {
      setState(() { _bioDisponible = false; _bioConfigurada = false; });
    }
  }

  // ── Login con huella ──
  Future<void> _loginConHuella() async {
    if (!_bioDisponible || !_bioConfigurada || _ciGuardado == null) return;
    setState(() => _cargando = true);
    try {
      final autenticado = await _localAuth.authenticate(
        localizedReason: 'Confirma tu identidad para ingresar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!autenticado) {
        setState(() => _cargando = false);
        return;
      }

      // Obtener pin cifrado guardado y hacer login automático
      final pinGuardado = widget.storageService.obtenerPINBio();
      if (pinGuardado == null) {
        _mostrarError('No hay sesión guardada. Ingresa con CI y PIN.');
        setState(() => _cargando = false);
        return;
      }

      final resultado = await widget.supabaseService.login(
        ci: _ciGuardado!,
        pin: pinGuardado,
      );

      if (!mounted) return;
      if (resultado['exito'] == true) {
        final usuario = resultado['usuario'];
        await widget.storageService.guardarUsuario(usuario);
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        _mostrarError('Sesión expirada. Ingresa con CI y PIN.');
        widget.storageService.limpiarBio();
        setState(() { _bioConfigurada = false; _ciGuardado = null; });
      }
    } catch (e) {
      _mostrarError('Error biométrico: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ── Login normal ──
  Future<void> _iniciarSesion() async {
    if (_ciCtrl.text.isEmpty || _pinCtrl.text.isEmpty) {
      _mostrarError('Completa CI y PIN'); return;
    }
    if (!ValidatorsHelper.esValidoCI(_ciCtrl.text)) {
      _mostrarError('CI inválido (7-10 dígitos)'); return;
    }
    if (!ValidatorsHelper.esValidoPIN(_pinCtrl.text)) {
      _mostrarError('PIN debe tener 4 dígitos'); return;
    }

    setState(() => _cargando = true);
    try {
      final resultado = await widget.supabaseService.login(
        ci:  _ciCtrl.text.trim(),
        pin: _pinCtrl.text.trim(),
      );
      if (!mounted) return;

      if (resultado['exito'] == true) {
        final usuario = resultado['usuario'];
        await widget.storageService.guardarUsuario(usuario);

        // Ofrecer guardar biometría si está disponible y no configurada
        if (_bioDisponible && !_bioConfigurada && mounted) {
          final guardar = await _mostrarDialogoBio();
          if (guardar == true) {
            await widget.storageService.guardarCIBio(_ciCtrl.text.trim());
            await widget.storageService.guardarPINBio(_pinCtrl.text.trim());
            setState(() {
              _bioConfigurada = true;
              _ciGuardado     = _ciCtrl.text.trim();
            });
          }
        }

        if (mounted) Navigator.of(context).pushReplacementNamed('/home');
      } else {
        _mostrarError(resultado['mensaje'] ?? 'CI o PIN incorrecto');
      }
    } catch (e) {
      _mostrarError('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<bool?> _mostrarDialogoBio() {
    final dark = themeNotifier.isDark;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NothingTheme.surf(dark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.fingerprint, color: NothingTheme.accentGreen, size: 22),
          const SizedBox(width: 10),
          Text('ACCESO RÁPIDO', style: TextStyle(
              fontFamily: 'monospace', fontSize: 12,
              fontWeight: FontWeight.w700, letterSpacing: 2,
              color: NothingTheme.prim(dark))),
        ]),
        content: Text(
          '¿Activar ingreso con huella dactilar para la próxima vez?',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              color: NothingTheme.sec(dark))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('AHORA NO', style: TextStyle(
                fontFamily: 'monospace', fontSize: 10,
                color: NothingTheme.sec(dark))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ACTIVAR', style: TextStyle(
                fontFamily: 'monospace', fontSize: 10,
                fontWeight: FontWeight.w700,
                color: NothingTheme.accentGreen)),
          ),
        ],
      ),
    );
  }

  void _mostrarError(String m) {
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

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),

                // ── Punto verde Nothing ──
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: NothingTheme.accentGreen,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: NothingTheme.accentGreen.withOpacity(0.5),
                        blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 20),

                Text('ACCESO', style: NothingTheme.heading.copyWith(
                    color: prim)),
                Text('TRANSITAPP', style: NothingTheme.heading.copyWith(
                    color: prim)),
                const SizedBox(height: 8),
                Text('Ingresa con tu Carnet de Identidad',
                    style: TextStyle(fontFamily: 'monospace',
                        fontSize: 12, color: sec)),
                const SizedBox(height: 40),

                // ── Huella (si disponible y configurada) ──
                if (_bioDisponible && _bioConfigurada) ...[
                  _buildBioBtn(dark, prim, sec, div, surf),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(child: Container(height: 0.5, color: div)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('O CON CI + PIN', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 8,
                          letterSpacing: 2, color: sec)),
                    ),
                    Expanded(child: Container(height: 0.5, color: div)),
                  ]),
                  const SizedBox(height: 24),
                ],

                // ── Campo CI ──
                NothingTextField(
                  label: 'CARNET DE IDENTIDAD',
                  hint: 'Ej: 12345678',
                  controller: _ciCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !_cargando,
                ),
                const SizedBox(height: 20),

                // ── Campo PIN ──
                NothingTextField(
                  label: 'PIN',
                  hint: '• • • •',
                  controller: _pinCtrl,
                  obscureText: _ocultarPin,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  enabled: !_cargando,
                  suffixIcon: Icon(
                      _ocultarPin ? Icons.visibility_off : Icons.visibility,
                      size: 18, color: sec),
                  onSuffixTap: () =>
                      setState(() => _ocultarPin = !_ocultarPin),
                ),
                const SizedBox(height: 28),

                // ── Botón ingresar ──
                NothingButton(
                  label: 'INICIAR SESIÓN',
                  onTap: _iniciarSesion,
                  isLoading: _cargando,
                  filled: true,
                ),
                const SizedBox(height: 12),
                NothingButton(
                  label: 'CREAR CUENTA',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/registro-escanear'),
                  filled: false,
                ),
                const SizedBox(height: 24),

                // ── Divisor ──
                Row(children: [
                  Expanded(child: Container(height: 0.5, color: div)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('O', style: TextStyle(
                        fontFamily: 'monospace', fontSize: 8,
                        letterSpacing: 2, color: sec)),
                  ),
                  Expanded(child: Container(height: 0.5, color: div)),
                ]),
                const SizedBox(height: 24),

                NothingButton(
                  label: 'ACCESO CONDUCTORES',
                  onTap: () => Navigator.of(context).pushNamed('/login-conductor'),
                  filled: false,
                  color: NothingTheme.accentOrange,
                  icon: Icons.directions_bus,
                ),
                const SizedBox(height: 20),

                // ── Nota ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: NothingTheme.accentBlue.withOpacity(0.3),
                        width: 0.5),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: NothingTheme.accentBlue, size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Solo puedes tener UNA cuenta por Carnet de Identidad.',
                      style: TextStyle(fontFamily: 'monospace',
                          fontSize: 11, color: sec),
                    )),
                  ]),
                ),
                const SizedBox(height: 32),

                Center(child: Text('TransitApp v1.0.0',
                    style: TextStyle(fontFamily: 'monospace',
                        fontSize: 9, letterSpacing: 2, color: sec))),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Widget del botón de huella ──
  Widget _buildBioBtn(bool dark, Color prim, Color sec, Color div, Color surf) {
    return GestureDetector(
      onTap: _cargando ? null : _loginConHuella,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: NothingTheme.accentGreen.withOpacity(0.4), width: 0.5),
        ),
        child: Column(children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Transform.scale(
                scale: _pulseAnim.value, child: child),
            child: const Icon(Icons.fingerprint, size: 52,
                color: NothingTheme.accentGreen),
          ),
          const SizedBox(height: 10),
          Text('INGRESAR CON HUELLA', style: TextStyle(
              fontFamily: 'monospace', fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 2,
              color: prim)),
          const SizedBox(height: 4),
          Text(_ciGuardado != null ? 'CI: $_ciGuardado' : '',
              style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9, color: sec)),
        ]),
      ),
    );
  }
}
