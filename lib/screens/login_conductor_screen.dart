import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class LoginConductorScreen extends StatefulWidget {
  final SupabaseService supabaseService;
  final StorageService storageService;

  const LoginConductorScreen({
    required this.supabaseService,
    required this.storageService,
    super.key,
  });

  @override
  State<LoginConductorScreen> createState() => _LoginConductorScreenState();
}

class _LoginConductorScreenState extends State<LoginConductorScreen> {
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _ocultarPin = true;
  bool _cargando = false;

  @override
  void dispose() {
    _ciController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (_ciController.text.isEmpty || _pinController.text.isEmpty) {
      _mostrarError('Por favor completa todos los campos');
      return;
    }

    if (!ValidatorsHelper.esValidoCI(_ciController.text)) {
      _mostrarError('CI inválido (7-10 dígitos)');
      return;
    }

    if (!ValidatorsHelper.esValidoPIN(_pinController.text)) {
      _mostrarError('PIN debe tener 4 dígitos');
      return;
    }

    setState(() => _cargando = true);

    try {
      final resultado = await widget.supabaseService.loginConductor(
        ci: _ciController.text.trim(),
        pin: _pinController.text.trim(),
      );

      if (!mounted) return;

      if (resultado['exito'] == true) {
        // Guardar datos del conductor
        if (resultado['conductor'] != null) {
          await widget.storageService.guardarObjeto('conductor_data', resultado['conductor']);
        }
        await widget.storageService.guardar('tipo_usuario', 'conductor');
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/panel-conductor');
        }
      } else {
        _mostrarError(resultado['mensaje'] ?? 'Error desconocido');
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // Botón de retroceso
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              const SizedBox(height: 20),

              // Dot indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: NothingTheme.accentOrange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: NothingTheme.accentOrange.withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Título
              const Text('ACCESO', style: NothingTheme.heading),
              const Text('CONDUCTORES', style: NothingTheme.heading),
              const SizedBox(height: 8),
              Text(
                'Ingresa con tus credenciales de conductor',
                style: NothingTheme.body.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 48),

              // Campo CI
              NothingTextField(
                label: 'CARNET DE IDENTIDAD',
                hint: 'Ej: 12345678',
                controller: _ciController,
                keyboardType: TextInputType.number,
                enabled: !_cargando,
              ),
              const SizedBox(height: 24),

              // Campo PIN
              NothingTextField(
                label: 'PIN',
                hint: '****',
                controller: _pinController,
                obscureText: _ocultarPin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                enabled: !_cargando,
                suffixIcon: Icon(_ocultarPin ? Icons.visibility_off : Icons.visibility),
                onSuffixTap: () => setState(() => _ocultarPin = !_ocultarPin),
              ),
              const SizedBox(height: 32),

              // Botón Login
              NothingButton(
                label: 'INGRESAR COMO CONDUCTOR',
                onTap: _iniciarSesion,
                isLoading: _cargando,
                filled: true,
                icon: Icons.directions_bus,
                color: NothingTheme.accentOrange,
              ),
              const SizedBox(height: 16),

              // Botón Registro Conductor
              NothingButton(
                label: 'SOLICITAR REGISTRO',
                onTap: () => Navigator.of(context).pushNamed('/registro-conductor'),
                filled: false,
                icon: Icons.person_add,
              ),
              const SizedBox(height: 24),

              // Separador
              Row(
                children: [
                  Expanded(child: Divider(color: NothingTheme.divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('O', style: NothingTheme.body),
                  ),
                  Expanded(child: Divider(color: NothingTheme.divider)),
                ],
              ),
              const SizedBox(height: 24),

              // Botón Volver a Login Pasajero
              NothingButton(
                label: 'VOLVER A LOGIN PASAJEROS',
                onTap: () => Navigator.of(context).pushReplacementNamed('/login'),
                filled: false,
                icon: Icons.arrow_back,
              ),
              const SizedBox(height: 40),

              // Mensaje informativo
              NothingCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: NothingTheme.accentOrange, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '⚠️ Si aún no eres conductor registrado, completa el formulario de solicitud. El administrador revisará tus datos.',
                        style: NothingTheme.body.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Versión
              Center(
                child: Text(
                  'TransitApp v1.0.0',
                  style: NothingTheme.label.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}