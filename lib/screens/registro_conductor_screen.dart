import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/nothing_theme.dart';

class RegistroConductorScreen extends StatefulWidget {
  const RegistroConductorScreen({super.key});

  @override
  State<RegistroConductorScreen> createState() =>
      _RegistroConductorScreenState();
}

class _RegistroConductorScreenState extends State<RegistroConductorScreen> {
  late SupabaseService supabaseService;
  late StorageService storageService;

  final _formKey = GlobalKey<FormState>();
  bool _cargando = false;
  String? _errorMessage;

  // ── Campos de texto ──
  final ciController           = TextEditingController();
  final nombreController       = TextEditingController();
  final apellidoController     = TextEditingController();
  final emailController        = TextEditingController();
  final telefonoController     = TextEditingController();
  final direccionController    = TextEditingController();
  final numeroLicenciaController = TextEditingController();
  final empresaController      = TextEditingController();
  final numeroBusController    = TextEditingController();
  final placaController        = TextEditingController();

  // ── Fechas ──
  DateTime? fechaNacimiento;
  DateTime? vigenciaLicencia;

  // ── Zona ──
  int zonaSeleccionada = 1;
  List<Map<String, dynamic>> zonas = [
    {'id': 1, 'nombre': 'Cercado de Cochabamba'},
  ];

  // ── Fotos ──
  File? _fotoCIAnverso;
  File? _fotoCIReverso;
  File? _fotoLicencia;
  File? _fotoPlaca;
  File? _fotoCoche;

  // ── Estado de validación de fotos ──
  bool? _ciValidado;       // null=no analizado, true=OK, false=inválido
  bool? _licenciaValidada;
  bool? _placaValidada;

  String _leyendoFoto = '';

  @override
  void initState() {
    super.initState();
    storageService  = StorageService();
    supabaseService = SupabaseService(storageService);
    _cargarZonas();
  }

  Future<void> _cargarZonas() async {
    final lista = await supabaseService.obtenerZonas();
    if (lista.isNotEmpty && mounted) {
      setState(() {
        zonas = lista;
        zonaSeleccionada = lista.first['id'] as int;
      });
    }
  }

