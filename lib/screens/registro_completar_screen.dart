import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../models/usuario_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class RegistroCompletarScreen extends StatefulWidget {
  final UsuarioModel usuarioPreliminar;
  final String qrDataCompleto;
  // true = vino del tab ESTUDIANTE → tipo ya fijado
  final bool emailGeneradoAutomaticamente;

  const RegistroCompletarScreen({
    required this.usuarioPreliminar,
    required this.qrDataCompleto,
    this.emailGeneradoAutomaticamente = false,
    super.key,
  });

  @override
  State<RegistroCompletarScreen> createState() =>
      _RegistroCompletarScreenState();
}

class _RegistroCompletarScreenState extends State<RegistroCompletarScreen> {
  late SupabaseService _supabaseService;
  late StorageService _storageService;

  late TextEditingController _emailController;
  late TextEditingController _telefonoController;
  late TextEditingController _pinController;
  late TextEditingController _pinConfirmController;

  // El tipo viene del carnet escaneado; solo se puede cambiar cuando el
  // usuario llegó por el tab CI normal (no estudiante, no descuento especial).
  late String _tipoUsuarioSeleccionado;
  bool _cargando = false;
  bool _mostrarPin = false;

  // Si vino del tab CI normal, puede cambiar entre general / adultomayor / discapacidad
  // (estudiante se registra desde su propio tab con carnet universitario).
  bool get _puedeElegirTipo =>
      !widget.emailGeneradoAutomaticamente &&
      widget.usuarioPreliminar.tipoUsuario == 'general';

  bool get _emailEsSoloLectura =>
      widget.emailGeneradoAutomaticamente &&
      _tipoUsuarioSeleccionado == 'estudiante';

  @override
  void initState() {
    super.initState();
    _storageService = StorageService();
    _supabaseService = SupabaseService(_storageService);
    _inicializarControladores();
  }

  void _inicializarControladores() {
    // Tipo viene del carnet; no lo dejamos cambiar si ya es estudiante.
    _tipoUsuarioSeleccionado = widget.usuarioPreliminar.tipoUsuario;

    _emailController = TextEditingController(
      text: widget.usuarioPreliminar.email.isNotEmpty
          ? widget.usuarioPreliminar.email
          : '',
    );
    _telefonoController = TextEditingController();
    _pinController      = TextEditingController();
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
      if (_tipoUsuarioSeleccionado == 'estudiante' &&
          !ValidatorsHelper.esEmailUniversitario(emailIngresado)) {
        _mostrarError(
            'Para estudiantes el email debe ser institucional\n'
            '(ej: @upds.edu.bo, @umss.edu.bo, @ucb.edu.bo…)');
        return;
      }
      if (!ValidatorsHelper.esEmailValido(emailIngresado)) {
        _mostrarError('Formato de email inválido');
        return;
      }
    } else {
      if (emailIngresado.isEmpty ||
          !ValidatorsHelper.esEmailValido(emailIngresado)) {
        _mostrarError('Email generado inválido. Contacta soporte.');
        return;
      }
    }

    if (!ValidatorsHelper.esValidoTelefono(_telefonoController.text)) {
      _mostrarError('Teléfono inválido (8 dígitos en Bolivia)');
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('¡Registro exitoso! Iniciando sesión...'),
          backgroundColor: NothingTheme.success,
        ));
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pushReplacementNamed('/home');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: NothingTheme.error,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: const NothingAppBar(title: 'COMPLETAR REGISTRO'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── Datos leídos del carnet ──
            const Text('DATOS DEL CARNET', style: NothingTheme.label),
            const SizedBox(height: 12),

            NothingCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _readOnlyRow('CI', widget.usuarioPreliminar.ci),
                  const Divider(color: NothingTheme.divider),
                  _readOnlyRow('Nombre', widget.usuarioPreliminar.nombre),
                  const Divider(color: NothingTheme.divider),
                  _readOnlyRow('Apellido', widget.usuarioPreliminar.apellido),
                  const Divider(color: NothingTheme.divider),
                  _readOnlyRow(
                    'Nacimiento',
                    FormateoHelper.formatearFecha(
                        widget.usuarioPreliminar.fechaNacimiento),
                  ),
                  const Divider(color: NothingTheme.divider),
                  // Tipo detectado — badge visual
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tipo', style: NothingTheme.label),
                        _TipoBadge(tipo: _tipoUsuarioSeleccionado),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Selector de tipo SOLO para usuarios que vienen del tab CI general ──
            if (_puedeElegirTipo) ...[
              const SizedBox(height: 20),
              const Text('TIPO DE USUARIO', style: NothingTheme.label),
              const SizedBox(height: 4),
              Text(
                'Selecciona si aplicas a algún beneficio especial.',
                style: NothingTheme.body.copyWith(fontSize: 11,
                    color: NothingTheme.secondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: NothingTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: NothingTheme.divider, width: 0.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _tipoUsuarioSeleccionado,
                    isExpanded: true,
                    dropdownColor: NothingTheme.surface,
                    style: NothingTheme.body,
                    items: const [
                      DropdownMenuItem(
                          value: 'general', child: Text('General (sin descuento)')),
                      DropdownMenuItem(
                          value: 'adultomayor',
                          child: Text('Adulto Mayor (30% descuento)')),
                      DropdownMenuItem(
                          value: 'discapacidad',
                          child: Text('Discapacidad (gratuito)')),
                    ],
                    onChanged: (value) {
                      setState(
                          () => _tipoUsuarioSeleccionado = value ?? 'general');
                    },
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Email ──
            NothingTextField(
              label: 'EMAIL',
              hint: _tipoUsuarioSeleccionado == 'estudiante'
                  ? 'correo@upds.edu.bo'
                  : 'correo@ejemplo.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_cargando && !_emailEsSoloLectura,
            ),
            if (_emailEsSoloLectura)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '✓ Email institucional generado desde tu CI',
                  style: NothingTheme.body
                      .copyWith(fontSize: 11, color: NothingTheme.success),
                ),
              ),
            if (!_emailEsSoloLectura &&
                _tipoUsuarioSeleccionado == 'estudiante')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠ Usa tu correo institucional universitario',
                  style: NothingTheme.body.copyWith(
                      fontSize: 11, color: NothingTheme.accentOrange),
                ),
              ),
            const SizedBox(height: 16),

            // ── Teléfono ──
            NothingTextField(
              label: 'TELÉFONO',
              hint: '67123456',
              controller: _telefonoController,
              keyboardType: TextInputType.phone,
              enabled: !_cargando,
            ),
            const SizedBox(height: 16),

            // ── PIN ──
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
              onChanged: (v) => setState(() => _mostrarPin = v ?? false),
              title: const Text('Mostrar PIN', style: NothingTheme.body),
              activeColor: NothingTheme.accentGreen,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 24),

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

  Widget _readOnlyRow(String label, String value) {
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

// ── Badge visual para tipo de usuario ──
class _TipoBadge extends StatelessWidget {
  final String tipo;
  const _TipoBadge({required this.tipo});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tipo) {
      'estudiante'  => ('Estudiante', NothingTheme.accentPurple),
      'adultomayor' => ('Adulto Mayor', NothingTheme.accentBlue),
      'discapacidad'=> ('Discapacidad', NothingTheme.accentOrange),
      _             => ('General', NothingTheme.secondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color),
      ),
    );
  }
}
