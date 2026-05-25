import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../models/usuario_model.dart';
import 'registro_completar_screen.dart';

class RegistroEscanearScreen extends StatefulWidget {
  const RegistroEscanearScreen({super.key});
  @override
  State<RegistroEscanearScreen> createState() => _RegistroEscanearScreenState();
}

class _RegistroEscanearScreenState extends State<RegistroEscanearScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late SupabaseService _svc;
  late StorageService _store;

  bool _cargando = false;

  // Fotos CI
  File? _carnetAnverso, _carnetReverso;
  // Fotos Estudiante
  File? _univAnverso, _univReverso;

  final _ciCtrl     = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _apellCtrl  = TextEditingController();
  final _fechaCtrl  = TextEditingController();
  final _univCtrl   = TextEditingController();
  final _codCtrl    = TextEditingController();

  String _leyendoFoto = '';

  // Resultado de validación del carnet
  bool? _carnetValidado;   // null=no analizado, true=OK, false=inválido
  String _mensajeValidacion = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _store   = StorageService();
    _svc     = SupabaseService(_store);
    themeNotifier.addListener(_rebuild);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        // Limpiar campos y estado al cambiar de tab
        setState(() {
          _ciCtrl.clear(); _nombreCtrl.clear(); _apellCtrl.clear();
          _fechaCtrl.clear(); _univCtrl.clear(); _codCtrl.clear();
          _carnetAnverso = _carnetReverso = null;
          _univAnverso   = _univReverso   = null;
          _carnetValidado = null;
          _mensajeValidacion = '';
        });
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ciCtrl.dispose(); _nombreCtrl.dispose(); _apellCtrl.dispose();
    _fechaCtrl.dispose(); _univCtrl.dispose(); _codCtrl.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // ──────────────────────────────────────────────────────
  //  Tomar foto y procesar OCR + validación
  // ──────────────────────────────────────────────────────
  Future<void> _tomarFoto({
    required String tipo,
    required ImageSource fuente,
  }) async {
    final picker = ImagePicker();
    final XFile? imagen = await picker.pickImage(
      source: fuente,
      maxWidth: 1400,
      maxHeight: 1000,
      imageQuality: 92,
    );
    if (imagen == null) return;

    final archivo = File(imagen.path);

    setState(() {
      switch (tipo) {
        case 'ci_anverso':   _carnetAnverso = archivo; break;
        case 'ci_reverso':   _carnetReverso = archivo; break;
        case 'univ_anverso': _univAnverso   = archivo; break;
        case 'univ_reverso': _univReverso   = archivo; break;
      }
      _leyendoFoto    = 'Analizando imagen…';
      _cargando       = true;
      _carnetValidado = null;
      _mensajeValidacion = '';
    });

    try {
      final resultado = await _extraerYValidar(archivo, tipo);

      if (resultado == null) {
        // No se detectó texto de carnet — imagen inválida
        setState(() {
          _carnetValidado    = false;
          _mensajeValidacion = 'No se detectó un carnet válido. '
              'Asegúrate de fotografiar el carnet boliviano con buena iluminación.';
        });
        return;
      }

      if (resultado['valido'] == false) {
        setState(() {
          _carnetValidado    = false;
          _mensajeValidacion = resultado['razon'] ??
              'El documento no parece un carnet válido.';
        });
        return;
      }

      // Carnet válido — poblar campos
      setState(() {
        _carnetValidado    = true;
        _mensajeValidacion = '✓ Carnet verificado correctamente';
        if (resultado['ci']?.isNotEmpty == true) {
          _ciCtrl.text = resultado['ci']!;
        }
        if (resultado['nombre']?.isNotEmpty == true) {
          _nombreCtrl.text = resultado['nombre']!;
        }
        if (resultado['apellido']?.isNotEmpty == true) {
          _apellCtrl.text = resultado['apellido']!;
        }
        if (resultado['fecha']?.isNotEmpty == true) {
          _fechaCtrl.text = resultado['fecha']!;
        }
        if (resultado['universidad']?.isNotEmpty == true) {
          _univCtrl.text = resultado['universidad']!;
        }
        if (resultado['codigo']?.isNotEmpty == true) {
          _codCtrl.text = resultado['codigo']!;
        }
      });
      _snack('✓ Datos extraídos correctamente');
    } catch (e) {
      setState(() {
        _carnetValidado    = false;
        _mensajeValidacion = 'Error al analizar: $e';
      });
      _snack('Error al analizar imagen', isError: true);
    } finally {
      setState(() { _cargando = false; _leyendoFoto = ''; });
    }
  }

  // ──────────────────────────────────────────────────────
  //  OCR + validación de autenticidad del carnet
  // ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _extraerYValidar(File archivo, String tipo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(archivo);
      final recognized = await recognizer.processImage(inputImage);
      final texto = recognized.text;

      if (texto.trim().length < 20) {
        // Muy poco texto — no es un documento
        return null;
      }

      final esEstudiante = tipo.startsWith('univ');

      if (esEstudiante) {
        return _validarYParsearUniversitario(texto);
      } else {
        return _validarYParsearCI(texto);
      }
    } catch (e) {
      print('OCR error: $e');
      return null;
    } finally {
      await recognizer.close();
    }
  }

  // ──────────────────────────────────────────────────────
  //  Validar CI boliviano
  //  Requisitos: debe contener al menos 2 de estos indicadores:
  //   • número de 7-8 dígitos (el CI)
  //   • alguna palabra clave de la cédula boliviana
  //   • una fecha de nacimiento
  // ──────────────────────────────────────────────────────
  Map<String, dynamic> _validarYParsearCI(String texto) {
    final upper = texto.toUpperCase();

    // Palabras que aparecen en el CI boliviano real
    final palabrasClave = [
      'CEDULA', 'CÉDULA', 'IDENTIDAD', 'BOLIVIA', 'PLURINACIONAL',
      'ESTADO', 'CIVIL', 'NACIONAL', 'SERVICIO', 'GENERAL',
      'NACIMIENTO', 'FECHA', 'DOMICILIO', 'EXPEDICION', 'EXPIRACION',
    ];

    int indicadores = 0;

    // ¿Tiene número de 7-8 dígitos?
    final tieneCI = RegExp(r'\b\d{7,8}\b').hasMatch(texto);
    if (tieneCI) indicadores++;

    // ¿Tiene fecha?
    final tieneFecha = RegExp(r'\b\d{2}[/\-]\d{2}[/\-]\d{4}\b').hasMatch(texto);
    if (tieneFecha) indicadores++;

    // ¿Tiene palabras clave?
    final tienePalabrasClave =
        palabrasClave.any((p) => upper.contains(p));
    if (tienePalabrasClave) indicadores++;

    if (indicadores < 2) {
      return {
        'valido': false,
        'razon': 'La imagen no corresponde a un Carnet de Identidad boliviano. '
            'Fotografía el carnet con claridad.',
      };
    }

    final datos = _parsearCI(texto);
    datos['valido'] = 'true';
    return datos;
  }

  // ──────────────────────────────────────────────────────
  //  Validar carnet universitario
  //  Requisitos: mención de universidad o código estudiantil
  // ──────────────────────────────────────────────────────
  Map<String, dynamic> _validarYParsearUniversitario(String texto) {
    final upper = texto.toUpperCase();

    // Palabras que aparecen en un carnet universitario boliviano
    final palabrasUniv = [
      'UNIVERSIDAD', 'UNIV', 'UPDS', 'UMSS', 'UMSA', 'UCB', 'UNIFRANZ',
      'UAB', 'UAGRM', 'UDABOL', 'ESTUDIANTIL', 'ESTUDIANTE',
      'CARNET', 'CODIGO', 'CÓDIGO', 'MATRICULA', 'MATRÍCULA',
      'FACULTAD', 'CARRERA', 'SEMESTRE', 'GESTION',
    ];

    final tieneUniv = palabrasUniv.any((p) => upper.contains(p));
    final tieneCI   = RegExp(r'\b\d{7,8}\b').hasMatch(texto);
    final tieneCod  = RegExp(r'\b[A-Z0-9]{4,15}\b').hasMatch(texto);

    if (!tieneUniv) {
      return {
        'valido': false,
        'razon': 'La imagen no parece un carnet universitario. '
            'Fotografía tu carnet de estudiante con claridad.',
      };
    }

    if (!tieneCI && !tieneCod) {
      return {
        'valido': false,
        'razon': 'No se encontró CI ni código estudiantil en la imagen.',
      };
    }

    final datos = _parsearCarnetUniversitario(texto);
    datos['valido'] = 'true';
    return datos;
  }

  // ── Parser CI boliviano ──
  Map<String, String> _parsearCI(String texto) {
    final lineas = texto.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String ci = '', nombre = '', apellido = '', fecha = '';

    // CI — buscar "Nº" o número de 7-8 dígitos
    final regexCI = RegExp(r'N[°oO\u00BA]?\s*(\d{7,8})');
    final matchCI = regexCI.firstMatch(texto);
    if (matchCI != null) {
      ci = matchCI.group(1) ?? '';
    } else {
      for (final l in lineas) {
        final m = RegExp(r'\b(\d{7,8})\b').firstMatch(l);
        if (m != null) { ci = m.group(1)!; break; }
      }
    }

    // Fecha — DD/MM/YYYY o DD-MM-YYYY
    final regexFecha = RegExp(r'\b(\d{2})[/\-](\d{2})[/\-](\d{4})\b');
    final matchFecha = regexFecha.firstMatch(texto);
    if (matchFecha != null) {
      fecha =
          '${matchFecha.group(1)}/${matchFecha.group(2)}/${matchFecha.group(3)}';
    }

    // Nombre y apellido — líneas en mayúsculas sin números ni etiquetas
    final etiquetas = {
      'CEDULA', 'CÉDULA', 'IDENTIDAD', 'BOLIVIA', 'PLURINACIONAL',
      'ESTADO', 'FECHA', 'NACIMIENTO', 'EMISION', 'EXPIRACION',
      'DOMICILIO', 'OCUPACION', 'SERVICIO', 'GENERAL', 'CIVIL',
      'NACIONAL',
    };
    final candidatos = lineas.where((l) {
      final upper = l.toUpperCase();
      if (l.length < 3 || l.length > 45) return false;
      if (RegExp(r'\d').hasMatch(l)) return false;
      if (etiquetas.any((e) => upper.contains(e))) return false;
      return RegExp(r'^[A-ZÁÉÍÓÚÑ\s]+$').hasMatch(upper);
    }).toList();

    if (candidatos.isNotEmpty) nombre   = _titulizar(candidatos[0]);
    if (candidatos.length > 1) apellido = _titulizar(candidatos[1]);

    return {
      'ci': ci, 'nombre': nombre, 'apellido': apellido,
      'fecha': fecha, 'universidad': '', 'codigo': '',
    };
  }

  // ── Parser carnet universitario ──
  Map<String, String> _parsearCarnetUniversitario(String texto) {
    final lineas = texto.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String ci = '', nombre = '', apellido = '', fecha = '',
           universidad = '', codigo = '';

    // CI
    final mCI = RegExp(r'C\.?I\.?\s*:?\s*(\d{7,8})').firstMatch(texto);
    if (mCI != null) ci = mCI.group(1)!;
    if (ci.isEmpty) {
      final m = RegExp(r'\b(\d{7,8})\b').firstMatch(texto);
      if (m != null) ci = m.group(1)!;
    }

    // Código estudiantil
    final mCod = RegExp(r'C[oó]d[^\d]*(\w{4,15})').firstMatch(texto);
    if (mCod != null) codigo = mCod.group(1)!;

    // Fecha
    final mF = RegExp(r'\b(\d{2})[/\-](\d{2})[/\-](\d{4})\b').firstMatch(texto);
    if (mF != null) fecha = '${mF.group(1)}/${mF.group(2)}/${mF.group(3)}';

    // Universidad — línea que contenga indicador de universidad
    final univIndicadores = [
      'UPDS', 'UMSS', 'UMSA', 'UCB', 'UNIFRANZ', 'UAGRM', 'UAB',
      'UDABOL', 'UATF', 'UNIVERSIDAD', 'U.M', 'U.P', 'U.C',
    ];
    for (final l in lineas) {
      final upper = l.toUpperCase();
      if (univIndicadores.any((u) => upper.contains(u))) {
        universidad = _titulizar(l);
        break;
      }
    }

    // Nombre/apellido
    final candidatos = lineas.where((l) {
      if (l.length < 4 || RegExp(r'\d').hasMatch(l)) return false;
      return RegExp(r'^[A-ZÁÉÍÓÚÑ\s]+$').hasMatch(l.toUpperCase());
    }).toList();
    if (candidatos.isNotEmpty) nombre   = _titulizar(candidatos[0]);
    if (candidatos.length > 1) apellido = _titulizar(candidatos[1]);

    return {
      'ci': ci, 'nombre': nombre, 'apellido': apellido,
      'fecha': fecha, 'universidad': universidad, 'codigo': codigo,
    };
  }

  String _titulizar(String s) => s.toLowerCase().split(' ').map((w) =>
      w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');

  // ──────────────────────────────────────────────────────
  //  Modal cámara / galería
  // ──────────────────────────────────────────────────────
  Future<void> _mostrarOpcionesFoto(String tipo) async {
    final dark = themeNotifier.isDark;
    final fuente = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: NothingTheme.surf(dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: NothingTheme.div(dark),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('CAPTURAR FOTO',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 2,
                      color: NothingTheme.sec(dark))),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt,
                    color: NothingTheme.accentBlue),
                title: Text('Tomar foto con cámara',
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 12,
                        color: NothingTheme.prim(dark))),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: NothingTheme.accentPurple),
                title: Text('Elegir de galería',
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 12,
                        color: NothingTheme.prim(dark))),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (fuente == null || !mounted) return;
    await _tomarFoto(tipo: tipo, fuente: fuente);
  }

  // ──────────────────────────────────────────────────────
  //  Procesar y navegar
  // ──────────────────────────────────────────────────────
  Future<void> _procesarContinuar(bool esEstudiante) async {
    if (_carnetValidado != true) {
      _snack(
        esEstudiante
            ? 'Sube una foto válida de tu carnet universitario primero.'
            : 'Sube una foto válida de tu CI primero.',
        isError: true,
      );
      return;
    }

    final ci      = _ciCtrl.text.trim();
    final nombre  = _nombreCtrl.text.trim();
    final apellido = _apellCtrl.text.trim();

    if (ci.isEmpty || ci.length < 7) {
      _snack('Ingresa un CI válido (mínimo 7 dígitos)', isError: true); return;
    }
    if (nombre.isEmpty) {
      _snack('Ingresa el nombre', isError: true); return;
    }
    if (esEstudiante && _univCtrl.text.trim().isEmpty) {
      _snack('Ingresa el nombre de tu universidad', isError: true); return;
    }

    setState(() => _cargando = true);
    final existe = await _svc.ciYaExiste(ci);
    if (existe) {
      setState(() => _cargando = false);
      _snack('Este CI ya tiene una cuenta registrada.', isError: true);
      return;
    }

    DateTime? fechaNac;
    try {
      final partes = _fechaCtrl.text.split('/');
      if (partes.length == 3) {
        fechaNac = DateTime(
            int.parse(partes[2]), int.parse(partes[1]), int.parse(partes[0]));
      }
    } catch (_) {}

    setState(() => _cargando = false);

    final usuario = UsuarioModel(
      ci: ci,
      nombre: nombre.isNotEmpty ? nombre : 'Usuario',
      apellido: apellido,
      email: '',
      telefono: '',
      tipoUsuario: esEstudiante ? 'estudiante' : 'general',
      saldo: 0.0,
      activo: true,
      fechaNacimiento: fechaNac ?? DateTime.now(),
      fechaRegistro: DateTime.now(),
      emailVerificado: false,
    );

    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RegistroCompletarScreen(
          usuarioPreliminar: usuario,
          qrDataCompleto: ci,
          emailGeneradoAutomaticamente: esEstudiante,
        ),
      ));
    }
  }

  void _snack(String m, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        backgroundColor:
            isError ? NothingTheme.error : NothingTheme.accentGreen,
        duration: const Duration(seconds: 3),
      ));

  // ──────────────────────────────────────────────────────
  //  BUILD
  // ──────────────────────────────────────────────────────
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
      appBar: NothingAppBar(title: 'CREAR CUENTA', showBackButton: !_cargando),
      body: Column(children: [
        // Tab bar
        Container(
          color: bg,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: prim,
            unselectedLabelColor: sec,
            indicatorColor: prim,
            indicatorWeight: 0.5,
            labelStyle: const TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1.5),
            dividerColor: div,
            tabs: const [
              Tab(text: 'CARNET CI'),
              Tab(text: 'ESTUDIANTE'),
            ],
          ),
        ),

        // Indicador de carga OCR
        if (_cargando)
          Container(
            color: bg.withOpacity(0.0),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            child: Row(children: [
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: NothingTheme.accentPurple)),
              const SizedBox(width: 10),
              Text(
                _leyendoFoto.isNotEmpty ? _leyendoFoto : 'Procesando…',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 10,
                    color: NothingTheme.accentPurple),
              ),
            ]),
          ),

        // Banner de validación
        if (_carnetValidado != null && !_cargando)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (_carnetValidado!
                      ? NothingTheme.accentGreen
                      : NothingTheme.error)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_carnetValidado!
                        ? NothingTheme.accentGreen
                        : NothingTheme.error)
                    .withOpacity(0.4),
                width: 0.5,
              ),
            ),
            child: Row(children: [
              Icon(
                _carnetValidado! ? Icons.verified : Icons.error_outline,
                size: 16,
                color: _carnetValidado!
                    ? NothingTheme.accentGreen
                    : NothingTheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _mensajeValidacion,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: _carnetValidado!
                          ? NothingTheme.accentGreen
                          : NothingTheme.error),
                ),
              ),
            ]),
          ),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildTabCI(dark, bg, surf, sec, prim, div),
              _buildTabEstudiante(dark, bg, surf, sec, prim, div),
            ],
          ),
        ),
      ]),
    );
  }

  // ── TAB FOTO CI ──
  Widget _buildTabCI(bool dark, Color bg, Color surf, Color sec, Color prim, Color div) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoBox(
          text: 'Fotografía el anverso (lado con foto) de tu CI boliviano. '
              'Solo se aceptan carnets de identidad válidos.',
          dark: dark, sec: sec, surf: surf,
        ),
        const SizedBox(height: 20),

        Text('FOTOS DEL CARNET', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(child: _FotoBox(
            label: 'ANVERSO',
            sublabel: 'Lado con foto',
            icon: Icons.credit_card,
            tieneImagen: _carnetAnverso != null,
            imagenFile: _carnetAnverso,
            isDark: dark,
            validado: _carnetAnverso != null ? _carnetValidado : null,
            onTap: _cargando ? null : () => _mostrarOpcionesFoto('ci_anverso'),
          )),
          const SizedBox(width: 12),
          Expanded(child: _FotoBox(
            label: 'REVERSO',
            sublabel: 'Lado con datos',
            icon: Icons.credit_card_outlined,
            tieneImagen: _carnetReverso != null,
            imagenFile: _carnetReverso,
            isDark: dark,
            validado: null, // reverso es opcional / informativo
            onTap: _cargando ? null : () => _mostrarOpcionesFoto('ci_reverso'),
          )),
        ]),

        const SizedBox(height: 20),
        Text('DATOS DETECTADOS', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 4),
        Text('Revisa y corrige si es necesario', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            color: sec.withOpacity(0.6))),
        const SizedBox(height: 12),

        _Campo(label: 'NÚMERO DE CI', hint: 'Ej: 12345678',
            ctrl: _ciCtrl, keyboard: TextInputType.number,
            enabled: !_cargando, dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'NOMBRE(S)', hint: 'Juan Carlos',
            ctrl: _nombreCtrl, enabled: !_cargando,
            dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'APELLIDO(S)', hint: 'García López',
            ctrl: _apellCtrl, enabled: !_cargando,
            dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'FECHA DE NACIMIENTO', hint: 'DD/MM/AAAA',
            ctrl: _fechaCtrl, keyboard: TextInputType.datetime,
            enabled: !_cargando, dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 24),

        _BotonContinuar(
          label: 'CONTINUAR',
          icon: Icons.arrow_forward,
          color: NothingTheme.accentGreen,
          cargando: _cargando,
          onTap: () => _procesarContinuar(false),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── TAB ESTUDIANTE ──
  Widget _buildTabEstudiante(bool dark, Color bg, Color surf, Color sec, Color prim, Color div) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: NothingTheme.accentPurple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: NothingTheme.accentPurple.withOpacity(0.4), width: 0.5),
          ),
          child: const Row(children: [
            Icon(Icons.school_outlined,
                color: NothingTheme.accentPurple, size: 16),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tarifa estudiantil: 50% de descuento. '
                'Tu carnet universitario será verificado.',
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 11,
                    color: NothingTheme.accentPurple)),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        Text('CARNET UNIVERSITARIO', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(child: _FotoBox(
            label: 'ANVERSO',
            sublabel: 'Carnet univ.',
            icon: Icons.badge_outlined,
            tieneImagen: _univAnverso != null,
            imagenFile: _univAnverso,
            isDark: dark,
            accentColor: NothingTheme.accentPurple,
            validado: _univAnverso != null ? _carnetValidado : null,
            onTap: _cargando ? null : () => _mostrarOpcionesFoto('univ_anverso'),
          )),
          const SizedBox(width: 12),
          Expanded(child: _FotoBox(
            label: 'REVERSO',
            sublabel: 'CI / datos',
            icon: Icons.badge,
            tieneImagen: _univReverso != null,
            imagenFile: _univReverso,
            isDark: dark,
            accentColor: NothingTheme.accentPurple,
            validado: null,
            onTap: _cargando ? null : () => _mostrarOpcionesFoto('univ_reverso'),
          )),
        ]),

        const SizedBox(height: 20),
        Text('DATOS DEL ESTUDIANTE', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 4),
        Text('Revisa y corrige si es necesario', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, color: sec.withOpacity(0.6))),
        const SizedBox(height: 12),

        _Campo(label: 'CI', hint: '12345678',
            ctrl: _ciCtrl, keyboard: TextInputType.number,
            enabled: !_cargando, dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'NOMBRE(S)', hint: 'Juan Carlos',
            ctrl: _nombreCtrl, enabled: !_cargando,
            dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'APELLIDO(S)', hint: 'García',
            ctrl: _apellCtrl, enabled: !_cargando,
            dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'UNIVERSIDAD', hint: 'UPDS, UMSS, UCB…',
            ctrl: _univCtrl, enabled: !_cargando,
            dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'CÓDIGO ESTUDIANTIL', hint: 'CBA-2024-0001',
            ctrl: _codCtrl, enabled: !_cargando,
            dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 10),
        _Campo(label: 'FECHA DE NACIMIENTO', hint: 'DD/MM/AAAA',
            ctrl: _fechaCtrl, keyboard: TextInputType.datetime,
            enabled: !_cargando, dark: dark, prim: prim, sec: sec, surf: surf, div: div),
        const SizedBox(height: 24),

        _BotonContinuar(
          label: 'REGISTRAR COMO ESTUDIANTE',
          icon: Icons.school,
          color: NothingTheme.accentPurple,
          cargando: _cargando,
          onTap: () => _procesarContinuar(true),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Widgets auxiliares
// ─────────────────────────────────────────────

class _FotoBox extends StatelessWidget {
  final String label, sublabel;
  final IconData icon;
  final bool tieneImagen, isDark;
  final File? imagenFile;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool? validado; // null=no aplica, true=OK, false=inválido

  const _FotoBox({
    required this.label, required this.sublabel, required this.icon,
    required this.tieneImagen, required this.isDark,
    this.imagenFile, this.onTap, this.accentColor, this.validado,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = accentColor ?? NothingTheme.accentGreen;
    if (validado == false) accent = NothingTheme.error;
    if (validado == true)  accent = accentColor ?? NothingTheme.accentGreen;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 120,
        decoration: BoxDecoration(
          color: tieneImagen
              ? accent.withOpacity(0.08)
              : NothingTheme.surf(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tieneImagen ? accent.withOpacity(0.6) : NothingTheme.div(isDark),
            width: tieneImagen ? 1.0 : 0.5,
          ),
        ),
        child: tieneImagen && imagenFile != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(imagenFile!, fit: BoxFit.cover),
                  Container(color: Colors.black.withOpacity(0.35)),
                  Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        validado == false
                            ? Icons.cancel
                            : validado == true
                                ? Icons.check_circle
                                : Icons.check_circle,
                        size: 22, color: accent,
                      ),
                      const SizedBox(height: 4),
                      Text(label, style: TextStyle(
                          fontFamily: 'monospace', fontSize: 8,
                          fontWeight: FontWeight.w700, letterSpacing: 2,
                          color: accent)),
                      Text('TOCA PARA CAMBIAR', style: TextStyle(
                          fontFamily: 'monospace', fontSize: 7,
                          color: Colors.white.withOpacity(0.7))),
                    ],
                  )),
                ]),
              )
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 28,
                    color: onTap != null
                        ? NothingTheme.sec(isDark)
                        : NothingTheme.sec(isDark).withOpacity(0.3)),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 2,
                    color: NothingTheme.sec(isDark))),
                const SizedBox(height: 2),
                Text(sublabel, style: TextStyle(
                    fontFamily: 'monospace', fontSize: 8,
                    color: NothingTheme.sec(isDark).withOpacity(0.6))),
                const SizedBox(height: 4),
                Text(onTap != null ? 'TOCA PARA FOTO' : '…',
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 7,
                        color: accent.withOpacity(0.7), letterSpacing: 1)),
              ]),
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final TextInputType keyboard;
  final bool enabled, dark;
  final Color prim, sec, surf, div;

  const _Campo({
    required this.label, required this.hint, required this.ctrl,
    this.keyboard = TextInputType.text, required this.enabled,
    required this.dark, required this.prim, required this.sec,
    required this.surf, required this.div,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surf, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: div, width: 0.5),
      ),
      child: TextField(
        controller: ctrl, enabled: enabled, keyboardType: keyboard,
        style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: prim),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontFamily: 'monospace', fontSize: 9,
              letterSpacing: 1.5, color: sec),
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 11,
              color: sec.withOpacity(0.4)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _BotonContinuar extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool cargando;
  final VoidCallback onTap;

  const _BotonContinuar({
    required this.label, required this.icon, required this.color,
    required this.cargando, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: cargando ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: cargando ? color.withOpacity(0.4) : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: cargando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 16, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(label, style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 2,
                        color: Colors.black)),
                  ]),
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  final bool dark;
  final Color sec, surf;
  const _InfoBox(
      {required this.text, required this.dark, required this.sec, required this.surf});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: NothingTheme.accentBlue.withOpacity(0.3), width: 0.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline,
              color: NothingTheme.accentBlue, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: sec))),
        ]),
      );
}
