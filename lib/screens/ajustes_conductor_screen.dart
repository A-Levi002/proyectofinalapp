import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';

class AjustesConductorScreen extends StatefulWidget {
  const AjustesConductorScreen({super.key});
  @override State<AjustesConductorScreen> createState() => _AjustesConductorScreenState();
}

class _AjustesConductorScreenState extends State<AjustesConductorScreen> {
  // Notificaciones
  bool _notifViajes    = true;
  bool _notifPagos     = true;
  bool _notifContrato  = true;
  bool _notifAlerts    = false;

  // GPS
  bool _gpsAutoStart   = false;
  bool _gpsBackground  = true;

  // Biometría
  bool _bioDisponible  = false;
  bool _bioActivada    = false;
  final _localAuth     = LocalAuthentication();
  late StorageService  _store;

  @override
  void initState() {
    super.initState();
    _store = StorageService();
    themeNotifier.addListener(_rebuild);
    _cargarEstadoBio();
  }

  @override void dispose() { themeNotifier.removeListener(_rebuild); super.dispose(); }
  void _rebuild() => setState(() {});

  Future<void> _cargarEstadoBio() async {
    await _store.init();
    try {
      final disp  = await _localAuth.canCheckBiometrics;
      final tipos = await _localAuth.getAvailableBiometrics();
      final ci    = _store.obtenerCIBio();
      setState(() {
        _bioDisponible = disp && tipos.isNotEmpty;
        _bioActivada   = ci != null && ci.isNotEmpty;
      });
    } catch (_) {
      setState(() { _bioDisponible = false; _bioActivada = false; });
    }
  }

