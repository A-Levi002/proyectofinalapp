import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/nothing_theme.dart';
import '../models/usuario_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

enum _FotoAccion { camara, galeria, eliminar }

// Nombres de bucket a intentar en orden
const _bucketCandidates = ['user-avatars', 'avatars', 'images', 'public', 'storage'];

class PerfilScreen extends StatefulWidget {
  final StorageService? storageService;
  const PerfilScreen({this.storageService, super.key});
  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen>
    with SingleTickerProviderStateMixin {
  late SupabaseService _supabaseService;
  late StorageService  _storageService;
  final SupabaseClient _supabase = Supabase.instance.client;

  UsuarioModel? _usuario;
  bool _cargando     = true;
  bool _subiendoFoto = false;

  // Color dominante extraído de la foto de perfil
  Color _dominantColor = const Color(0xFF1A1A1A);
  bool  _colorExtraido = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _storageService  = widget.storageService ?? StorageService();
    _supabaseService = SupabaseService(_storageService);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _cargarPerfil();
    themeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _cargarPerfil() async {
    setState(() => _cargando = true);
    try {
      final u = await _supabaseService.obtenerPerfil();
      if (u != null) {
        await _storageService.guardarUsuario(u);
        setState(() => _usuario = u);
        await _extraerColorDominante(u.fotoPerfil);
      } else {
        final local = _storageService.obtenerUsuario();
        setState(() => _usuario = local);
        if (local?.fotoPerfil != null) await _extraerColorDominante(local!.fotoPerfil);
      }
    } catch (_) {
      setState(() => _usuario = _storageService.obtenerUsuario());
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
        _fadeCtrl.forward();
      }
    }
  }

