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

  final _localAuth    = LocalAuthentication();
  bool _bioDisponible  = false;
  bool _bioConfigurada = false;

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

  Future<void> _verificarBiometria() async {
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
  }

  Future<void> _iniciarSesion() async {
    if (_ciCtrl.text.isEmpty || _pinCtrl.text.isEmpty) {
      _snack('Completa CI y PIN'); return;
    }
    if (!ValidatorsHelper.esValidoCI(_ciCtrl.text)) {
      _snack('CI inválido (7-10 dígitos)'); return;
    }
    if (!ValidatorsHelper.esValidoPIN(_pinCtrl.text)) {
      _snack('PIN debe tener 4 dígitos'); return;
    }

    setState(() => _cargando = true);
    try {
      final res = await widget.supabaseService.login(
          ci: _ciCtrl.text.trim(), pin: _pinCtrl.text.trim());
      if (!mounted) return;

      if (res['exito'] == true) {
        final usuario = res['usuario'];
        await widget.storageService.guardarUsuario(usuario);
        await widget.storageService.guardarTipoSesion('usuario');
        await widget.storageService.marcarCuentaRegistrada('usuario');
        await widget.storageService.desbloquearApp();

        // Ofrecer biometría si no está configurada
        if (_bioDisponible && !_bioConfigurada && mounted) {
          final guardar = await _mostrarDialogoBio();
          if (guardar == true) {
            await widget.storageService.guardarCIBio(_ciCtrl.text.trim());
            await widget.storageService.guardarPINBio(_pinCtrl.text.trim());
            setState(() => _bioConfigurada = true);
          }
        }

        if (mounted) Navigator.of(context).pushReplacementNamed('/home');
      } else {
        _snack(res['mensaje'] ?? 'CI o PIN incorrecto');
      }
    } catch (e) {
      _snack('Error de conexión: $e');
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
          const Icon(Icons.fingerprint,
              color: NothingTheme.accentGreen, size: 22),
          const SizedBox(width: 10),
          Text('ACCESO RÁPIDO', style: TextStyle(
              fontFamily: 'monospace', fontSize: 12,
              fontWeight: FontWeight.w700, letterSpacing: 2,
              color: NothingTheme.prim(dark))),
        ]),
        content: Text('¿Activar ingreso con huella la próxima vez?',
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

  void _snack(String m) {
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
      onWillPop: () async {
        // Si viene del onboarding, volver allá
        if (Navigator.of(context).canPop()) return true;
        Navigator.of(context).pushReplacementNamed('/onboarding');
        return false;
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),

                // Logo centrado
                Center(child: Column(children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: surf,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: div, width: 0.5),
                    ),
                    child: const Center(child: Icon(
                        Icons.directions_bus_rounded,
                        size: 36, color: NothingTheme.accentGreen)),
                  ),
                  const SizedBox(height: 20),
                  Text('TRANSITAPP', style: TextStyle(
                      fontFamily: 'monospace', fontSize: 20,
                      fontWeight: FontWeight.w900, letterSpacing: 3,
                      color: prim)),
                ])),
                const SizedBox(height: 48),

                // ── Huella (si configurada) ──
                if (_bioDisponible && _bioConfigurada) ...[
                  GestureDetector(
                    onTap: () => Navigator.of(context)
                        .pushReplacementNamed('/bienvenida'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: surf,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: NothingTheme.accentGreen.withOpacity(0.4),
                            width: 0.5),
                      ),
                      child: Column(children: [
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, child) => Transform.scale(
                              scale: _pulseAnim.value, child: child),
                          child: const Icon(Icons.fingerprint,
                              size: 44, color: NothingTheme.accentGreen),
                        ),
                        const SizedBox(height: 8),
                        Text('INGRESAR CON HUELLA', style: TextStyle(
                            fontFamily: 'monospace', fontSize: 10,
                            fontWeight: FontWeight.w700, letterSpacing: 2,
                            color: prim)),
                      ]),
                    ),
                  ),
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

                // ── CI ──
                NothingTextField(
                  label: 'CARNET DE IDENTIDAD',
                  hint: 'Ej: 12345678',
                  controller: _ciCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !_cargando,
                ),
                const SizedBox(height: 20),

                // ── PIN ──
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

                NothingButton(
                  label: 'INICIAR SESIÓN',
                  onTap: _iniciarSesion,
                  isLoading: _cargando,
                  filled: true,
                ),



                const SizedBox(height: 32),

                Center(child: Text('TransitApp v1.0.0', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    letterSpacing: 2, color: sec.withOpacity(0.5)))),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}