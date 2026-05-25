import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class ValidadorScreen extends StatefulWidget {
  const ValidadorScreen({super.key});

  @override
  State<ValidadorScreen> createState() => _ValidadorScreenState();
}

class _ValidadorScreenState extends State<ValidadorScreen> {
  late MobileScannerController _scannerController;
  late SupabaseService _supabaseService;
  late StorageService _storageService;

  bool _procesando = false;
  String? _ultimoResultado;
  String? _ultimoMensaje;
  DateTime? _ultimaValidacion;
  int _contadorValidaciones = 0;
  bool _tienePermiso = false;
  double _ultimoMonto = 0;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      autoStart: true,
      torchEnabled: false,
      facing: CameraFacing.back,
    );
    _inicializarServicios();
    _verificarPermiso();
  }

  void _inicializarServicios() {
    _storageService = StorageService();
    _supabaseService = SupabaseService(_storageService);
  }

  Future<void> _verificarPermiso() async {
    // En producción, verificar que sea conductor/validador
    // Por ahora, simulamos que tiene permiso
    setState(() => _tienePermiso = true);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _procesarQR(String qrData) async {
    if (_procesando) return;

    setState(() {
      _procesando = true;
      _ultimoResultado = null;
      _ultimoMensaje = null;
    });

    try {
      final resultado = await _supabaseService.validarQRViaje(qrData);

      if (resultado['exito'] == true) {
        setState(() {
          _ultimoResultado = 'VALIDADO';
          _ultimoMensaje = '✓ Viaje validado correctamente';
          _ultimaValidacion = DateTime.now();
          _contadorValidaciones++;
          _ultimoMonto = resultado['tarifaAplicada'] ?? 0;
        });

        _mostrarDialogoExito(resultado);
      } else {
        setState(() {
          _ultimoResultado = 'RECHAZADO';
          _ultimoMensaje = resultado['mensaje'] ?? 'QR inválido';
          _ultimaValidacion = DateTime.now();
        });

        _mostrarDialogoError(resultado['mensaje'] ?? 'QR inválido');
      }
    } catch (e) {
      setState(() {
        _ultimoResultado = 'ERROR';
        _ultimoMensaje = 'Error de conexión';
        _ultimaValidacion = DateTime.now();
      });
      _mostrarDialogoError('Error de conexión: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() => _procesando = false);
        }
      });
    }
  }

  void _mostrarDialogoExito(Map<String, dynamic> resultado) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NothingTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NothingTheme.success, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: NothingTheme.success, size: 28),
            SizedBox(width: 12),
            Text('VIAJE VALIDADO'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogInfoRow('Pasajero', resultado['usuarioNombre'] ?? 'N/A'),
            const SizedBox(height: 8),
            _buildDialogInfoRow('Tipo', resultado['tipoUsuario'] ?? 'N/A'),
            const SizedBox(height: 8),
            _buildDialogInfoRow(
              'Tarifa',
              FormateoHelper.formatearMoneda(resultado['tarifaAplicada'] ?? 0),
              highlight: true,
            ),
            const SizedBox(height: 8),
            _buildDialogInfoRow(
              'Saldo restante',
              FormateoHelper.formatearMoneda(resultado['saldoRestante'] ?? 0),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: NothingTheme.body.copyWith(color: NothingTheme.success)),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoError(String mensaje) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NothingTheme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NothingTheme.error, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: NothingTheme.error, size: 28),
            SizedBox(width: 12),
            Text('VALIDACIÓN RECHAZADA'),
          ],
        ),
        content: Text(mensaje, style: NothingTheme.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: NothingTheme.body.copyWith(color: NothingTheme.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogInfoRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: NothingTheme.body.copyWith(fontSize: 13)),
        Text(
          value,
          style: NothingTheme.body.copyWith(
            fontSize: 13,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            color: highlight ? NothingTheme.success : NothingTheme.primary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_tienePermiso) {
      return Scaffold(
        backgroundColor: NothingTheme.background,
        appBar: const NothingAppBar(title: 'VALIDADOR QR'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: NothingTheme.error),
              const SizedBox(height: 16),
              const Text('NO TIENES PERMISOS DE VALIDADOR', style: NothingTheme.label),
              const SizedBox(height: 8),
              Text(
                'Solo los conductores pueden validar viajes',
                style: NothingTheme.body.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 24),
              NothingButton(
                label: 'VOLVER',
                onTap: () => Navigator.pop(context),
                filled: false,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(
        title: 'VALIDADOR QR',
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, size: 20),
            onPressed: () => _scannerController.toggleTorch(),
            tooltip: 'Encender linterna',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android, size: 20),
            onPressed: () => _scannerController.switchCamera(),
            tooltip: 'Cambiar cámara',
          ),
        ],
      ),
      body: Column(
        children: [
          // Panel de estadísticas
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: NothingTheme.surface,
              border: Border(bottom: BorderSide(color: NothingTheme.divider, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'VALIDACIONES HOY',
                  _contadorValidaciones.toString(),
                  NothingTheme.accentGreen,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: NothingTheme.divider,
                ),
                _buildStatItem(
                  'ÚLTIMA',
                  _ultimaValidacion != null
                      ? '${_ultimaValidacion!.hour.toString().padLeft(2, '0')}:${_ultimaValidacion!.minute.toString().padLeft(2, '0')}:${_ultimaValidacion!.second.toString().padLeft(2, '0')}'
                      : '--:--:--',
                  NothingTheme.secondary,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: NothingTheme.divider,
                ),
                _buildStatItem(
                  'ÚLTIMO MONTO',
                  _ultimoMonto > 0
                      ? 'Bs. ${_ultimoMonto.toStringAsFixed(2)}'
                      : '--',
                  NothingTheme.accentOrange,
                ),
              ],
            ),
          ),

          // Scanner
          Expanded(
            child: _procesando
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        if (_ultimoResultado != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: _ultimoResultado == 'VALIDADO'
                                  ? NothingTheme.success.withOpacity(0.1)
                                  : NothingTheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: _ultimoResultado == 'VALIDADO'
                                    ? NothingTheme.success
                                    : NothingTheme.error,
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _ultimoResultado == 'VALIDADO'
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  size: 48,
                                  color: _ultimoResultado == 'VALIDADO'
                                      ? NothingTheme.success
                                      : NothingTheme.error,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _ultimoResultado!,
                                  style: NothingTheme.title.copyWith(
                                    fontSize: 18,
                                    color: _ultimoResultado == 'VALIDADO'
                                        ? NothingTheme.success
                                        : NothingTheme.error,
                                  ),
                                ),
                                if (_ultimoMensaje != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _ultimoMensaje!,
                                    style: NothingTheme.body.copyWith(fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      if (_procesando) return;
                      final barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final rawValue = barcode.rawValue;
                        if (rawValue != null && rawValue.isNotEmpty) {
                          _procesarQR(rawValue);
                          break;
                        }
                      }
                    },
                    errorBuilder: (context, error, child) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt, size: 64, color: NothingTheme.secondary),
                            const SizedBox(height: 16),
                            const Text('Error al acceder a la cámara', style: NothingTheme.body),
                            const SizedBox(height: 16),
                            NothingButton(
                              label: 'REINTENTAR',
                              onTap: () {
                                _scannerController.start();
                                setState(() {});
                              },
                              filled: false,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Instrucciones
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: NothingTheme.surface,
              border: Border(top: BorderSide(color: NothingTheme.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner, size: 20, color: NothingTheme.accentBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Apunta la cámara al código QR del pasajero. La validación es automática.',
                    style: NothingTheme.body.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: NothingTheme.label.copyWith(fontSize: 9)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}