  Future<void> _extraerColorDominante(String? url) async {
    if (url == null || url.isEmpty) {
      setState(() { _dominantColor = const Color(0xFF1A1A1A); _colorExtraido = false; });
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(100, 100),
      );
      final color = palette.vibrantColor?.color
          ?? palette.dominantColor?.color
          ?? const Color(0xFF1A1A1A);
      setState(() {
        _dominantColor = color;
        _colorExtraido = true;
      });
    } catch (_) {
      setState(() { _dominantColor = const Color(0xFF1A1A1A); _colorExtraido = false; });
    }
  }

  // ── Subir foto con detección automática de bucket ──
  Future<void> _subirFotoPerfil(File archivo) async {
    setState(() => _subiendoFoto = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final ci  = _usuario?.ci ?? user.id;
      final ext = archivo.path.split('.').last.toLowerCase();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final ruta = 'fotos_perfil/perfil_${ci}_$ts.$ext';

      // Intentar buckets conocidos automáticamente
      String? bucketUsado;
      String? urlFinal;
      dynamic lastError;

      for (final bucket in _bucketCandidates) {
        try {
          await _supabase.storage.from(bucket).upload(
            ruta, archivo,
            fileOptions: const FileOptions(upsert: true),
          );
          bucketUsado = bucket;
          urlFinal = _supabase.storage.from(bucket).getPublicUrl(ruta);
          break;
        } catch (e) {
          lastError = e;
          continue;
        }
      }

      if (bucketUsado == null || urlFinal == null) {
        throw Exception(
            'No se encontró un bucket disponible. '
            'Crea un bucket llamado "user-avatars" o "avatars" en Supabase Storage. '
            '(Último error: $lastError)');
      }

      await _supabase.from('usuarios')
          .update({'foto_perfil_url': urlFinal}).eq('ci', ci);

      final act = await _supabaseService.obtenerPerfil();
      if (act != null) {
        await _storageService.guardarUsuario(act);
        setState(() => _usuario = act);
        await _extraerColorDominante(act.fotoPerfil);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Foto actualizada'),
              backgroundColor: NothingTheme.accentGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('bucket')
                ? '⚠ Crea un bucket "user-avatars" en Supabase Storage y hazlo público'
                : 'Error: $e'),
            backgroundColor: NothingTheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _cambiarFotoPerfil() async {
    final dark = themeNotifier.isDark;
    final accion = await showModalBottomSheet<_FotoAccion>(
      context: context,
      backgroundColor: NothingTheme.surf(dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: NothingTheme.div(dark),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('FOTO DE PERFIL', style: TextStyle(
                fontFamily: 'monospace', fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 2,
                color: NothingTheme.sec(dark))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: NothingTheme.accentBlue),
              title: Text('Tomar foto', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12,
                  color: NothingTheme.prim(dark))),
              onTap: () => Navigator.pop(ctx, _FotoAccion.camara),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: NothingTheme.accentPurple),
              title: Text('Elegir de galería', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12,
                  color: NothingTheme.prim(dark))),
              onTap: () => Navigator.pop(ctx, _FotoAccion.galeria),
            ),
            if (_usuario?.fotoPerfil != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: NothingTheme.error),
                title: const Text('Eliminar foto',
                    style: TextStyle(fontFamily: 'monospace',
                        fontSize: 12, color: NothingTheme.error)),
                onTap: () => Navigator.pop(ctx, _FotoAccion.eliminar),
              ),
          ]),
        ),
      ),
    );

    if (accion == null || !mounted) return;

    if (accion == _FotoAccion.eliminar) {
      await _eliminarFoto(); return;
    }

    final source = accion == _FotoAccion.camara
        ? ImageSource.camera : ImageSource.gallery;
    final XFile? imagen = await ImagePicker().pickImage(
        source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (imagen == null) return;
    await _subirFotoPerfil(File(imagen.path));
  }

  Future<void> _eliminarFoto() async {
    setState(() => _subiendoFoto = true);
    try {
      final ci = _usuario?.ci ?? '';
      await _supabase.from('usuarios')
          .update({'foto_perfil_url': null}).eq('ci', ci);
      final act = await _supabaseService.obtenerPerfil();
      if (act != null) {
        await _storageService.guardarUsuario(act);
        setState(() {
          _usuario = act;
          _dominantColor = const Color(0xFF1A1A1A);
          _colorExtraido = false;
        });
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NothingTheme.surf(themeNotifier.isDark),
        title: Text('CERRAR SESIÓN', style: TextStyle(
            fontFamily: 'monospace', fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: 2,
            color: NothingTheme.prim(themeNotifier.isDark))),
        content: Text('¿Deseas salir de tu cuenta?', style: TextStyle(
            fontFamily: 'monospace', fontSize: 11,
            color: NothingTheme.sec(themeNotifier.isDark))),
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
      await _supabaseService.logout();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: error ? NothingTheme.error : NothingTheme.accentGreen));
  }

  // ────────────────────────────────────────────
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
          appBar: NothingAppBar(title: 'MI PERFIL'),
          body: const Center(child: CircularProgressIndicator()));
    }

    if (_usuario == null) {
      return Scaffold(backgroundColor: bg,
          appBar: NothingAppBar(title: 'MI PERFIL'),
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: NothingTheme.error),
            const SizedBox(height: 12),
            GestureDetector(onTap: _cargarPerfil,
                child: Text('REINTENTAR', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 11,
                    color: prim))),
          ])));
    }

    // Color del header: dominante de foto o negro/blanco según tema
    final headerBase = _colorExtraido
        ? _dominantColor
        : (dark ? const Color(0xFF111111) : const Color(0xFFF0F0F0));

    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [

            // ── SliverAppBar con color dinámico ──
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: bg,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: prim, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: prim, size: 20),
                  onPressed: () async {
                    final result = await Navigator.pushNamed(context, '/editar-perfil');
                    if (result == true) _cargarPerfil();
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeader(headerBase, dark, prim, sec, div),
              ),
              title: Text('MI PERFIL', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 3,
                  color: prim)),
            ),

            // ── Contenido ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _NothingCard(
                      title: 'INFORMACIÓN PERSONAL',
                      dark: dark, prim: prim, sec: sec, div: div, surf: surf,
                      children: [
                        _Row(label: 'CI',       value: _usuario!.ci,    prim: prim, sec: sec, div: div),
                        _Row(label: 'Email',    value: _usuario!.email, prim: prim, sec: sec, div: div),
                        _Row(label: 'Nacimiento',
                            value: FormateoHelper.formatearFecha(_usuario!.fechaNacimiento),
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Edad',
                            value: '${_usuario!.edad} años',
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Teléfono',
                            value: _usuario!.telefono.isNotEmpty
                                ? _usuario!.telefono : '—',
                            prim: prim, sec: sec, div: div, last: true),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _NothingCard(
                      title: 'ESTADO DE CUENTA',
                      dark: dark, prim: prim, sec: sec, div: div, surf: surf,
                      children: [
                        _Row(label: 'Saldo',
                            value: FormateoHelper.formatearMoneda(_usuario!.saldo),
                            valueColor: NothingTheme.accentGreen,
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Descuento',
                            value: '${(_usuario!.descuento * 100).toInt()}%',
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Email verificado',
                            value: _usuario!.emailVerificado ? '✓ Sí' : '○ No',
                            valueColor: _usuario!.emailVerificado
                                ? NothingTheme.accentGreen : null,
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Cuenta',
                            value: _usuario!.activo ? '✓ Activa' : '✗ Inactiva',
                            valueColor: _usuario!.activo
                                ? NothingTheme.accentGreen : NothingTheme.error,
                            prim: prim, sec: sec, div: div, last: true),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _NothingCard(
                      title: 'BENEFICIOS',
                      dark: dark, prim: prim, sec: sec, div: div, surf: surf,
                      children: [
                        _Row(label: 'Tarifa base',
                            value: FormateoHelper.formatearMoneda(2.50),
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Descuento',
                            value: '${(_usuario!.descuento * 100).toInt()}%',
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Tu tarifa / viaje',
                            value: FormateoHelper.formatearMoneda(
                                TarifasHelper.calcularTarifa(
                                    tipoUsuario: _usuario!.tipoUsuario)),
                            valueColor: NothingTheme.accentGreen,
                            prim: prim, sec: sec, div: div),
                        _Row(label: 'Ahorro / viaje',
                            value: FormateoHelper.formatearMoneda(
                                2.50 * _usuario!.descuento),
                            valueColor: NothingTheme.accentOrange,
                            prim: prim, sec: sec, div: div, last: true),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Acciones ──
                    _ActionBtn(
                      label: 'RECARGAR SALDO',
                      icon: Icons.credit_card_outlined,
                      color: NothingTheme.accentGreen,
                      dark: dark, div: div,
                      filled: true,
                      onTap: () => Navigator.pushNamed(context, '/recarga'),
                    ),
                    const SizedBox(height: 10),
                    _ActionBtn(
                      label: 'EDITAR PERFIL',
                      icon: Icons.edit_outlined,
                      color: NothingTheme.accentBlue,
                      dark: dark, div: div,
                      onTap: () async {
                        final result =
                            await Navigator.pushNamed(context, '/editar-perfil');
                        if (result == true) _cargarPerfil();
                      },
                    ),
                    const SizedBox(height: 10),
                    _ActionBtn(
                      label: 'CERRAR SESIÓN',
                      icon: Icons.logout,
                      color: NothingTheme.error,
                      dark: dark, div: div,
                      onTap: _cerrarSesion,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header dinámico ──
  Widget _buildHeader(Color headerBase, bool dark, Color prim, Color sec, Color div) {
    final bg = NothingTheme.bg(dark);
    final isDominant = _colorExtraido;

    // Luminosidad del color para decidir si el texto encima es negro o blanco
    final lum = headerBase.computeLuminance();
    final onHeader = lum > 0.4 ? Colors.black87 : Colors.white;

    return Stack(fit: StackFit.expand, children: [
      // Fondo con color dinámico
      AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              headerBase.withOpacity(isDominant ? 0.85 : 0.5),
              headerBase.withOpacity(isDominant ? 0.3 : 0.1),
              bg,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
      ),

      // Blur sutil
      if (isDominant)
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: const SizedBox.expand(),
        ),

      // Patrón de líneas Nothing (decorativo)
      Positioned.fill(child: CustomPaint(painter: _LinePainter(
          color: onHeader.withOpacity(0.04)))),

      // Contenido del header
      Positioned(
        left: 0, right: 0, bottom: 24,
        child: Column(children: [
          // Avatar
          GestureDetector(
            onTap: _subiendoFoto ? null : _cambiarFotoPerfil,
            child: Stack(alignment: Alignment.center, children: [
              // Anillo exterior decorativo
              Container(
                width: 106, height: 106,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: onHeader.withOpacity(0.2), width: 1),
                ),
              ),
              // Avatar
              Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark ? Colors.black : Colors.white,
                  border: Border.all(
                      color: onHeader.withOpacity(0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3),
                        blurRadius: 16, spreadRadius: 2),
                  ],
                ),
                child: ClipOval(child: _subiendoFoto
                    ? Center(child: CircularProgressIndicator(
                        color: NothingTheme.accentPurple, strokeWidth: 2))
                    : _usuario!.fotoPerfil != null
                        ? Image.network(_usuario!.fotoPerfil!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultAvatar(dark))
                        : _defaultAvatar(dark)),
              ),
              // Botón cámara
              Positioned(bottom: 0, right: 0,
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: isDominant
                        ? headerBase
                        : NothingTheme.accentPurple,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: NothingTheme.bg(dark), width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 14, color: Colors.white),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // Nombre
          Text('${_usuario!.nombre} ${_usuario!.apellido}',
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: onHeader,
                  shadows: [Shadow(color: Colors.black26, blurRadius: 8)])),

          const SizedBox(height: 8),

          // Badge tipo usuario
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: isDominant
                  ? headerBase.withOpacity(0.25)
                  : (dark ? Colors.white10 : Colors.black.withOpacity(0.08)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: onHeader.withOpacity(0.3), width: 0.5),
            ),
            child: Text(_usuario!.tipoUsuario.toUpperCase(),
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 3,
                    color: onHeader)),
          ),
        ]),
      ),
    ]);
  }

  Widget _defaultAvatar(bool dark) => Container(
    color: NothingTheme.surf(dark),
    child: Icon(Icons.person, size: 48,
        color: NothingTheme.prim(dark).withOpacity(0.4)),
  );
}

// ─────────────────────────────────────────────
// Pintor de líneas Nothing
// ─────────────────────────────────────────────
class _LinePainter extends CustomPainter {
  final Color color;
  const _LinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 0.5;
    const spacing = 20.0;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_LinePainter o) => o.color != color;
}

// ─────────────────────────────────────────────
// Widgets reutilizables
// ─────────────────────────────────────────────

class _NothingCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool dark;
  final Color prim, sec, div, surf;

  const _NothingCard({
    required this.title, required this.children,
    required this.dark, required this.prim,
    required this.sec, required this.div, required this.surf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: div, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Título de la card
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: div, width: 0.5)),
          ),
          child: Text(title, style: TextStyle(
              fontFamily: 'monospace', fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        ),
        ...children,
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final Color prim, sec, div;
  final bool last;

  const _Row({
    required this.label, required this.value,
    this.valueColor, required this.prim,
    required this.sec, required this.div,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: last ? null : BoxDecoration(
        border: Border(bottom: BorderSide(color: div, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 11, color: sec)),
          Flexible(child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? prim))),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool dark, filled;
  final Color div;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label, required this.icon, required this.color,
    required this.dark, required this.div,
    this.filled = false, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: filled ? Colors.transparent : color.withOpacity(0.4),
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
