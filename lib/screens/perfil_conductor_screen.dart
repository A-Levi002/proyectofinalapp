import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

const _bucketCandidates = ['conductores-docs', 'user-avatars', 'avatars', 'images', 'public'];

enum _FotoAccion { camara, galeria, eliminar }

class PerfilConductorScreen extends StatefulWidget {
  const PerfilConductorScreen({super.key});
  @override
  State<PerfilConductorScreen> createState() => _PerfilConductorScreenState();
}

class _PerfilConductorScreenState extends State<PerfilConductorScreen>
    with SingleTickerProviderStateMixin {
  late SupabaseService _svc;
  late StorageService  _store;
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _conductor;
  Map<String, dynamic>? _contrato;
  bool _cargando     = true;
  bool _subiendoFoto = false;

  Color _dominantColor = const Color(0xFF1A1A1A);
  bool  _colorExtraido = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _store = StorageService();
    _svc   = SupabaseService(_store);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    themeNotifier.addListener(_rebuild);
    _cargarDatos();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final cRes = await _svc.obtenerConductor();
      final tRes = await _svc.obtenerContratoConductor();
      if (cRes['exito'] == true) {
        _conductor = cRes['conductor'];
        await _extraerColor(_conductor?['foto_carnet']);
      }
      if (tRes['exito'] == true) _contrato = tRes['contrato'];
    } catch (_) {} finally {
      if (mounted) {
        setState(() => _cargando = false);
        _fadeCtrl.forward();
      }
    }
  }

  Future<void> _extraerColor(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final pal = await PaletteGenerator.fromImageProvider(
          NetworkImage(url), size: const Size(100, 100));
      final c = pal.vibrantColor?.color ?? pal.dominantColor?.color;
      if (c != null) setState(() { _dominantColor = c; _colorExtraido = true; });
    } catch (_) {}
  }

  Future<void> _cambiarFoto() async {
    final dark = themeNotifier.isDark;
    final accion = await showModalBottomSheet<_FotoAccion>(
      context: context,
      backgroundColor: NothingTheme.surf(dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: NothingTheme.div(dark),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('FOTO DE PERFIL', style: TextStyle(fontFamily: 'monospace',
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2,
              color: NothingTheme.sec(dark))),
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.camera_alt, color: NothingTheme.accentOrange),
              title: Text('Tomar foto', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 12, color: NothingTheme.prim(dark))),
              onTap: () => Navigator.pop(ctx, _FotoAccion.camara)),
          ListTile(leading: const Icon(Icons.photo_library, color: NothingTheme.accentPurple),
              title: Text('Elegir de galería', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 12, color: NothingTheme.prim(dark))),
              onTap: () => Navigator.pop(ctx, _FotoAccion.galeria)),
          if (_conductor?['foto_carnet'] != null)
            ListTile(leading: const Icon(Icons.delete_outline, color: NothingTheme.error),
                title: const Text('Eliminar foto',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                        color: NothingTheme.error)),
                onTap: () => Navigator.pop(ctx, _FotoAccion.eliminar)),
        ]),
      )),
    );
    if (accion == null || !mounted) return;
    if (accion == _FotoAccion.eliminar) { await _eliminarFoto(); return; }
    final src = accion == _FotoAccion.camara ? ImageSource.camera : ImageSource.gallery;
    final img = await ImagePicker().pickImage(source: src, maxWidth: 800,
        maxHeight: 800, imageQuality: 85);
    if (img == null) return;
    await _subirFoto(File(img.path));
  }

  Future<void> _subirFoto(File archivo) async {
    setState(() => _subiendoFoto = true);
    try {
      final ci  = _conductor?['ci'] ?? '';
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final ext = archivo.path.split('.').last.toLowerCase();
      final ruta = 'fotos_perfil/conductor_${ci}_$ts.$ext';

      String? url;
      for (final bucket in _bucketCandidates) {
        try {
          await _supabase.storage.from(bucket).upload(ruta, archivo,
              fileOptions: const FileOptions(upsert: true));
          url = _supabase.storage.from(bucket).getPublicUrl(ruta);
          break;
        } catch (_) { continue; }
      }
      if (url == null) throw Exception('Sin bucket disponible');

      await _supabase.from('conductores')
          .update({'foto_carnet': url}).eq('ci', ci);
      await _cargarDatos();
      _snack('✓ Foto actualizada');
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _eliminarFoto() async {
    setState(() => _subiendoFoto = true);
    try {
      await _supabase.from('conductores')
          .update({'foto_carnet': null}).eq('ci', _conductor?['ci'] ?? '');
      await _cargarDatos();
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final dark = themeNotifier.isDark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NothingTheme.surf(dark),
        title: Text('CERRAR SESIÓN', style: TextStyle(fontFamily: 'monospace',
            fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2,
            color: NothingTheme.prim(dark))),
        content: Text('¿Deseas salir de tu cuenta de conductor?',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                color: NothingTheme.sec(dark))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('SALIR',
                  style: TextStyle(color: NothingTheme.error))),
        ],
      ),
    );
    if (ok == true) {
      await _store.guardar('tipo_usuario', '');
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: error ? NothingTheme.error : NothingTheme.accentGreen));
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
      return Scaffold(backgroundColor: bg,
          appBar: const NothingAppBar(title: 'MI PERFIL'),
          body: const Center(child: CircularProgressIndicator(
              color: NothingTheme.accentOrange)));
    }

    if (_conductor == null) {
      return Scaffold(backgroundColor: bg,
          appBar: const NothingAppBar(title: 'MI PERFIL'),
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: NothingTheme.error),
            const SizedBox(height: 12),
            GestureDetector(onTap: _cargarDatos,
                child: Text('REINTENTAR', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 11, color: prim))),
          ])));
    }

    final headerBase = _colorExtraido ? _dominantColor
        : (dark ? const Color(0xFF1A0A00) : const Color(0xFFFFF3E0));
    final lum = headerBase.computeLuminance();
    final onH = lum > 0.4 ? Colors.black87 : Colors.white;

    final nombre   = '${_conductor!['nombre'] ?? ''} ${_conductor!['apellido'] ?? ''}';
    final empresa  = _conductor!['empresa'] ?? '—';
    final estado   = _conductor!['estado'] ?? 'inactivo';
    final fotoUrl  = _conductor!['foto_carnet'] as String?;

    // Fechas
    String fNac = '—', fLic = '—', fReg = '—';
    try {
      final n = _conductor!['fecha_nacimiento'];
      if (n != null) fNac = DateFormat('dd/MM/yyyy').format(DateTime.parse(n));
      final l = _conductor!['vigencia_licencia'];
      if (l != null) fLic = DateFormat('dd/MM/yyyy').format(DateTime.parse(l));
      final r = _conductor!['created_at'];
      if (r != null) fReg = DateFormat('dd/MM/yyyy').format(DateTime.parse(r));
    } catch (_) {}

    // Vigencia licencia
    bool licVigente = true;
    try {
      final l = _conductor!['vigencia_licencia'];
      if (l != null) licVigente = DateTime.parse(l).isAfter(DateTime.now());
    } catch (_) {}

    // Color estado
    Color estadoColor;
    String estadoLabel;
    switch (estado) {
      case 'activo':     estadoColor = NothingTheme.accentGreen;  estadoLabel = 'ACTIVO'; break;
      case 'suspendido': estadoColor = NothingTheme.error;        estadoLabel = 'SUSPENDIDO'; break;
      default:           estadoColor = NothingTheme.accentOrange; estadoLabel = 'INACTIVO';
    }

    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(slivers: [

          // ── SliverAppBar ──
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: bg,
            leading: IconButton(
                icon: Icon(Icons.arrow_back, color: prim, size: 20),
                onPressed: () => Navigator.pop(context)),
            title: Text('MI PERFIL', style: TextStyle(fontFamily: 'monospace',
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 3, color: prim)),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(headerBase, onH, dark, nombre,
                  empresa, estadoLabel, estadoColor, fotoUrl),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Información personal ──
                _Card(title: 'INFORMACIÓN PERSONAL', dark: dark,
                    prim: prim, sec: sec, div: div, surf: surf, children: [
                  _Row(label: 'CI',       value: _conductor!['ci'] ?? '—',     prim: prim, sec: sec, div: div),
                  _Row(label: 'Email',    value: _conductor!['email'] ?? '—',  prim: prim, sec: sec, div: div),
                  _Row(label: 'Teléfono', value: _conductor!['telefono'] ?? '—', prim: prim, sec: sec, div: div),
                  _Row(label: 'Nacimiento', value: fNac,                        prim: prim, sec: sec, div: div),
                  _Row(label: 'Dirección',  value: _conductor!['direccion'] ?? '—',
                      prim: prim, sec: sec, div: div, last: true),
                ]),
                const SizedBox(height: 14),

                // ── Datos laborales ──
                _Card(title: 'DATOS LABORALES', dark: dark,
                    prim: prim, sec: sec, div: div, surf: surf, children: [
                  _Row(label: 'Empresa',   value: empresa, prim: prim, sec: sec, div: div),
                  _Row(label: 'Bus / Trufi',
                      value: _conductor!['numero_bus'] ?? '—',
                      prim: prim, sec: sec, div: div),
                  _Row(label: 'Zona ID',
                      value: '${_conductor!['zona_id'] ?? '—'}',
                      prim: prim, sec: sec, div: div),
                  _Row(label: 'Registro',  value: fReg,   prim: prim, sec: sec, div: div, last: true),
                ]),
                const SizedBox(height: 14),

                // ── Licencia ──
                _Card(title: 'LICENCIA DE CONDUCIR', dark: dark,
                    prim: prim, sec: sec, div: div, surf: surf, children: [
                  _Row(label: 'Número',    value: _conductor!['numero_licencia'] ?? '—', prim: prim, sec: sec, div: div),
                  _Row(label: 'Categoría', value: _conductor!['categoria_licencia'] ?? 'P', prim: prim, sec: sec, div: div),
                  _Row(label: 'Vigencia',  value: fLic,
                      valueColor: licVigente ? NothingTheme.accentGreen : NothingTheme.error,
                      prim: prim, sec: sec, div: div),
                  _Row(label: 'Estado',
                      value: licVigente ? '✓ Vigente' : '✗ Vencida',
                      valueColor: licVigente ? NothingTheme.accentGreen : NothingTheme.error,
                      prim: prim, sec: sec, div: div, last: true),
                ]),
                const SizedBox(height: 14),

                // ── Contrato ──
                if (_contrato != null) ...[
                  _Card(title: 'CONTRATO', dark: dark,
                      prim: prim, sec: sec, div: div, surf: surf, children: [
                    _Row(label: 'Estado',
                        value: (_contrato!['estado'] ?? 'pendiente').toUpperCase(),
                        valueColor: _contrato!['estado'] == 'aceptado'
                            ? NothingTheme.accentGreen
                            : _contrato!['estado'] == 'rechazado'
                                ? NothingTheme.error
                                : NothingTheme.accentOrange,
                        prim: prim, sec: sec, div: div),
                    _Row(label: 'Comisión',
                        value: '${_contrato!['comision_porcentaje'] ?? 10}%',
                        prim: prim, sec: sec, div: div),
                    _Row(label: 'Inicio',
                        value: _contrato!['fecha_inicio'] ?? '—',
                        prim: prim, sec: sec, div: div, last: true),
                  ]),
                  const SizedBox(height: 14),
                ],

                // ── Saldo comisiones ──
                _Card(title: 'COMISIONES', dark: dark,
                    prim: prim, sec: sec, div: div, surf: surf, children: [
                  _Row(label: 'Saldo acumulado',
                      value: 'Bs ${double.tryParse(_conductor!['saldo_comisiones']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}',
                      valueColor: NothingTheme.accentGreen,
                      prim: prim, sec: sec, div: div, last: true),
                ]),
                const SizedBox(height: 24),

                // ── Acciones ──
                _Btn(label: 'CERRAR SESIÓN', icon: Icons.logout,
                    color: NothingTheme.error, dark: dark, onTap: _cerrarSesion),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(Color headerBase, Color onH, bool dark, String nombre,
      String empresa, String estadoLabel, Color estadoColor, String? fotoUrl) {
    final isDom = _colorExtraido;
    return Stack(fit: StackFit.expand, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              headerBase.withOpacity(isDom ? 0.85 : 0.5),
              headerBase.withOpacity(isDom ? 0.3 : 0.1),
              NothingTheme.bg(dark),
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
      ),
      Positioned.fill(child: CustomPaint(
          painter: _LinePainter(color: onH.withOpacity(0.04)))),
      Positioned(left: 0, right: 0, bottom: 24,
        child: Column(children: [
          // Avatar con botón cámara
          GestureDetector(
            onTap: _subiendoFoto ? null : _cambiarFoto,
            child: Stack(alignment: Alignment.center, children: [
              Container(width: 106, height: 106,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: onH.withOpacity(0.2), width: 1))),
              Container(width: 96, height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: dark ? Colors.black : Colors.white,
                    border: Border.all(color: onH.withOpacity(0.5), width: 1.5)),
                child: ClipOval(child: _subiendoFoto
                    ? const Center(child: CircularProgressIndicator(
                        color: NothingTheme.accentOrange, strokeWidth: 2))
                    : fotoUrl != null
                        ? Image.network(fotoUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatar(dark))
                        : _avatar(dark)),
              ),
              Positioned(bottom: 0, right: 0,
                child: Container(width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: isDom ? headerBase : NothingTheme.accentOrange,
                    shape: BoxShape.circle,
                    border: Border.all(color: NothingTheme.bg(dark), width: 2)),
                  child: const Icon(Icons.camera_alt, size: 14, color: Colors.white))),
            ]),
          ),
          const SizedBox(height: 12),
          Text(nombre, style: TextStyle(fontFamily: 'monospace', fontSize: 20,
              fontWeight: FontWeight.w900, color: onH,
              shadows: const [Shadow(color: Colors.black26, blurRadius: 8)])),
          const SizedBox(height: 4),
          Text(empresa, style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              color: onH.withOpacity(0.7))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: estadoColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: estadoColor.withOpacity(0.6), width: 0.5)),
            child: Text(estadoLabel, style: TextStyle(fontFamily: 'monospace',
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 3,
                color: estadoColor)),
          ),
        ]),
      ),
    ]);
  }

  Widget _avatar(bool dark) => Container(
    color: NothingTheme.surf(dark),
    child: Icon(Icons.directions_bus, size: 48,
        color: NothingTheme.accentOrange.withOpacity(0.6)));
}

// ─────────────────────────────────────────────
//  Painter de líneas
// ─────────────────────────────────────────────
class _LinePainter extends CustomPainter {
  final Color color;
  const _LinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 0.5;
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_LinePainter o) => o.color != color;
}

// ─────────────────────────────────────────────
//  Widgets reutilizables
// ─────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool dark;
  final Color prim, sec, div, surf;
  const _Card({required this.title, required this.children, required this.dark,
      required this.prim, required this.sec, required this.div, required this.surf});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: surf, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: div, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: div, width: 0.5))),
        child: Text(title, style: TextStyle(fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
      ),
      ...children,
    ]),
  );
}

class _Row extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final Color prim, sec, div;
  final bool last;
  const _Row({required this.label, required this.value, this.valueColor,
      required this.prim, required this.sec, required this.div, this.last = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: last ? null : BoxDecoration(
        border: Border(bottom: BorderSide(color: div, width: 0.5))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec)),
      Flexible(child: Text(value, textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12,
              fontWeight: FontWeight.w600, color: valueColor ?? prim))),
    ]),
  );
}

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool dark;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.icon, required this.color,
      required this.dark, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 2, color: color)),
      ]),
    ),
  );
}