  @override
  void dispose() {
    ciController.dispose();
    nombreController.dispose();
    apellidoController.dispose();
    emailController.dispose();
    telefonoController.dispose();
    direccionController.dispose();
    numeroLicenciaController.dispose();
    empresaController.dispose();
    numeroBusController.dispose();
    placaController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────
  //  Tomar / elegir foto
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
                    color: NothingTheme.accentOrange),
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
    await _procesarFoto(tipo: tipo, fuente: fuente);
  }

  Future<void> _procesarFoto({
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
        case 'ci_anverso':  _fotoCIAnverso  = archivo; _ciValidado       = null; break;
        case 'ci_reverso':  _fotoCIReverso  = archivo; break;
        case 'licencia':    _fotoLicencia   = archivo; _licenciaValidada = null; break;
        case 'placa':       _fotoPlaca      = archivo; _placaValidada    = null; break;
        case 'coche':       _fotoCoche      = archivo; break;
      }
      _leyendoFoto = 'Analizando imagen…';
      _cargando = true;
    });

    try {
      switch (tipo) {
        case 'ci_anverso':
          final r = await _validarCI(archivo);
          setState(() {
            _ciValidado = r['valido'] as bool;
            if (r['valido'] == true) {
              if ((r['ci'] as String).isNotEmpty) {
                ciController.text = r['ci']!;
              }
              if ((r['nombre'] as String).isNotEmpty) {
                nombreController.text = r['nombre']!;
              }
              if ((r['apellido'] as String).isNotEmpty) {
                apellidoController.text = r['apellido']!;
              }
              if ((r['fecha'] as String).isNotEmpty) {
                try {
                  final p = (r['fecha'] as String).split('/');
                  if (p.length == 3) {
                    fechaNacimiento = DateTime(
                        int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                  }
                } catch (_) {}
              }
            }
          });
          if (r['valido'] == true) {
            _snack('✓ CI verificado correctamente');
          } else {
            _snack('No se detectó un CI boliviano válido. '
                'Fotografíalo con buena iluminación.', isError: true);
          }
          break;

        case 'licencia':
          final r = await _validarLicencia(archivo);
          setState(() {
            _licenciaValidada = r['valido'] as bool;
            if (r['valido'] == true && (r['numero'] as String).isNotEmpty) {
              numeroLicenciaController.text = r['numero']!;
            }
          });
          if (r['valido'] == true) {
            _snack('✓ Licencia de conducir verificada');
          } else {
            _snack('No se detectó una licencia de conducir válida.', isError: true);
          }
          break;

        case 'placa':
          final r = await _validarPlaca(archivo);
          setState(() {
            _placaValidada = r['valido'] as bool;
            if (r['valido'] == true && (r['placa'] as String).isNotEmpty) {
              placaController.text = r['placa']!;
            }
          });
          if (r['valido'] == true) {
            _snack('✓ Placa detectada: ${r['placa']}');
          } else {
            _snack('No se detectó una placa boliviana válida.', isError: true);
          }
          break;

        case 'coche':
          _snack('✓ Foto del vehículo guardada');
          break;

        case 'ci_reverso':
          _snack('✓ Reverso del CI guardado');
          break;
      }
    } catch (e) {
      _snack('Error al analizar: $e', isError: true);
    } finally {
      setState(() { _cargando = false; _leyendoFoto = ''; });
    }
  }

  // ──────────────────────────────────────────────────────
  //  Validaciones OCR
  // ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _validarCI(File archivo) async {
    final texto = await _ocr(archivo);
    if (texto == null || texto.trim().length < 20) {
      return {'valido': false, 'ci': '', 'nombre': '', 'apellido': '', 'fecha': ''};
    }
    final upper = texto.toUpperCase();
    final palabrasClave = [
      'CEDULA', 'CÉDULA', 'IDENTIDAD', 'BOLIVIA', 'PLURINACIONAL',
      'ESTADO', 'CIVIL', 'NACIONAL', 'SERVICIO', 'NACIMIENTO', 'DOMICILIO',
    ];
    int score = 0;
    if (RegExp(r'\b\d{7,8}\b').hasMatch(texto)) score++;
    if (RegExp(r'\b\d{2}[/\-]\d{2}[/\-]\d{4}\b').hasMatch(texto)) score++;
    if (palabrasClave.any((p) => upper.contains(p))) score++;

    if (score < 2) return {'valido': false, 'ci': '', 'nombre': '', 'apellido': '', 'fecha': ''};

    return {
      'valido': true,
      ..._parsearCI(texto),
    };
  }

  Future<Map<String, dynamic>> _validarLicencia(File archivo) async {
    final texto = await _ocr(archivo);
    if (texto == null || texto.trim().length < 15) {
      return {'valido': false, 'numero': ''};
    }
    final upper = texto.toUpperCase();
    // Palabras que aparecen en licencias bolivianas
    final indicadores = [
      'LICENCIA', 'CONDUCIR', 'TRANSITO', 'TRÁNSITO', 'DRIVER',
      'TRANSPORTE', 'POLICIAL', 'BOLIVIA', 'CATEGORIA', 'CATEGORÍA',
    ];
    final tieneIndicador = indicadores.any((p) => upper.contains(p));
    // Número de licencia: letras + guión + números
    final mNum = RegExp(r'[A-Z]{2,4}[\-\s]?\d{4,8}').firstMatch(texto);
    final tieneNumero = mNum != null || RegExp(r'\b\d{5,10}\b').hasMatch(texto);

    if (!tieneIndicador && !tieneNumero) {
      return {'valido': false, 'numero': ''};
    }

    String numero = '';
    if (mNum != null) {
      numero = mNum.group(0)!.replaceAll(' ', '-');
    } else {
      final m = RegExp(r'\b(\d{5,10})\b').firstMatch(texto);
      if (m != null) numero = m.group(1)!;
    }

    return {'valido': true, 'numero': numero};
  }

  Future<Map<String, dynamic>> _validarPlaca(File archivo) async {
    final texto = await _ocr(archivo);
    if (texto == null || texto.trim().length < 3) {
      return {'valido': false, 'placa': ''};
    }
    // Placa boliviana: 3-4 letras + 3-4 números (ej: ABC-1234, 1234-ABC)
    final regexPlaca = RegExp(
        r'\b([A-Z]{1,4}[\-\s]?\d{3,4}|\d{3,4}[\-\s]?[A-Z]{1,4})\b');
    final match = regexPlaca.firstMatch(texto.toUpperCase());
    if (match == null) {
      return {'valido': false, 'placa': ''};
    }
    final placa = match.group(0)!.replaceAll(' ', '-').toUpperCase();
    return {'valido': true, 'placa': placa};
  }

  Future<String?> _ocr(File archivo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFile(archivo);
      final result = await recognizer.processImage(input);
      return result.text.isEmpty ? null : result.text;
    } catch (e) {
      print('OCR error: $e');
      return null;
    } finally {
      await recognizer.close();
    }
  }

  Map<String, String> _parsearCI(String texto) {
    final lineas = texto.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    String ci = '', nombre = '', apellido = '', fecha = '';

    final mCI = RegExp(r'N[°oO\u00BA]?\s*(\d{7,8})').firstMatch(texto);
    if (mCI != null) {
      ci = mCI.group(1)!;
    } else {
      for (final l in lineas) {
        final m = RegExp(r'\b(\d{7,8})\b').firstMatch(l);
        if (m != null) { ci = m.group(1)!; break; }
      }
    }

    final mF = RegExp(r'\b(\d{2})[/\-](\d{2})[/\-](\d{4})\b').firstMatch(texto);
    if (mF != null) fecha = '${mF.group(1)}/${mF.group(2)}/${mF.group(3)}';

    final etiquetas = {
      'CEDULA', 'CÉDULA', 'IDENTIDAD', 'BOLIVIA', 'PLURINACIONAL',
      'ESTADO', 'FECHA', 'NACIMIENTO', 'EMISION', 'EXPIRACION',
      'DOMICILIO', 'OCUPACION', 'SERVICIO', 'GENERAL', 'CIVIL', 'NACIONAL',
    };
    final candidatos = lineas.where((l) {
      final up = l.toUpperCase();
      if (l.length < 3 || l.length > 45) return false;
      if (RegExp(r'\d').hasMatch(l)) return false;
      if (etiquetas.any((e) => up.contains(e))) return false;
      return RegExp(r'^[A-ZÁÉÍÓÚÑ\s]+$').hasMatch(up);
    }).toList();

    if (candidatos.isNotEmpty) nombre   = _titulizar(candidatos[0]);
    if (candidatos.length > 1) apellido = _titulizar(candidatos[1]);

    return {'ci': ci, 'nombre': nombre, 'apellido': apellido, 'fecha': fecha};
  }

  String _titulizar(String s) => s.toLowerCase().split(' ').map((w) =>
      w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');

  // ──────────────────────────────────────────────────────
  //  Subir fotos a Supabase Storage y obtener URLs
  // ──────────────────────────────────────────────────────
  Future<String?> _subirFoto(File archivo, String ruta) async {
    try {
      final supabase = Supabase.instance.client;
      final bytes = await archivo.readAsBytes();
      await supabase.storage
          .from('conductores-docs')
          .uploadBinary(ruta, bytes,
              fileOptions: const FileOptions(upsert: true));
      return supabase.storage
          .from('conductores-docs')
          .getPublicUrl(ruta);
    } catch (e) {
      print('Error subiendo foto: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────
  //  Registrar conductor
  // ──────────────────────────────────────────────────────
  Future<void> _registrarConductor() async {
    if (!_formKey.currentState!.validate()) return;

    if (_fotoCIAnverso == null) {
      _mostrarError('Sube la foto del anverso de tu CI');
      return;
    }
    if (_ciValidado != true) {
      _mostrarError('El CI no fue verificado correctamente. '
          'Vuelve a fotografiar tu carnet.');
      return;
    }
    if (_fotoLicencia == null) {
      _mostrarError('Sube la foto de tu licencia de conducir');
      return;
    }
    if (_licenciaValidada != true) {
      _mostrarError('La licencia no fue verificada. '
          'Fotografía tu licencia de conducir.');
      return;
    }
    if (_fotoPlaca == null) {
      _mostrarError('Sube la foto de la placa de tu vehículo');
      return;
    }
    if (_placaValidada != true) {
      _mostrarError('La placa no fue detectada. '
          'Fotografía la placa claramente.');
      return;
    }
    if (_fotoCoche == null) {
      _mostrarError('Sube una foto del vehículo');
      return;
    }
    if (fechaNacimiento == null) {
      _mostrarError('Selecciona tu fecha de nacimiento');
      return;
    }
    if (vigenciaLicencia == null) {
      _mostrarError('Selecciona la vigencia de tu licencia');
      return;
    }
    final edad = DateTime.now().difference(fechaNacimiento!).inDays ~/ 365;
    if (edad < 18) {
      _mostrarError('Debes ser mayor de 18 años');
      return;
    }
    if (vigenciaLicencia!.isBefore(DateTime.now())) {
      _mostrarError('La licencia está vencida');
      return;
    }

    setState(() { _cargando = true; _errorMessage = null; });

    try {
      final ci = ciController.text.trim();

      // Subir fotos
      setState(() => _leyendoFoto = 'Subiendo documentos…');

      final urlCIAnverso = await _subirFoto(
          _fotoCIAnverso!, 'ci/$ci/anverso.jpg');
      final urlCIReverso = _fotoCIReverso != null
          ? await _subirFoto(_fotoCIReverso!, 'ci/$ci/reverso.jpg')
          : null;
      final urlLicencia = await _subirFoto(
          _fotoLicencia!, 'licencia/$ci/licencia.jpg');
      final urlPlaca = await _subirFoto(
          _fotoPlaca!, 'vehiculo/$ci/placa.jpg');
      final urlCoche = await _subirFoto(
          _fotoCoche!, 'vehiculo/$ci/coche.jpg');

      setState(() => _leyendoFoto = 'Enviando solicitud…');

      final resultado = await supabaseService.registrarConductor(
        ci: ci,
        nombre: nombreController.text.trim(),
        apellido: apellidoController.text.trim(),
        email: emailController.text.trim(),
        telefono: telefonoController.text.trim(),
        direccion: direccionController.text.trim(),
        numeroLicencia: numeroLicenciaController.text.trim(),
        fechaNacimiento: fechaNacimiento!,
        vigenciaLicencia: vigenciaLicencia!,
        empresa: empresaController.text.trim(),
        numeroBus: numeroBusController.text.trim(),
        placa: placaController.text.trim(),
        zonaId: zonaSeleccionada,
        fotoCIUrl: urlCIAnverso,
        fotoLicenciaUrl: urlLicencia,
        fotoPlacaUrl: urlPlaca,
        fotoCocheUrl: urlCoche,
      );

      if (resultado['exito'] == true) {
        _mostrarExito('✓ Solicitud enviada. Espera aprobación del administrador.');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        String mensaje = resultado['mensaje'] ?? 'Error en el registro';
        if (resultado['codigo'] == 'CI_DUPLICADO') {
          mensaje = 'Este CI ya está registrado como conductor.';
        }
        _mostrarError(mensaje);
      }
    } catch (e) {
      _mostrarError('Error de conexión: $e');
    } finally {
      if (mounted) setState(() { _cargando = false; _leyendoFoto = ''; });
    }
  }

  void _mostrarError(String mensaje) {
    setState(() => _errorMessage = mensaje);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: NothingTheme.error,
      duration: const Duration(seconds: 4),
    ));
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: NothingTheme.success,
      duration: const Duration(seconds: 3),
    ));
  }

  void _snack(String m, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      backgroundColor: isError ? NothingTheme.error : NothingTheme.accentGreen,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _seleccionarFecha(BuildContext context,
      {required bool esNacimiento}) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esNacimiento ? DateTime(1990) : DateTime.now(),
      firstDate: esNacimiento ? DateTime(1950) : DateTime.now(),
      lastDate: esNacimiento ? DateTime.now() : DateTime(2040),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: NothingTheme.accentOrange,
            surface: NothingTheme.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (fecha != null) {
      setState(() {
        if (esNacimiento) {
          fechaNacimiento = fecha;
        } else {
          vigenciaLicencia = fecha;
        }
      });
    }
  }

  // ──────────────────────────────────────────────────────
  //  BUILD
  // ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;

    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: const NothingAppBar(title: 'REGISTRO CONDUCTOR'),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──
                  NothingCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      const Icon(Icons.directions_bus,
                          size: 48, color: NothingTheme.accentOrange),
                      const SizedBox(height: 12),
                      Text('REGÍSTRATE COMO CONDUCTOR',
                          style: NothingTheme.label.copyWith(
                              color: NothingTheme.accentOrange)),
                      const SizedBox(height: 8),
                      Text(
                        'Sube tus documentos reales. '
                        'Tu solicitud será revisada por el administrador.',
                        style: NothingTheme.body.copyWith(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Error ──
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: NothingTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: NothingTheme.error.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            size: 18, color: NothingTheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_errorMessage!,
                              style: NothingTheme.body.copyWith(
                                  fontSize: 12,
                                  color: NothingTheme.error)),
                        ),
                      ]),
                    ),

                  // ════════════════════════════════════════
                  //  SECCIÓN 1 — CARNET DE IDENTIDAD
                  // ════════════════════════════════════════
                  const _SeccionTitulo(
                    titulo: 'CARNET DE IDENTIDAD',
                    subtitulo: 'Fotografía tu CI boliviano (obligatorio)',
                    icono: Icons.credit_card,
                    color: NothingTheme.accentBlue,
                  ),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: _DocFotoBox(
                        label: 'CI ANVERSO',
                        sublabel: 'Lado con foto',
                        icon: Icons.credit_card,
                        archivo: _fotoCIAnverso,
                        validado: _ciValidado,
                        accentColor: NothingTheme.accentBlue,
                        isDark: dark,
                        onTap: _cargando
                            ? null
                            : () => _mostrarOpcionesFoto('ci_anverso'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DocFotoBox(
                        label: 'CI REVERSO',
                        sublabel: 'Lado con QR',
                        icon: Icons.credit_card_outlined,
                        archivo: _fotoCIReverso,
                        validado: null,
                        accentColor: NothingTheme.accentBlue,
                        isDark: dark,
                        onTap: _cargando
                            ? null
                            : () => _mostrarOpcionesFoto('ci_reverso'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // ── Datos del CI (autocompletados) ──
                  NothingTextField(
                    label: 'CARNET DE IDENTIDAD',
                    hint: 'Ej: 12345678',
                    controller: ciController,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v?.isEmpty ?? true) return 'Ingresa tu CI';
                      final l = v!.replaceAll(RegExp(r'[^0-9]'), '');
                      if (l.length < 7 || l.length > 10) return 'CI inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: NothingTextField(
                        label: 'NOMBRE',
                        hint: 'Juan',
                        controller: nombreController,
                        validator: (v) =>
                            (v?.isEmpty ?? true) ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NothingTextField(
                        label: 'APELLIDO',
                        hint: 'Pérez',
                        controller: apellidoController,
                        validator: (v) =>
                            (v?.isEmpty ?? true) ? 'Requerido' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  _buildDatePickerField(
                    label: 'FECHA DE NACIMIENTO',
                    value: fechaNacimiento,
                    hint: 'Selecciona tu fecha de nacimiento',
                    onTap: () =>
                        _seleccionarFecha(context, esNacimiento: true),
                  ),
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════
                  //  SECCIÓN 2 — LICENCIA DE CONDUCIR
                  // ════════════════════════════════════════
                  const _SeccionTitulo(
                    titulo: 'LICENCIA DE CONDUCIR',
                    subtitulo: 'Fotografía tu licencia (obligatorio)',
                    icono: Icons.badge,
                    color: NothingTheme.accentGreen,
                  ),
                  const SizedBox(height: 12),

                  _DocFotoBox(
                    label: 'FOTO LICENCIA',
                    sublabel: 'Licencia de conducir',
                    icon: Icons.badge_outlined,
                    archivo: _fotoLicencia,
                    validado: _licenciaValidada,
                    accentColor: NothingTheme.accentGreen,
                    isDark: dark,
                    onTap: _cargando
                        ? null
                        : () => _mostrarOpcionesFoto('licencia'),
                    fullWidth: true,
                  ),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'NÚMERO DE LICENCIA',
                    hint: 'Ej: BOL-123456',
                    controller: numeroLicenciaController,
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),

                  _buildDatePickerField(
                    label: 'VIGENCIA DE LICENCIA',
                    value: vigenciaLicencia,
                    hint: 'Fecha de vencimiento',
                    onTap: () =>
                        _seleccionarFecha(context, esNacimiento: false),
                  ),
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════
                  //  SECCIÓN 3 — VEHÍCULO
                  // ════════════════════════════════════════
                  const _SeccionTitulo(
                    titulo: 'VEHÍCULO',
                    subtitulo: 'Placa y foto del auto que usarás en la ruta',
                    icono: Icons.directions_car,
                    color: NothingTheme.accentOrange,
                  ),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: _DocFotoBox(
                        label: 'FOTO PLACA',
                        sublabel: 'Placa del auto',
                        icon: Icons.confirmation_number_outlined,
                        archivo: _fotoPlaca,
                        validado: _placaValidada,
                        accentColor: NothingTheme.accentOrange,
                        isDark: dark,
                        onTap: _cargando
                            ? null
                            : () => _mostrarOpcionesFoto('placa'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DocFotoBox(
                        label: 'FOTO COCHE',
                        sublabel: 'Vista exterior',
                        icon: Icons.directions_car_outlined,
                        archivo: _fotoCoche,
                        validado: null, // solo visual, no se parsea
                        accentColor: NothingTheme.accentOrange,
                        isDark: dark,
                        onTap: _cargando
                            ? null
                            : () => _mostrarOpcionesFoto('coche'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'PLACA DEL VEHÍCULO',
                    hint: 'Ej: ABC-1234',
                    controller: placaController,
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'NÚMERO DE BUS / TRUFI',
                    hint: 'Ej: 10, 2B (opcional)',
                    controller: numeroBusController,
                  ),
                  const SizedBox(height: 20),

                  // ════════════════════════════════════════
                  //  SECCIÓN 4 — CONTACTO Y EMPRESA
                  // ════════════════════════════════════════
                  const _SeccionTitulo(
                    titulo: 'CONTACTO Y EMPRESA',
                    subtitulo: null,
                    icono: Icons.business,
                    color: NothingTheme.accentPurple,
                  ),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'EMAIL',
                    hint: 'conductor@ejemplo.com',
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v?.isEmpty ?? true) return 'Ingresa email';
                      if (!v!.contains('@')) return 'Email inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'TELÉFONO',
                    hint: '67123456',
                    controller: telefonoController,
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'DIRECCIÓN',
                    hint: 'Calle/Avenida, N°',
                    controller: direccionController,
                    maxLines: 2,
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),

                  NothingTextField(
                    label: 'EMPRESA',
                    hint: 'Nombre de la empresa o sindicato',
                    controller: empresaController,
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),

                  // Zona
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ZONA DE COBERTURA', style: NothingTheme.label),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: NothingTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: NothingTheme.divider, width: 0.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: zonaSeleccionada,
                            isExpanded: true,
                            dropdownColor: NothingTheme.surface,
                            style: NothingTheme.body,
                            items: zonas.map((z) => DropdownMenuItem<int>(
                              value: z['id'] as int,
                              child: Text(z['nombre'] as String),
                            )).toList(),
                            onChanged: (v) =>
                                setState(() => zonaSeleccionada = v ?? 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Aviso
                  NothingCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: NothingTheme.accentOrange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tu solicitud y documentos serán revisados por el '
                          'administrador. Recibirás respuesta por correo.',
                          style: NothingTheme.body.copyWith(fontSize: 11),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  NothingButton(
                    label: 'ENVIAR SOLICITUD',
                    onTap: _registrarConductor,
                    isLoading: _cargando,
                    filled: true,
                    icon: Icons.send,
                    color: NothingTheme.accentOrange,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Overlay de carga
          if (_cargando)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: Center(
                child: NothingCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(
                        color: NothingTheme.accentOrange, strokeWidth: 2),
                    const SizedBox(height: 16),
                    Text(
                      _leyendoFoto.isNotEmpty
                          ? _leyendoFoto
                          : 'Procesando…',
                      style: NothingTheme.body
                          .copyWith(fontSize: 12),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required DateTime? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: NothingTheme.label),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: NothingTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NothingTheme.divider, width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value != null
                      ? DateFormat('dd/MM/yyyy').format(value)
                      : hint,
                  style: NothingTheme.body.copyWith(
                    color: value != null
                        ? NothingTheme.primary
                        : NothingTheme.secondary,
                  ),
                ),
                const Icon(Icons.calendar_today,
                    size: 18, color: NothingTheme.secondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Widget: caja de foto de documento
// ─────────────────────────────────────────────
class _DocFotoBox extends StatelessWidget {
  final String label, sublabel;
  final IconData icon;
  final File? archivo;
  final bool? validado;
  final Color accentColor;
  final bool isDark;
  final VoidCallback? onTap;
  final bool fullWidth;

  const _DocFotoBox({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.archivo,
    required this.validado,
    required this.accentColor,
    required this.isDark,
    this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    Color color = accentColor;
    if (validado == false) color = NothingTheme.error;

    final tieneImagen = archivo != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: fullWidth ? 140 : 120,
        decoration: BoxDecoration(
          color: tieneImagen
              ? color.withOpacity(0.08)
              : NothingTheme.surf(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tieneImagen
                ? color.withOpacity(0.6)
                : NothingTheme.div(isDark),
            width: tieneImagen ? 1.0 : 0.5,
          ),
        ),
        child: tieneImagen
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(archivo!, fit: BoxFit.cover),
                  Container(color: Colors.black.withOpacity(0.35)),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          validado == false
                              ? Icons.cancel
                              : Icons.check_circle,
                          size: 24, color: color,
                        ),
                        const SizedBox(height: 4),
                        Text(label,
                            style: TextStyle(
                                fontFamily: 'monospace', fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2, color: color)),
                        if (validado == false)
                          const Text('INVÁLIDO', style: TextStyle(
                              fontFamily: 'monospace', fontSize: 7,
                              color: NothingTheme.error)),
                        if (validado == true)
                          Text('VERIFICADO', style: TextStyle(
                              fontFamily: 'monospace', fontSize: 7,
                              color: color)),
                        Text('TOCA PARA CAMBIAR',
                            style: TextStyle(
                                fontFamily: 'monospace', fontSize: 7,
                                color: Colors.white.withOpacity(0.6))),
                      ],
                    ),
                  ),
                ]),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28,
                      color: onTap != null
                          ? NothingTheme.sec(isDark)
                          : NothingTheme.sec(isDark).withOpacity(0.3)),
                  const SizedBox(height: 8),
                  Text(label,
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 9,
                          fontWeight: FontWeight.w700, letterSpacing: 2,
                          color: NothingTheme.sec(isDark))),
                  const SizedBox(height: 2),
                  Text(sublabel,
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 8,
                          color: NothingTheme.sec(isDark).withOpacity(0.6))),
                  const SizedBox(height: 4),
                  Text('TOCA PARA FOTO',
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 7,
                          color: color.withOpacity(0.7), letterSpacing: 1)),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Widget: título de sección
// ─────────────────────────────────────────────
class _SeccionTitulo extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final Color color;

  const _SeccionTitulo({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icono, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: NothingTheme.label.copyWith(color: color)),
            if (subtitulo != null)
              Text(subtitulo!,
                  style: NothingTheme.body
                      .copyWith(fontSize: 10, color: NothingTheme.secondary)),
          ],
        ),
      ],
    );
  }
}
