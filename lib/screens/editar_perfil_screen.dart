import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/nothing_theme.dart';
import '../models/usuario_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

// Acción elegida en el BottomSheet de foto — evita confundir null (cerrar) con eliminar
enum _FotoAccion { camara, galeria, eliminar }

class EditarPerfilScreen extends StatefulWidget {
  final StorageService? storageService;
  const EditarPerfilScreen({this.storageService, super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  late SupabaseService _supabaseService;
  late StorageService _storageService;
  final SupabaseClient _supabase = Supabase.instance.client;

  UsuarioModel? _usuario;
  bool _cargando  = true;
  bool _guardando = false;
  bool _subiendoFoto = false;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _telefonoCtrl;

  @override
  void initState() {
    super.initState();
    _telefonoCtrl = TextEditingController();
    _storageService = widget.storageService ?? StorageService();
    _supabaseService = SupabaseService(_storageService);
    _cargarPerfil();
    themeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _telefonoCtrl.dispose();
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
        setState(() { _usuario = u; _telefonoCtrl.text = u.telefono; });
      } else {
        final local = _storageService.obtenerUsuario();
        if (local != null) {
          setState(() { _usuario = local; _telefonoCtrl.text = local.telefono; });
        }
      }
    } catch (e) {
      _mostrarError('Error al cargar perfil: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarCambios() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _guardando = true);
    try {
      final ci = _usuario?.ci ?? '';
      await _supabase
          .from('usuarios')
          .update({'telefono': _telefonoCtrl.text.trim()})
          .eq('ci', ci);

      final actualizado = await _supabaseService.obtenerPerfil();
      if (actualizado != null) {
        await _storageService.guardarUsuario(actualizado);
        setState(() => _usuario = actualizado);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Perfil actualizado'),
            backgroundColor: NothingTheme.accentGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarError('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── Foto: usa enum para distinguir acciones ──
  Future<void> _cambiarFotoPerfil() async {
    final dark = themeNotifier.isDark;
    final accion = await showModalBottomSheet<_FotoAccion>(
      context: context,
      backgroundColor: NothingTheme.surf(dark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: NothingTheme.div(dark),
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('FOTO DE PERFIL', style: TextStyle(
                fontFamily: 'monospace', fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 2,
                color: NothingTheme.sec(dark))),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.camera_alt,
                    color: NothingTheme.accentBlue),
                title: Text('Tomar foto', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12,
                  color: NothingTheme.prim(dark))),
                onTap: () => Navigator.pop(ctx, _FotoAccion.camara),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: NothingTheme.accentPurple),
                title: Text('Elegir de galería', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12,
                  color: NothingTheme.prim(dark))),
                onTap: () => Navigator.pop(ctx, _FotoAccion.galeria),
              ),
              if (_usuario?.fotoPerfil != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: NothingTheme.error),
                  title: const Text('Eliminar foto', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12,
                    color: NothingTheme.error)),
                  onTap: () => Navigator.pop(ctx, _FotoAccion.eliminar),
                ),
            ],
          ),
        ),
      ),
    );

    // null = usuario cerró el sheet tocando fuera → no hacer nada
    if (accion == null || !mounted) return;

    switch (accion) {
      case _FotoAccion.eliminar:
        await _eliminarFoto();
        break;
      case _FotoAccion.camara:
      case _FotoAccion.galeria:
        final source = accion == _FotoAccion.camara
            ? ImageSource.camera
            : ImageSource.gallery;
        final picker = ImagePicker();
        final XFile? imagen = await picker.pickImage(
          source: source,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
        );
        if (imagen == null) return;
        await _subirFoto(File(imagen.path));
        break;
    }
  }

  Future<void> _subirFoto(File archivo) async {
    setState(() => _subiendoFoto = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      final ci  = _usuario?.ci ?? user.id;
      final ext = archivo.path.split('.').last.toLowerCase();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final ruta = 'fotos_perfil/perfil_${ci}_$ts.$ext';

      // Auto-detectar bucket disponible
      const buckets = ['user-avatars', 'avatars', 'images', 'public'];
      String? urlFinal;
      dynamic lastErr;
      for (final b in buckets) {
        try {
          await _supabase.storage.from(b).upload(
              ruta, archivo, fileOptions: const FileOptions(upsert: true));
          urlFinal = _supabase.storage.from(b).getPublicUrl(ruta);
          break;
        } catch (e) { lastErr = e; }
      }
      if (urlFinal == null) throw Exception('Bucket no encontrado. Crea "user-avatars" público en Supabase Storage. ($lastErr)');
      final url = urlFinal;

      await _supabase.from('usuarios')
          .update({'foto_perfil_url': url}).eq('ci', ci);

      final act = await _supabaseService.obtenerPerfil();
      if (act != null) {
        await _storageService.guardarUsuario(act);
        if (mounted) setState(() => _usuario = act);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Foto actualizada'),
            backgroundColor: NothingTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      _mostrarError('Error subiendo foto: $e');
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
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
        if (mounted) setState(() => _usuario = act);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto eliminada')),
        );
      }
    } catch (e) {
      _mostrarError('Error eliminando foto: $e');
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: NothingTheme.error),
    );
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
        appBar: NothingAppBar(title: 'EDITAR PERFIL'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: NothingAppBar(title: 'EDITAR PERFIL'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Avatar centrado ──
              Center(
                child: Stack(children: [
                  GestureDetector(
                    onTap: _subiendoFoto ? null : _cambiarFotoPerfil,
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: div, width: 1)),
                      child: ClipOval(child: _subiendoFoto
                          ? Center(child: CircularProgressIndicator(
                              color: NothingTheme.accentPurple))
                          : _usuario?.fotoPerfil != null
                              ? Image.network(
                                  _usuario!.fotoPerfil!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, progress) =>
                                      progress == null
                                          ? child
                                          : Center(child:
                                              CircularProgressIndicator(
                                                color: NothingTheme.accentPurple)),
                                  errorBuilder: (_, __, ___) =>
                                      _avatarDefault(dark, prim, surf),
                                )
                              : _avatarDefault(dark, prim, surf)),
                    ),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: GestureDetector(
                      onTap: _subiendoFoto ? null : _cambiarFotoPerfil,
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: NothingTheme.accentPurple,
                          shape: BoxShape.circle,
                          border: Border.all(color: bg, width: 2)),
                        child: const Icon(Icons.camera_alt,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Center(child: Text('Toca la foto para cambiarla',
                style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                    letterSpacing: 1, color: sec))),
              const SizedBox(height: 28),

              // ── Datos fijos ──
              _SecLabel(text: 'DATOS PERSONALES', sec: sec),
              const SizedBox(height: 12),
              _ReadonlyField(label: 'Nombre completo',
                  value: '${_usuario?.nombre ?? ''} ${_usuario?.apellido ?? ''}',
                  icon: Icons.person_outline,
                  prim: prim, sec: sec, surf: surf, div: div),
              const SizedBox(height: 10),
              _ReadonlyField(label: 'CI',
                  value: _usuario?.ci ?? '',
                  icon: Icons.badge_outlined,
                  prim: prim, sec: sec, surf: surf, div: div),
              const SizedBox(height: 10),
              _ReadonlyField(label: 'Correo electrónico',
                  value: _usuario?.email ?? '',
                  icon: Icons.email_outlined,
                  prim: prim, sec: sec, surf: surf, div: div),
              const SizedBox(height: 10),
              _ReadonlyField(label: 'Tipo de usuario',
                  value: (_usuario?.tipoUsuario ?? '').toUpperCase(),
                  icon: Icons.verified_user_outlined,
                  prim: prim, sec: sec, surf: surf, div: div),
              const SizedBox(height: 24),

              // ── Campo editable ──
              _SecLabel(text: 'DATOS EDITABLES', sec: sec),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: surf,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: div, width: 0.5)),
                child: TextFormField(
                  controller: _telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(fontFamily: 'monospace',
                      fontSize: 13, color: prim),
                  decoration: InputDecoration(
                    labelText: 'Teléfono',
                    labelStyle: TextStyle(fontFamily: 'monospace',
                        fontSize: 11, color: sec),
                    prefixIcon: Icon(Icons.phone_outlined, size: 18, color: sec),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.trim().length < 7) {
                      return 'Número inválido';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Los demás datos se modifican contactando al administrador.',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: sec, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 32),

              // ── Guardar ──
              SizedBox(width: double.infinity,
                child: GestureDetector(
                  onTap: _guardando ? null : _guardarCambios,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: NothingTheme.accentGreen,
                      borderRadius: BorderRadius.circular(12)),
                    child: Center(child: _guardando
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : const Text('GUARDAR CAMBIOS', style: TextStyle(
                            fontFamily: 'monospace', fontSize: 12,
                            fontWeight: FontWeight.w700, letterSpacing: 2,
                            color: Colors.black))),
                  ),
                )),
              const SizedBox(height: 12),

              // ── Cancelar ──
              SizedBox(width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: div, width: 0.5)),
                    child: Center(child: Text('CANCELAR', style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12,
                      fontWeight: FontWeight.w700, letterSpacing: 2,
                      color: sec))),
                  ),
                )),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarDefault(bool dark, Color prim, Color surf) => Container(
    color: surf,
    child: Icon(Icons.person, size: 48, color: prim.withOpacity(0.4)),
  );
}

// ── Widgets auxiliares ──

class _SecLabel extends StatelessWidget {
  final String text; final Color sec;
  const _SecLabel({required this.text, required this.sec});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(
    fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
    letterSpacing: 2.5, color: sec));
}

class _ReadonlyField extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color prim, sec, surf, div;
  const _ReadonlyField({
    required this.label, required this.value, required this.icon,
    required this.prim, required this.sec,
    required this.surf, required this.div,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: surf.withOpacity(0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: div.withOpacity(0.5), width: 0.5)),
    child: Row(children: [
      Icon(icon, size: 16, color: sec),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 9,
            color: sec, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 12,
            fontWeight: FontWeight.w600,
            color: prim.withOpacity(0.6))),
      ])),
      Icon(Icons.lock_outline, size: 12, color: sec.withOpacity(0.4)),
    ]),
  );
}
