import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/nothing_theme.dart';
import '../models/usuario_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class HomeScreen extends StatefulWidget {
  final StorageService? storageService;
  const HomeScreen({this.storageService, super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late SupabaseService _svc;
  late StorageService  _store;
  UsuarioModel? _usuario;
  bool _cargando   = true;
  bool _mapaListo  = false;
  bool _mapaError  = false;

  GoogleMapController? _mapCtrl;
  static const LatLng _centro = LatLng(-17.3935, -66.1568);

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _store = widget.storageService ?? StorageService();
    _svc   = SupabaseService(_store);
    _cargarPerfil();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    themeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _mapCtrl?.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _cargarPerfil() async {
    setState(() => _cargando = true);
    try {
      final u = await _svc.obtenerPerfil();
      if (u != null) {
        await _store.guardarUsuario(u);
        setState(() => _usuario = u);
      } else {
        setState(() => _usuario = _store.obtenerUsuario());
      }
    } catch (_) {
      setState(() => _usuario = _store.obtenerUsuario());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CERRAR SESIÓN',
            style: TextStyle(fontFamily: 'monospace', fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 2)),
        content: const Text('¿Deseas salir?',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SALIR',
                  style: TextStyle(color: NothingTheme.error))),
        ],
      ),
    );
    if (ok == true) {
      await _svc.logout();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'BUENOS DÍAS';
    if (h < 18) return 'BUENAS TARDES';
    return 'BUENAS NOCHES';
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    if (_cargando) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _GlyphLoader(isDark: dark),
          const SizedBox(height: 20),
          Text('CARGANDO...', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: Stack(children: [

        // ── Mapa o fondo de respaldo ──
        _mapaError
            ? _MapaFallback(dark: dark, bg: bg)
            : GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: _centro, zoom: 14.5),
                onMapCreated: (c) {
                  _mapCtrl = c;
                  // Esperar al siguiente frame para aplicar estilo
                  Future.microtask(() async {
                    try {
                      await c.setMapStyle(
                          themeNotifier.isDark ? _darkMapStyle : _lightMapStyle);
                    } catch (_) {}
                    if (mounted) setState(() => _mapaListo = true);
                  });
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                markers: {
                  Marker(
                    markerId: const MarkerId('centro'),
                    position: _centro,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        dark
                            ? BitmapDescriptor.hueAzure
                            : BitmapDescriptor.hueRed),
                  ),
                },
              ),

        // ── Header ──
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            // Avatar → perfil
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/perfil'),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: dark ? NothingTheme.cardColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: div, width: 0.5),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                ),
                child: Center(child: Text(
                  (_usuario?.nombre.isNotEmpty == true)
                      ? _usuario!.nombre[0].toUpperCase()
                      : 'U',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 16,
                      fontWeight: FontWeight.w900, color: prim),
                )),
              ),
            ),
            const SizedBox(width: 10),
            // Barra búsqueda → trufis
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/trufis'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: dark
                      ? NothingTheme.cardColor.withOpacity(0.95)
                      : Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: div, width: 0.5),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.15), blurRadius: 8)],
                ),
                child: Row(children: [
                  Icon(Icons.directions_bus_outlined, size: 16, color: NothingTheme.accentGreen),
                  const SizedBox(width: 8),
                  Text('Ver trufis en tiempo real',
                      style: TextStyle(fontFamily: 'monospace',
                          fontSize: 11, color: sec)),
                ]),
              ),
            )),
            const SizedBox(width: 10),
            // Ajustes
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/ajustes'),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: dark ? NothingTheme.cardColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: div, width: 0.5),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.15), blurRadius: 8)],
                ),
                child: Icon(Icons.tune, size: 18, color: prim),
              ),
            ),
          ]),
        )),

        // ── Botón centrar ──
        if (!_mapaError)
          Positioned(
            right: 16, bottom: 290,
            child: GestureDetector(
              onTap: () => _mapCtrl?.animateCamera(
                  CameraUpdate.newCameraPosition(
                      const CameraPosition(target: _centro, zoom: 15))),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: dark ? NothingTheme.cardColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: div, width: 0.5),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                ),
                child: Icon(Icons.my_location, size: 20, color: prim),
              ),
            ),
          ),

        // ── Panel inferior ──
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: dark
                  ? NothingTheme.cardColor.withOpacity(0.97)
                  : Colors.white.withOpacity(0.97),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: div, width: 0.5)),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, -4))],
            ),
            child: SafeArea(top: false, child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [

                // Handle
                Center(child: Container(
                    width: 36, height: 3,
                    decoration: BoxDecoration(
                        color: div,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),

                // Saludo + saldo
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_saludo(), style: TextStyle(
                        fontFamily: 'monospace', fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5, color: sec)),
                    Text(_usuario?.nombre ?? 'Usuario', style: TextStyle(
                        fontFamily: 'monospace', fontSize: 20,
                        fontWeight: FontWeight.w900, color: prim)),
                    const SizedBox(height: 4),
                    NothingBadge(
                        label: (_usuario?.tipoUsuario ?? 'general')
                            .toUpperCase(),
                        color: NothingTheme.accentGreen),
                  ]),
                  // Saldo
                  AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Transform.scale(
                        scale: (_usuario != null && _usuario!.saldo < 5)
                            ? _pulse.value : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: surf,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: (_usuario != null && _usuario!.saldo < 5)
                                  ? NothingTheme.error.withOpacity(0.6)
                                  : NothingTheme.accentGreen.withOpacity(0.4),
                              width: 0.5),
                          ),
                          child: Column(children: [
                            Text('SALDO', style: TextStyle(
                                fontFamily: 'monospace', fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2, color: sec)),
                            Text(
                                FormateoHelper.formatearMoneda(
                                    _usuario?.saldo ?? 0),
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: NothingTheme.accentGreen)),
                          ]),
                        ),
                      )),
                ]),

                const SizedBox(height: 16),
                _GlyphDivider(isDark: dark),
                const SizedBox(height: 16),

                // Acciones rápidas
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  _QuickBtn(icon: Icons.qr_code_2_outlined,  label: 'QR',
                      isDark: dark,
                      onTap: () => Navigator.pushNamed(context, '/generar-qr')),
                  _QuickBtn(icon: Icons.credit_card_outlined, label: 'RECARGAR',
                      isDark: dark,
                      onTap: () => Navigator.pushNamed(context, '/recarga')),
                  _QuickBtn(icon: Icons.directions_bus_outlined, label: 'TRUFIS',
                      isDark: dark,
                      onTap: () => Navigator.pushNamed(context, '/trufis')),
                  _QuickBtn(icon: Icons.history_outlined,     label: 'VIAJES',
                      isDark: dark,
                      onTap: () => Navigator.pushNamed(context, '/viajes')),
                  _QuickBtn(icon: Icons.settings_outlined,    label: 'AJUSTES',
                      isDark: dark,
                      onTap: () => Navigator.pushNamed(context, '/ajustes')),
                ]),

                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  GestureDetector(
                      onTap: _cerrarSesion,
                      child: Row(children: [
                        Icon(Icons.logout, size: 12, color: sec),
                        const SizedBox(width: 4),
                        Text('SALIR', style: TextStyle(
                            fontFamily: 'monospace', fontSize: 9,
                            letterSpacing: 2, color: sec)),
                      ])),
                ]),
              ]),
            )),
          ),
        ),
      ]),
    );
  }
}