  Future<void> _toggleBio(bool activar) async {
    if (activar) {
      try {
        final ok = await _localAuth.authenticate(
          localizedReason: 'Confirma tu huella para activar el acceso biométrico',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );
        if (!ok) return;
        final ci = _store.obtenerCIBio();
        if (ci == null || ci.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Primero inicia sesión con CI y PIN para activar la huella.',
                  style: TextStyle(fontFamily: 'monospace')),
              backgroundColor: NothingTheme.accentOrange,
            ));
          }
          return;
        }
        setState(() => _bioActivada = true);
        _snack('✓ Acceso con huella activado');
      } catch (_) {
        setState(() => _bioActivada = false);
      }
    } else {
      await _store.limpiarBio();
      setState(() => _bioActivada = false);
      _snack('Acceso biométrico desactivado');
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: error ? NothingTheme.error : NothingTheme.accentGreen));
  }

  void _mostrarAcercaDe() {
    final dark = themeNotifier.isDark;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: NothingTheme.surf(dark),
      title: const Text('ACERCA DE', style: TextStyle(fontFamily: 'monospace',
          fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2)),
      content: Text('TransitApp v1.0.0 — Panel Conductor\n'
          'Sistema de transporte público con pagos electrónicos.\n'
          'Diseñado con estilo Nothing Phone.',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              color: NothingTheme.sec(dark))),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('CERRAR'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    return Scaffold(
      backgroundColor: bg,
      appBar: const NothingAppBar(title: 'AJUSTES'),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Apariencia ──
        _SecLabel(text: 'APARIENCIA', sec: sec),
        const SizedBox(height: 12),
        NothingCard(child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(dark ? Icons.dark_mode : Icons.light_mode, size: 18, color: prim),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('MODO', style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1, color: prim)),
                Text(dark ? 'Oscuro' : 'Claro', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 10, color: sec)),
              ]),
            ]),
            const NothingThemeToggle(),
          ],
        )),
        const SizedBox(height: 8),

        // Preview colores
        NothingCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('VISTA PREVIA', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
          const SizedBox(height: 12),
          Row(children: [
            _ColorDot(color: NothingTheme.prim(dark), label: 'PRIMARIO',
                border: dark ? null : NothingTheme.dividerLight),
            const SizedBox(width: 12),
            _ColorDot(color: surf, label: 'SUPERFICIE', border: div),
            const SizedBox(width: 12),
            const _ColorDot(color: NothingTheme.accentOrange, label: 'CONDUCTOR'),
            const SizedBox(width: 12),
            const _ColorDot(color: NothingTheme.accentGreen, label: 'ACTIVO'),
          ]),
          const SizedBox(height: 12),
          _GlyphLines(isDark: dark),
        ])),

        const SizedBox(height: 24),
        Divider(color: div),
        const SizedBox(height: 24),

        // ── Notificaciones ──
        _SecLabel(text: 'NOTIFICACIONES', sec: sec),
        const SizedBox(height: 12),
        NothingCard(child: Column(children: [
          _SwitchRow(label: 'Nuevos viajes', sublabel: 'Cuando un pasajero escanea tu QR',
              value: _notifViajes, isDark: dark,
              onChanged: (v) => setState(() => _notifViajes = v)),
          Divider(color: div, height: 1),
          _SwitchRow(label: 'Pagos acreditados', sublabel: 'Comisiones confirmadas',
              value: _notifPagos, isDark: dark,
              onChanged: (v) => setState(() => _notifPagos = v)),
          Divider(color: div, height: 1),
          _SwitchRow(label: 'Contrato', sublabel: 'Cambios de estado del contrato',
              value: _notifContrato, isDark: dark,
              onChanged: (v) => setState(() => _notifContrato = v)),
          Divider(color: div, height: 1),
          _SwitchRow(label: 'Alertas de ruta', sublabel: 'Desvíos y cierres de vía',
              value: _notifAlerts, isDark: dark,
              onChanged: (v) => setState(() => _notifAlerts = v)),
        ])),

        const SizedBox(height: 24),
        Divider(color: div),
        const SizedBox(height: 24),

        // ── GPS ──
        _SecLabel(text: 'GPS Y UBICACIÓN', sec: sec),
        const SizedBox(height: 12),
        NothingCard(child: Column(children: [
          _SwitchRow(
            label: 'Inicio automático',
            sublabel: 'Activar GPS al abrir el panel',
            value: _gpsAutoStart, isDark: dark,
            icon: Icons.gps_fixed,
            iconColor: _gpsAutoStart ? NothingTheme.accentBlue : null,
            onChanged: (v) => setState(() => _gpsAutoStart = v),
          ),
          Divider(color: div, height: 1),
          _SwitchRow(
            label: 'GPS en segundo plano',
            sublabel: 'Continúa publicando ubicación',
            value: _gpsBackground, isDark: dark,
            icon: Icons.location_on,
            iconColor: _gpsBackground ? NothingTheme.accentGreen : null,
            onChanged: (v) => setState(() => _gpsBackground = v),
          ),
        ])),

        const SizedBox(height: 24),
        Divider(color: div),
        const SizedBox(height: 24),

        // ── Seguridad ──
        _SecLabel(text: 'SEGURIDAD', sec: sec),
        const SizedBox(height: 12),
        NothingCard(child: Column(children: [
          if (_bioDisponible) ...[
            _SwitchRow(
              label: 'Acceso con huella',
              sublabel: _bioActivada
                  ? 'Activado — toca para desactivar'
                  : 'Desactivado — toca para activar',
              value: _bioActivada, isDark: dark,
              icon: Icons.fingerprint,
              iconColor: _bioActivada ? NothingTheme.accentGreen : null,
              onChanged: _toggleBio,
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(children: [
                Icon(Icons.fingerprint, size: 18, color: sec.withOpacity(0.4)),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  'Tu dispositivo no tiene sensor de huella registrado',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec),
                )),
              ]),
            ),
          ],
        ])),

        const SizedBox(height: 24),
        Divider(color: div),
        const SizedBox(height: 24),

        // ── Cuenta conductor ──
        _SecLabel(text: 'CUENTA', sec: sec),
        const SizedBox(height: 12),
        NothingCard(child: Column(children: [
          _MenuRow(icon: Icons.person_outline, label: 'Mi perfil',
              isDark: dark, onTap: () => Navigator.pushNamed(context, '/perfil-conductor')),
          Divider(color: div, height: 1),
          _MenuRow(icon: Icons.receipt_long_outlined, label: 'Historial de pagos',
              isDark: dark, onTap: () => Navigator.pushNamed(context, '/panel-conductor')),
          Divider(color: div, height: 1),
          _MenuRow(icon: Icons.help_outline, label: 'Ayuda y soporte',
              isDark: dark, onTap: () {}),
          Divider(color: div, height: 1),
          _MenuRow(icon: Icons.info_outline, label: 'Acerca de',
              isDark: dark, onTap: _mostrarAcercaDe),
        ])),

        const SizedBox(height: 32),

        // ── Logo ──
        Center(child: Column(children: [
          _GlyphLogo(isDark: dark),
          const SizedBox(height: 12),
          Text('TRANSITAPP', style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 3, color: prim)),
          const SizedBox(height: 4),
          Text('v1.0.0 — Panel Conductor', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9, letterSpacing: 1, color: sec)),
        ])),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Widgets auxiliares (mismos del ajustes pasajero)
