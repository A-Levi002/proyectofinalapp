import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../models/usuario_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class RegistroCompletarScreen extends StatefulWidget {
  final UsuarioModel usuarioPreliminar;
  final String qrDataCompleto;
  final bool emailGeneradoAutomaticamente;

  const RegistroCompletarScreen({
    required this.usuarioPreliminar,
    required this.qrDataCompleto,
    this.emailGeneradoAutomaticamente = false,
    super.key,
  });

  @override
  State<RegistroCompletarScreen> createState() => _RegistroCompletarScreenState();
}

class _RegistroCompletarScreenState extends State<RegistroCompletarScreen> {
  late SupabaseService _supabaseService;
  late StorageService _storageService;

  late TextEditingController _emailController;
  late TextEditingController _telefonoController;
  late TextEditingController _pinController;
  late TextEditingController _pinConfirmController;

  String _tipoUsuarioSeleccionado = 'general';
  bool _cargando = false;
  bool _mostrarPin = false;
  
  bool get _emailEsSoloLectura =>
      widget.emailGeneradoAutomaticamente && _tipoUsuarioSeleccionado == 'estudiante';

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _inicializarControladores();
  }

  void _initializeServices() {
    _storageService = StorageService();
    _supabaseService = SupabaseService(_storageService);
  }

  void _inicializarControladores() {
    if (widget.emailGeneradoAutomaticamente) {
      _tipoUsuarioSeleccionado = 'estudiante';
    }

    _emailController = TextEditingController(
      text: widget.usuarioPreliminar.email.isNotEmpty
          ? widget.usuarioPreliminar.email
          : '',
    );
    _telefonoController = TextEditingController();
    _pinController = TextEditingController();
    _pinConfirmController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _telefonoController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _completarRegistro() async {
    final emailIngresado = _emailController.text.trim();

    if (!_emailEsSoloLectura) {
      if (emailIngresado.isEmpty) {
        _mostrarError('El email es obligatorio');
        return;
      }

      if (!ValidatorsHelper.esEmailUniversitario(emailIngresado) &&
          _tipoUsuarioSeleccionado == 'estudiante') {
        _mostrarError('Email debe ser institucional para estudiantes');
        return;
      }
    } else {
      if (emailIngresado.isEmpty || !ValidatorsHelper.esEmailValido(emailIngresado)) {
        _mostrarError('Email generado inválido. Contacta soporte.');
        return;
      }
    }

    if (!ValidatorsHelper.esValidoTelefono(_telefonoController.text)) {
      _mostrarError('Teléfono inválido');
      return;
    }

    if (!ValidatorsHelper.esValidoPIN(_pinController.text)) {
      _mostrarError('PIN debe tener 4 dígitos');
      return;
    }

    if (_pinController.text != _pinConfirmController.text) {
      _mostrarError('Los PINs no coinciden');
      return;
    }

    setState(() => _cargando = true);

    try {
      final resultado = await _supabaseService.registrarUsuario(
        ci: widget.usuarioPreliminar.ci,
        nombre: widget.usuarioPreliminar.nombre,
        apellido: widget.usuarioPreliminar.apellido,
        email: emailIngresado,
        telefono: _telefonoController.text.trim(),
        tipoUsuario: _tipoUsuarioSeleccionado,
        pin: _pinController.text.trim(),
        fechaNacimiento: widget.usuarioPreliminar.fechaNacimiento,
      );

      if (!mounted) return;

      if (resultado['exito'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Registro exitoso! Iniciando sesión...'),
            backgroundColor: NothingTheme.success,
          ),
        );

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        });
      } else {
        _mostrarError(resultado['mensaje'] ?? 'Error en el registro');
      }
    } catch (e) {
      _mostrarError('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: NothingTheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(title: 'COMPLETAR REGISTRO'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Datos del Carnet
            Text('DATOS DEL CARNET', style: NothingTheme.label),
            const SizedBox(height: 12),

            if (widget.emailGeneradoAutomaticamente)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NothingTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NothingTheme.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: NothingTheme.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '✓ Email institucional detectado y generado automáticamente',
                        style: NothingTheme.body.copyWith(fontSize: 12, color: NothingTheme.success),
                      ),
                    ),
                  ],
                ),
              ),

            NothingCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildReadOnlyField('CI', widget.usuarioPreliminar.ci),
                  const Divider(color: NothingTheme.divider),
                  _buildReadOnlyField('Nombre', widget.usuarioPreliminar.nombre),
                  const Divider(color: NothingTheme.divider),
                  _buildReadOnlyField('Apellido', widget.usuarioPreliminar.apellido),
                  const Divider(color: NothingTheme.divider),
                  _buildReadOnlyField(
                    'Nacimiento',
                    FormateoHelper.formatearFecha(widget.usuarioPreliminar.fechaNacimiento),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Tipo de Usuario
            Text('TIPO DE USUARIO', style: NothingTheme.label),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: NothingTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NothingTheme.divider, width: 0.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _tipoUsuarioSeleccionado,
                  isExpanded: true,
                  dropdownColor: NothingTheme.surface,
                  style: NothingTheme.body,
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(value: 'estudiante', child: Text('Estudiante')),
                    DropdownMenuItem(value: 'adultomayor', child: Text('Adulto Mayor')),
                    DropdownMenuItem(value: 'discapacidad', child: Text('Discapacidad')),
                  ],
                  onChanged: (value) {
                    setState(() => _tipoUsuarioSeleccionado = value ?? 'general');
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Email
            NothingTextField(
              label: 'EMAIL',
              hint: 'correo@ejemplo.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_cargando && !_emailEsSoloLectura,
            ),
            if (_emailEsSoloLectura) ...[
              const SizedBox(height: 4),
              Text(
                '✓ Email institucional generado a partir de tu CI',
                style: NothingTheme.body.copyWith(fontSize: 11, color: NothingTheme.success),
              ),
            ],
            const SizedBox(height: 16),

            // Teléfono
            NothingTextField(
              label: 'TELÉFONO',
              hint: '67123456',
              controller: _telefonoController,
              keyboardType: TextInputType.phone,
              enabled: !_cargando,
            ),
            const SizedBox(height: 16),

            // PIN
            NothingTextField(
              label: 'PIN (4 DÍGITOS)',
              hint: '****',
              controller: _pinController,
              obscureText: !_mostrarPin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              enabled: !_cargando,
            ),
            const SizedBox(height: 16),

            // Confirmar PIN
            NothingTextField(
              label: 'CONFIRMAR PIN',
              hint: '****',
              controller: _pinConfirmController,
              obscureText: !_mostrarPin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              enabled: !_cargando,
            ),

            CheckboxListTile(
              value: _mostrarPin,
              onChanged: (value) => setState(() => _mostrarPin = value ?? false),
              title: Text('Mostrar PIN', style: NothingTheme.body),
              activeColor: NothingTheme.accentGreen,
            ),

            const SizedBox(height: 24),

            // Botón Registrarse
            NothingButton(
              label: 'CREAR CUENTA',
              onTap: _completarRegistro,
              isLoading: _cargando,
              filled: true,
              icon: Icons.person_add,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: NothingTheme.label),
          Text(value, style: NothingTheme.body),
        ],
      ),
    );
  }
}