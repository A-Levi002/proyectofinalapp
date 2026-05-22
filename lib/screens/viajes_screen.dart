import 'package:flutter/material.dart';
import '../theme/nothing_theme.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class ViajesScreen extends StatefulWidget {
  final StorageService? storageService;

  const ViajesScreen({this.storageService, super.key});

  @override
  State<ViajesScreen> createState() => _ViajesScreenState();
}

class _ViajesScreenState extends State<ViajesScreen> {
  late SupabaseService _supabaseService;
  late StorageService _storageService;

  List<Map<String, dynamic>> _viajes = [];
  bool _cargando = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
    _cargarViajes();
  }

  void _inicializarServicios() {
    _storageService = widget.storageService ?? StorageService();
    _supabaseService = SupabaseService(_storageService);
  }

  Future<void> _cargarViajes() async {
    try {
      setState(() {
        _cargando = true;
        _errorMessage = null;
      });

      final viajes = await _supabaseService.obtenerHistorialViajes();

      setState(() {
        _viajes = List<Map<String, dynamic>>.from(viajes);
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: $e';
        _cargando = false;
      });
    }
  }

  String _getTipoUsuarioText(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'estudiante':
        return '🎓 Estudiante';
      case 'adultomayor':
        return '👴 Adulto Mayor';
      case 'discapacidad':
        return '♿ Discapacidad';
      default:
        return '👤 General';
    }
  }

  Color _getEstadoColor(String? estado) {
    switch (estado?.toLowerCase()) {
      case 'validado':
        return NothingTheme.success;
      case 'pendiente':
        return NothingTheme.warning;
      case 'cancelado':
        return NothingTheme.error;
      case 'expirado':
        return NothingTheme.secondary;
      default:
        return NothingTheme.accentBlue;
    }
  }

  String _getEstadoTexto(String? estado) {
    switch (estado?.toLowerCase()) {
      case 'validado':
        return 'VALIDADO';
      case 'pendiente':
        return 'PENDIENTE';
      case 'cancelado':
        return 'CANCELADO';
      case 'expirado':
        return 'EXPIRADO';
      default:
        return estado?.toUpperCase() ?? 'DESCONOCIDO';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(
        title: 'MIS VIAJES',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _cargarViajes,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: NothingTheme.error),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: NothingTheme.body),
                      const SizedBox(height: 20),
                      NothingButton(
                        label: 'REINTENTAR',
                        onTap: _cargarViajes,
                        filled: false,
                      ),
                    ],
                  ),
                )
              : _viajes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: NothingTheme.secondary),
                          const SizedBox(height: 16),
                          Text(
                            'NO HAY VIAJES REGISTRADOS',
                            style: NothingTheme.label,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Realiza tu primer viaje generando un QR',
                            style: NothingTheme.body.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 24),
                          NothingButton(
                            label: 'GENERAR QR',
                            onTap: () => Navigator.of(context).pushNamed('/generar-qr'),
                            filled: true,
                            icon: Icons.qr_code,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarViajes,
                      color: NothingTheme.primary,
                      backgroundColor: NothingTheme.surface,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _viajes.length,
                        itemBuilder: (context, index) {
                          final viaje = _viajes[index];
                          return _buildViajeCard(viaje, index);
                        },
                      ),
                    ),
    );
  }

  Widget _buildViajeCard(Map<String, dynamic> viaje, int index) {
    // Manejo seguro de fechas
    DateTime? fecha;
    if (viaje['fecha_validacion'] != null) {
      fecha = DateTime.tryParse(viaje['fecha_validacion']);
    }
    if (fecha == null && viaje['fecha'] != null) {
      fecha = DateTime.tryParse(viaje['fecha']);
    }
    if (fecha == null && viaje['created_at'] != null) {
      fecha = DateTime.tryParse(viaje['created_at']);
    }
    if (fecha == null) {
      fecha = DateTime.now();
    }
    
    // Manejo seguro de números
    final montoFinal = (viaje['monto_final'] as num?)?.toDouble() ?? 0.0;
    final montoOriginal = (viaje['monto_original'] as num?)?.toDouble() ?? 
                          (viaje['tarifa_base'] as num?)?.toDouble() ?? 2.50;
    final descuento = (viaje['porcentaje_descuento'] as num?)?.toDouble() ?? 
                      (viaje['monto_descuento'] as num?)?.toDouble() ?? 0.0;
    
    final tipoUsuario = viaje['tipo_usuario_momento']?.toString() ?? 
                        viaje['tipo_usuario']?.toString() ?? 
                        viaje['tipoUsuario']?.toString() ?? 
                        'general';
    final estado = viaje['estado']?.toString() ?? 'validado';
    final origen = viaje['origen']?.toString() ?? 'No especificado';
    final destino = viaje['destino']?.toString() ?? 'No especificado';
    
    // ID seguro
    final idViaje = viaje['id']?.toString() ?? 'viaje_$index';
    final idCorto = idViaje.length > 8 ? idViaje.substring(0, 8) : idViaje;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: NothingCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con número de viaje y estado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: NothingTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: NothingTheme.divider, width: 0.5),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: NothingTheme.body.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTipoUsuarioText(tipoUsuario),
                          style: NothingTheme.label.copyWith(
                            color: NothingTheme.accentGreen,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'VIAJE #$idCorto',
                          style: NothingTheme.body.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getEstadoColor(estado).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getEstadoColor(estado), width: 0.5),
                  ),
                  child: Text(
                    _getEstadoTexto(estado),
                    style: NothingTheme.label.copyWith(
                      fontSize: 9,
                      color: _getEstadoColor(estado),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Ruta (Origen → Destino)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NothingTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ORIGEN', style: NothingTheme.label.copyWith(fontSize: 9)),
                        const SizedBox(height: 4),
                        Text(
                          origen,
                          style: NothingTheme.body.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 16, color: NothingTheme.secondary),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('DESTINO', style: NothingTheme.label.copyWith(fontSize: 9)),
                        const SizedBox(height: 4),
                        Text(
                          destino,
                          style: NothingTheme.body.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Detalles de tarifa
            Row(
              children: [
                Expanded(
                  child: _buildTarifaDetalle(
                    'TARIFA BASE',
                    FormateoHelper.formatearMoneda(montoOriginal),
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: NothingTheme.divider,
                ),
                Expanded(
                  child: _buildTarifaDetalle(
                    'DESCUENTO',
                    '${descuento.toStringAsFixed(0)}%',
                    color: NothingTheme.accentOrange,
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: NothingTheme.divider,
                ),
                Expanded(
                  child: _buildTarifaDetalle(
                    'TOTAL',
                    FormateoHelper.formatearMoneda(montoFinal),
                    color: NothingTheme.accentGreen,
                    bold: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fecha
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: NothingTheme.secondary),
                const SizedBox(width: 6),
                Text(
                  FormateoHelper.formatearFechaHora(fecha),
                  style: NothingTheme.body.copyWith(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarifaDetalle(String label, String value, {Color? color, bool bold = false}) {
    return Column(
      children: [
        Text(label, style: NothingTheme.label.copyWith(fontSize: 9)),
        const SizedBox(height: 4),
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