// ─────────────────────────────────────────────

class _SecLabel extends StatelessWidget {
  final String text; final Color sec;
  const _SecLabel({required this.text, required this.sec});
  @override Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontFamily: 'monospace', fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec));
}

class _ColorDot extends StatelessWidget {
  final Color color; final String label; final Color? border;
  const _ColorDot({required this.color, required this.label, this.border});
  @override Widget build(BuildContext context) => Column(children: [
    Container(width: 30, height: 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle,
            border: border != null ? Border.all(color: border!, width: 0.5) : null)),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 7,
        letterSpacing: 1, color: NothingTheme.secondary)),
  ]);
}

class _GlyphLines extends StatelessWidget {
  final bool isDark;
  const _GlyphLines({required this.isDark});
  @override Widget build(BuildContext context) {
    final c = isDark ? Colors.white : Colors.black;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 0.5, width: double.infinity, color: c.withOpacity(0.15)),
      const SizedBox(height: 4),
      Container(height: 0.5, width: 180, color: c.withOpacity(0.10)),
      const SizedBox(height: 4),
      Container(height: 0.5, width: 220, color: c.withOpacity(0.07)),
      const SizedBox(height: 4),
      Container(height: 0.5, width: 140, color: c.withOpacity(0.05)),
    ]);
  }
}

class _GlyphLogo extends StatelessWidget {
  final bool isDark;
  const _GlyphLogo({required this.isDark});
  @override Widget build(BuildContext context) => SizedBox(width: 48, height: 48,
      child: CustomPaint(painter: _GlyphPainter(
          color: isDark ? Colors.white : Colors.black)));
}

class _GlyphPainter extends CustomPainter {
  final Color color;
  const _GlyphPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = color.withOpacity(0.8)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final p2 = Paint()..color = color.withOpacity(0.4)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2 - 1, p1);
    final cx = size.width / 2; final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 10, cy - 6), Offset(cx + 10, cy - 6), p2);
    canvas.drawLine(Offset(cx - 7, cy),      Offset(cx + 7, cy),      p2);
    canvas.drawLine(Offset(cx - 10, cy + 6), Offset(cx + 10, cy + 6), p2);
  }
  @override bool shouldRepaint(_GlyphPainter o) => o.color != color;
}

class _SwitchRow extends StatelessWidget {
  final String label, sublabel;
  final bool value, isDark;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final Color? iconColor;
  const _SwitchRow({required this.label, required this.sublabel, required this.value,
      required this.isDark, required this.onChanged, this.icon, this.iconColor});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: iconColor ?? NothingTheme.sec(isDark)),
          const SizedBox(width: 12),
        ],
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1,
              color: NothingTheme.prim(isDark))),
          Text(sublabel, style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: NothingTheme.sec(isDark))),
        ]),
      ]),
      Switch(value: value, onChanged: onChanged,
          activeThumbColor: NothingTheme.prim(isDark),
          activeTrackColor: NothingTheme.accentOrange.withOpacity(0.4),
          inactiveThumbColor: NothingTheme.sec(isDark),
          inactiveTrackColor: NothingTheme.div(isDark)),
    ]),
  );
}

class _MenuRow extends StatelessWidget {
  final IconData icon; final String label; final bool isDark; final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.label,
      required this.isDark, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(icon, size: 16, color: NothingTheme.sec(isDark)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontFamily: 'monospace',
            fontSize: 11, fontWeight: FontWeight.w600,
            color: NothingTheme.prim(isDark)))),
        Icon(Icons.arrow_forward_ios, size: 10, color: NothingTheme.sec(isDark)),
      ])));
}