// ── Fallback cuando el mapa no carga (API key issue) ──
class _MapaFallback extends StatelessWidget {
  final bool dark;
  final Color bg;
  const _MapaFallback({required this.dark, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 48,
              color: NothingTheme.sec(dark).withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('MAPA NO DISPONIBLE', style: TextStyle(
              fontFamily: 'monospace', fontSize: 10,
              letterSpacing: 2, color: NothingTheme.sec(dark))),
        ],
      )),
    );
  }
}

// ── Widgets privados ──

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _QuickBtn(
      {required this.icon, required this.label,
       required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: NothingTheme.surf(isDark),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: NothingTheme.div(isDark), width: 0.5),
            ),
            child: Icon(icon, size: 22, color: NothingTheme.prim(isDark))),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 8,
              fontWeight: FontWeight.w700, letterSpacing: 1.5,
              color: NothingTheme.sec(isDark))),
        ]));
  }
}

class _GlyphDivider extends StatelessWidget {
  final bool isDark;
  const _GlyphDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = isDark ? Colors.white : Colors.black;
    return Row(children: [
      Expanded(child: Container(height: 0.5, color: c.withOpacity(0.12))),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
              children: List.generate(
                  3,
                  (i) => Container(
                        width: 4, height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.withOpacity(0.15 + i * 0.1)),
                      )))),
      Expanded(child: Container(height: 0.5, color: c.withOpacity(0.12))),
    ]);
  }
}

class _GlyphLoader extends StatefulWidget {
  final bool isDark;
  const _GlyphLoader({required this.isDark});
  @override
  State<_GlyphLoader> createState() => _GlyphLoaderState();
}

class _GlyphLoaderState extends State<_GlyphLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 48, height: 48,
      child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
              painter: _GlyphLoaderPainter(
                  progress: _c.value, isDark: widget.isDark))));
}

class _GlyphLoaderPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  const _GlyphLoaderPainter({required this.progress, required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    final c = isDark ? Colors.white : Colors.black;
    final p1 = Paint()
      ..color = c.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final p2 = Paint()
      ..color = c.withOpacity(0.1)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(r, 0, 6.28, false, p2);
    canvas.drawArc(r, -1.57, progress * 6.28, false, p1);
  }
  @override
  bool shouldRepaint(_GlyphLoaderPainter o) => o.progress != progress;
}

// ── Estilos de mapa (JSON compacto en una sola línea para evitar errores de parsing) ──
const String _darkMapStyle =
    '[{"elementType":"geometry","stylers":[{"color":"#0a0a0a"}]},'
    '{"elementType":"labels.text.stroke","stylers":[{"color":"#000000"}]},'
    '{"elementType":"labels.text.fill","stylers":[{"color":"#444444"}]},'
    '{"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},'
    '{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#222222"}]},'
    '{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#222222"}]},'
    '{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d0d0d"}]},'
    '{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},'
    '{"featureType":"transit","stylers":[{"visibility":"off"}]}]';

const String _lightMapStyle =
    '[{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},'
    '{"featureType":"transit","stylers":[{"visibility":"off"}]},'
    '{"featureType":"road","elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},'
    '{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e0e0e0"}]},'
    '{"elementType":"geometry","stylers":[{"color":"#f8f8f8"}]},'
    '{"featureType":"water","elementType":"geometry","stylers":[{"color":"#d0d0d0"}]}]';
