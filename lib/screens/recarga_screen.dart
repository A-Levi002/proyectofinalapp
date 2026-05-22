import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class RecargaScreen extends StatefulWidget {
  final StorageService? storageService;

  const RecargaScreen({this.storageService, super.key});

  @override
  State<RecargaScreen> createState() => _RecargaScreenState();
}

class _RecargaScreenState extends State<RecargaScreen> {
  late SupabaseService _supabaseService;
  late StorageService _storageService;

  double _montoSeleccionado = 10.0;
  double _montoPersonalizado = 0.0;
  bool _usarPersonalizado = false;
  bool _cargando = false;
  // ignore: unused_field
  String? _errorMessage;
  // ignore: unused_field
  String? _mensajeExito;

  final List<double> _montosRapidos = [10.0, 20.0, 50.0, 100.0];

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
  }

  void _inicializarServicios() {
    _storageService = widget.storageService ?? StorageService();
    _supabaseService = SupabaseService(_storageService);
  }

  double get _montoActual {
    if (_usarPersonalizado && _montoPersonalizado > 0) {
      return _montoPersonalizado;
    }
    return _montoSeleccionado;
  }

  double get _comision {
    return _montoActual * 0.03; // 3% comisión PayPal
  }

  double get _montoRecibido {
    return _montoActual - _comision;
  }

  Future<void> _actualizarPerfilYSaldo() async {
    try {
      final usuarioActualizado = await _supabaseService.obtenerPerfil();
      if (usuarioActualizado != null) {
        await _storageService.guardarUsuario(usuarioActualizado);
      }
    } catch (e) {
      print('Error actualizando perfil: $e');
    }
  }

  Future<void> _iniciarRecargaPayPal() async {
    if (_montoActual <= 0) {
      _mostrarError('Ingresa un monto válido');
      return;
    }

    if (_montoActual < 5) {
      _mostrarError('El monto mínimo de recarga es Bs. 5.00');
      return;
    }

    if (_montoActual > 500) {
      _mostrarError('El monto máximo de recarga es Bs. 500.00');
      return;
    }

    setState(() {
      _cargando = true;
      _errorMessage = null;
      _mensajeExito = null;
    });

    try {
      final resultado = await _supabaseService.crearRecargaPayPal(
        monto: _montoActual,
      );

      if (resultado['exito'] == true) {
        setState(() {
          _mensajeExito = 'Recarga iniciada. Serás redirigido a PayPal...';
          _cargando = false;
        });

        // Mostrar éxito
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Recarga de Bs. ${_montoActual.toStringAsFixed(2)} exitosa'),
            backgroundColor: NothingTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );

        // Esperar un momento y actualizar perfil
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          // Actualizar perfil para tener el nuevo saldo
          await _actualizarPerfilYSaldo();
          
          // Mostrar mensaje adicional
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Saldo actualizado correctamente'),
              backgroundColor: NothingTheme.success,
              duration: Duration(seconds: 2),
            ),
          );
          
          // Regresar a la pantalla anterior
          Navigator.of(context).pop();
        }
      } else {
        _mostrarError(resultado['mensaje'] ?? 'Error en la recarga');
      }
    } catch (e) {
      _mostrarError('Error de conexión: $e');
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(title: 'RECARGAR SALDO'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // Info de método de pago
            NothingCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NothingTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.paypal,
                      size: 28,
                      color: NothingTheme.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MÉTODO DE PAGO', style: NothingTheme.label),
                        const SizedBox(height: 4),
                        Text(
                          'Paga con PayPal de forma segura',
                          style: NothingTheme.body.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Seleccionar monto
            Text('SELECCIONAR MONTO', style: NothingTheme.label),
            const SizedBox(height: 12),

            // Botones de monto rápido
            Row(
              children: _montosRapidos.map((monto) {
                final isSelected = !_usarPersonalizado && _montoSeleccionado == monto;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _usarPersonalizado = false;
                        _montoSeleccionado = monto;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? NothingTheme.accentGreen : NothingTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? NothingTheme.accentGreen : NothingTheme.divider,
                          width: 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Bs. ${monto.toStringAsFixed(0)}',
                          style: NothingTheme.body.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? NothingTheme.background : NothingTheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Monto personalizado
            GestureDetector(
              onTap: () {
                setState(() {
                  _usarPersonalizado = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _usarPersonalizado ? NothingTheme.accentBlue.withOpacity(0.1) : NothingTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _usarPersonalizado ? NothingTheme.accentBlue : NothingTheme.divider,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 20,
                      color: _usarPersonalizado ? NothingTheme.accentBlue : NothingTheme.secondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _usarPersonalizado
                          ? TextField(
                              autofocus: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: NothingTheme.body,
                              decoration: InputDecoration(
                                hintText: 'Ingresa un monto personalizado',
                                hintStyle: NothingTheme.body.copyWith(color: NothingTheme.secondary),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (value) {
                                try {
                                  final monto = double.tryParse(value);
                                  if (monto != null && monto > 0) {
                                    setState(() => _montoPersonalizado = monto);
                                  }
                                } catch (e) {}
                              },
                            )
                          : Text(
                              'Monto personalizado',
                              style: NothingTheme.body.copyWith(color: NothingTheme.secondary),
                            ),
                    ),
                    if (_usarPersonalizado && _montoPersonalizado > 0)
                      Text(
                        'Bs. ${_montoPersonalizado.toStringAsFixed(2)}',
                        style: NothingTheme.body.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NothingTheme.accentBlue,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Resumen de recarga
            Text('RESUMEN DE RECARGA', style: NothingTheme.label),
            const SizedBox(height: 12),

            NothingCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResumenRow('Monto a recargar', FormateoHelper.formatearMoneda(_montoActual)),
                  const SizedBox(height: 8),
                  _buildResumenRow('Comisión PayPal (3%)', FormateoHelper.formatearMoneda(_comision), color: NothingTheme.accentOrange),
                  const Divider(color: NothingTheme.divider, height: 24),
                  _buildResumenRow(
                    'Saldo a recibir',
                    FormateoHelper.formatearMoneda(_montoRecibido),
                    color: NothingTheme.accentGreen,
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Botón de pago
            NothingButton(
              label: 'PAGAR CON PAYPAL',
              onTap: _iniciarRecargaPayPal,
              isLoading: _cargando,
              filled: true,
              icon: Icons.payment,
              color: NothingTheme.accentBlue,
            ),
            const SizedBox(height: 16),

            // Mensaje de seguridad
            NothingCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.security, size: 18, color: NothingTheme.accentGreen),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tus datos están protegidos. PayPal maneja tu información de pago de forma segura.',
                      style: NothingTheme.body.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenRow(String label, String value, {Color? color, bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: NothingTheme.body.copyWith(fontSize: 13)),
        Text(
          value,
          style: NothingTheme.body.copyWith(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? NothingTheme.primary,
          ),
        ),
      ],
    );
  }
}