import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  // Campos del formulario
  final ciController = TextEditingController();
  final nombreController = TextEditingController();
  final apellidoController = TextEditingController();
  final emailController = TextEditingController();
  final telefonoController = TextEditingController();
  final direccionController = TextEditingController();
  final numeroLicenciaController = TextEditingController();
  final empresaController = TextEditingController();

  DateTime? fechaNacimiento;
  DateTime? vigenciaLicencia;
  int zonaSeleccionada = 1;
  List<Map<String, dynamic>> zonas = [
    {'id': 1, 'nombre': 'Cercado de Cochabamba'},
  ];

  @override
  void initState() {
    super.initState();
    storageService = StorageService();
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
    super.dispose();
  }

  Future<void> _seleccionarFecha(BuildContext context,
      {required bool esNacimiento}) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1960),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: NothingTheme.accentOrange,
              surface: NothingTheme.surface,
            ),
          ),
          child: child!,
        );
      },
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

  Future<void> _registrarConductor() async {
    if (!_formKey.currentState!.validate()) return;
    if (fechaNacimiento == null) {
      _mostrarError('Selecciona tu fecha de nacimiento');
      return;
    }
    if (vigenciaLicencia == null) {
      _mostrarError('Selecciona la vigencia de tu licencia');
      return;
    }

    // Validar edad mínima
    final edad = DateTime.now().difference(fechaNacimiento!).inDays ~/ 365;
    if (edad < 18) {
      _mostrarError('Debes ser mayor de 18 años');
      return;
    }

    // Validar licencia vigente
    if (vigenciaLicencia!.isBefore(DateTime.now())) {
      _mostrarError('La licencia está vencida');
      return;
    }

    setState(() {
      _cargando = true;
      _errorMessage = null;
    });

    try {
      final resultado = await supabaseService.registrarConductor(
        ci: ciController.text.trim(),
        nombre: nombreController.text.trim(),
        apellido: apellidoController.text.trim(),
        email: emailController.text.trim(),
        telefono: telefonoController.text.trim(),
        direccion: direccionController.text.trim(),
        numeroLicencia: numeroLicenciaController.text.trim(),
        vigenciaLicencia: vigenciaLicencia!,
        empresa: empresaController.text.trim(),
        zonaId: zonaSeleccionada,
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
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje) {
    setState(() => _errorMessage = mensaje);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: NothingTheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: NothingTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(title: 'REGISTRO CONDUCTOR'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              NothingCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.directions_bus, size: 48, color: NothingTheme.accentOrange),
                    const SizedBox(height: 12),
                    Text(
                      'REGÍSTRATE COMO CONDUCTOR',
                      style: NothingTheme.label.copyWith(
                        color: NothingTheme.accentOrange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Completa el formulario. Tu solicitud será revisada por el administrador.',
                      style: NothingTheme.body.copyWith(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: NothingTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NothingTheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 18, color: NothingTheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: NothingTheme.body.copyWith(fontSize: 12, color: NothingTheme.error),
                        ),
                      ),
                    ],
                  ),
                ),

              // DATOS PERSONALES
              Text('DATOS PERSONALES', style: NothingTheme.label),
              const SizedBox(height: 12),

              NothingTextField(
                label: 'CARNET DE IDENTIDAD',
                hint: 'Ej: 12345678',
                controller: ciController,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Ingresa tu CI';
                  final limpio = value!.replaceAll(RegExp(r'[^0-9]'), '');
                  if (limpio.length < 7 || limpio.length > 10) return 'CI inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: NothingTextField(
                      label: 'NOMBRE',
                      hint: 'Juan',
                      controller: nombreController,
                      validator: (value) => (value?.isEmpty ?? true) ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NothingTextField(
                      label: 'APELLIDO',
                      hint: 'Pérez',
                      controller: apellidoController,
                      validator: (value) => (value?.isEmpty ?? true) ? 'Requerido' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildDatePickerField(
                label: 'FECHA DE NACIMIENTO',
                value: fechaNacimiento,
                hint: 'Selecciona tu fecha de nacimiento',
                onTap: () => _seleccionarFecha(context, esNacimiento: true),
              ),
              const SizedBox(height: 16),

              // DATOS DE CONTACTO
              Text('DATOS DE CONTACTO', style: NothingTheme.label),
              const SizedBox(height: 12),

              NothingTextField(
                label: 'EMAIL',
                hint: 'conductor@ejemplo.com',
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Ingresa email';
                  if (!value!.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              NothingTextField(
                label: 'TELÉFONO',
                hint: '67123456',
                controller: telefonoController,
                keyboardType: TextInputType.phone,
                validator: (value) => (value?.isEmpty ?? true) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              NothingTextField(
                label: 'DIRECCIÓN',
                hint: 'Calle/Avenida, N°',
                controller: direccionController,
                maxLines: 2,
                validator: (value) => (value?.isEmpty ?? true) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),

              // INFORMACIÓN DE LICENCIA
              Text('INFORMACIÓN DE LICENCIA', style: NothingTheme.label),
              const SizedBox(height: 12),

              NothingTextField(
                label: 'NÚMERO DE LICENCIA',
                hint: 'Ej: BOL-123456',
                controller: numeroLicenciaController,
                validator: (value) => (value?.isEmpty ?? true) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              _buildDatePickerField(
                label: 'VIGENCIA DE LICENCIA',
                value: vigenciaLicencia,
                hint: 'Fecha de vencimiento',
                onTap: () => _seleccionarFecha(context, esNacimiento: false),
              ),
              const SizedBox(height: 16),

              // EMPRESA Y ZONA
              Text('EMPRESA Y ZONA', style: NothingTheme.label),
              const SizedBox(height: 12),

              NothingTextField(
                label: 'EMPRESA',
                hint: 'Nombre de la empresa',
                controller: empresaController,
                validator: (value) => (value?.isEmpty ?? true) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Dropdown Zona
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ZONA DE COBERTURA', style: NothingTheme.label),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: NothingTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NothingTheme.divider, width: 0.5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: zonaSeleccionada,
                        isExpanded: true,
                        dropdownColor: NothingTheme.surface,
                        style: NothingTheme.body,
                        items: zonas.map((zona) {
                          return DropdownMenuItem<int>(
                            value: zona['id'] as int,
                            child: Text(zona['nombre'] as String),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => zonaSeleccionada = value ?? 1);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Aviso
              NothingCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: NothingTheme.accentOrange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tu solicitud será revisada por el administrador. Recibirás un correo con la decisión.',
                        style: NothingTheme.body.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Botón de registro
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
                    color: value != null ? NothingTheme.primary : NothingTheme.secondary,
                  ),
                ),
                Icon(Icons.calendar_today, size: 18, color: NothingTheme.secondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}