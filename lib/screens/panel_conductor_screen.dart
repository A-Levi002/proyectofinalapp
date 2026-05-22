import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/nothing_theme.dart';

class PanelConductorScreen extends StatefulWidget {
  const PanelConductorScreen({super.key});

  @override
  State<PanelConductorScreen> createState() => _PanelConductorScreenState();
}

class _PanelConductorScreenState extends State<PanelConductorScreen> {
  late SupabaseService supabaseService;
  late StorageService storageService;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _cargando = true;
  Map<String, dynamic>? conductor;
  Map<String, dynamic>? contrato;
  Map<String, dynamic>? resumenGanancias;
  List<dynamic> pagos = [];
  String _filtroEstado = 'todos';

  // GPS
  bool _enServicio = false;
  bool _iniciandoServicio = false;
  StreamSubscription<Position>? _gpsSubscription;
  Position? _ultimaPosicion;
  Timer? _timerServicio;
  int _segundosEnServicio = 0;

  @override
  void initState() {
    super.initState();
    storageService = StorageService();
    supabaseService = SupabaseService(storageService);
    _cargarDatos();
  }

  @override
  void dispose() {
    _detenerServicio();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final conductorRes = await supabaseService.obtenerConductor();
      final contratoRes  = await supabaseService.obtenerContratoConductor();
      final gananciasRes = await supabaseService.obtenerResumenGanancias();
      final pagosRes     = await supabaseService.obtenerPagosConductor(
        filtroEstado: _filtroEstado == 'todos' ? null : _filtroEstado,
      );
      setState(() {
        if (conductorRes['exito'] == true) conductor = conductorRes['conductor'];
        if (contratoRes['exito'] == true) contrato = contratoRes['contrato'];
        resumenGanancias = gananciasRes;
        pagos = pagosRes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _toggleServicio() async {
    if (_enServicio) {
      await _detenerServicio();
    } else {
      await _iniciarServicio();
    }
  }

  Future<void> _iniciarServicio() async {
    setState(() => _iniciandoServicio = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _mostrarError('Activa el GPS de tu dispositivo.');
        setState(() => _iniciandoServicio = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _mostrarError('Se necesita permiso de ubicación.');
          setState(() => _iniciandoServicio = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _mostrarError('Permiso bloqueado. Ve a Configuración.');
        setState(() => _iniciandoServicio = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _publicarUbicacion(pos, enServicio: true);

      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((pos) {
        _ultimaPosicion = pos;
        _publicarUbicacion(pos, enServicio: true);
      });

      _timerServicio = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _segundosEnServicio++);
      });

      setState(() {
        _enServicio = true;
        _iniciandoServicio = false;
        _ultimaPosicion = pos;
        _segundosEnServicio = 0;
      });
    } catch (e) {
      _mostrarError('Error iniciando servicio: $e');
      setState(() => _iniciandoServicio = false);
    }
  }

  Future<void> _detenerServicio() async {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _timerServicio?.cancel();
    _timerServicio = null;

    if (conductor != null) {
      try {
        final conductorId = conductor!['id'] as String?;
        if (conductorId != null) {
          await _supabase.rpc('actualizar_ubicacion_conductor', params: {
            'p_conductor_id': conductorId,
            'p_latitud': _ultimaPosicion?.latitude ?? 0,
            'p_longitud': _ultimaPosicion?.longitude ?? 0,
            'p_velocidad': 0,
            'p_rumbo': 0,
            'p_en_servicio': false,
          });
        }
      } catch (e) {
        debugPrint('Error deteniendo servicio: $e');
      }
    }

    if (mounted) {
      setState(() {
        _enServicio = false;
        _segundosEnServicio = 0;
      });
    }
  }

  Future<void> _publicarUbicacion(Position pos, {required bool enServicio}) async {
    try {
      final conductorId = conductor?['id'] as String?;
      if (conductorId == null) return;
      await _supabase.rpc('actualizar_ubicacion_conductor', params: {
        'p_conductor_id': conductorId,
        'p_latitud': pos.latitude,
        'p_longitud': pos.longitude,
        'p_velocidad': pos.speed * 3.6,
        'p_rumbo': pos.heading,
        'p_precision': pos.accuracy,
        'p_en_servicio': enServicio,
      });
    } catch (e) {
      debugPrint('Error publicando ubicación: $e');
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: NothingTheme.error),
    );
  }

  String _formatearTiempoServicio() {
    final h = _segundosEnServicio ~/ 3600;
    final m = (_segundosEnServicio % 3600) ~/ 60;
    final s = _segundosEnServicio % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _aceptarContrato() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NothingTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Aceptar Contrato'),
        content: const Text('¿Estás de acuerdo con los términos y condiciones?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: NothingTheme.body),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _cargando = true);
              final resultado = await supabaseService.aceptarContratoAsIConductor();
              if (resultado['exito'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✓ Contrato aceptado'),
                      backgroundColor: NothingTheme.success),
                );
                _cargarDatos();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${resultado['mensaje']}'),
                      backgroundColor: NothingTheme.error),
                );
                setState(() => _cargando = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: NothingTheme.success),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _construirToggleServicio() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _enServicio
            ? NothingTheme.accentGreen.withOpacity(0.1)
            : NothingTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _enServicio ? NothingTheme.accentGreen : NothingTheme.divider,
          width: _enServicio ? 1 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: _enServicio
                      ? NothingTheme.accentGreen
                      : NothingTheme.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _enServicio ? 'EN SERVICIO' : 'FUERA DE SERVICIO',
                      style: NothingTheme.label.copyWith(
                        color: _enServicio
                            ? NothingTheme.accentGreen
                            : NothingTheme.secondary,
                      ),
                    ),
                    if (_enServicio) ...[
                      const SizedBox(height: 2),
                      Text('Tiempo: ${_formatearTiempoServicio()}',
                          style: NothingTheme.body.copyWith(fontSize: 11)),
                    ],
                  ],
                ),
              ),
              _iniciandoServicio
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: NothingTheme.accentGreen),
                    )
                  : GestureDetector(
                      onTap: _toggleServicio,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 52, height: 28,
                        decoration: BoxDecoration(
                          color: _enServicio
                              ? NothingTheme.accentGreen
                              : NothingTheme.divider,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 300),
                          alignment: _enServicio
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            width: 22, height: 22,
                            decoration: const BoxDecoration(
                              color: NothingTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
          if (_enServicio && _ultimaPosicion != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NothingTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 14, color: NothingTheme.accentGreen),
                  const SizedBox(width: 6),
                  Text(
                    '${_ultimaPosicion!.latitude.toStringAsFixed(5)}, '
                    '${_ultimaPosicion!.longitude.toStringAsFixed(5)}',
                    style: NothingTheme.body.copyWith(fontSize: 10),
                  ),
                  const Spacer(),
                  Text(
                    '${(_ultimaPosicion!.speed * 3.6).toStringAsFixed(0)} km/h',
                    style: NothingTheme.body.copyWith(
                        fontSize: 10, color: NothingTheme.accentBlue),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirCardResumen() {
    if (resumenGanancias == null) return const SizedBox.shrink();
    final totalGanancias  = double.tryParse(resumenGanancias!['total_ganancias'].toString()) ?? 0.0;
    final pagosPendientes = double.tryParse(resumenGanancias!['pagos_pendientes'].toString()) ?? 0.0;
    final pagosAbonados   = double.tryParse(resumenGanancias!['pagos_abonados'].toString()) ?? 0.0;
    final viajesHoy       = resumenGanancias!['viajes_hoy'] ?? 0;
    final totalRecaudado  = pagos.fold<double>(
        0.0, (s, p) => s + (double.tryParse(p['monto_bruto'].toString()) ?? 0.0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [NothingTheme.accentGreen, Color(0xFF2E7D32)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RESUMEN DE GANANCIAS', style: NothingTheme.label),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('Total', 'Bs ${totalGanancias.toStringAsFixed(2)}'),
            _stat('Recaudado', 'Bs ${totalRecaudado.toStringAsFixed(2)}'),
            _stat('Viajes Hoy', '$viajesHoy'),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('Pendiente', 'Bs ${pagosPendientes.toStringAsFixed(2)}'),
            _stat('Abonado', 'Bs ${pagosAbonados.toStringAsFixed(2)}'),
            _stat('Pagos', '${pagos.length}'),
          ]),
        ],
      ),
    );
  }

  Widget _stat(String label, String valor) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
    const SizedBox(height: 4),
    Text(valor, style: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
  ]);

  Widget _construirCardContrato() {
    if (contrato == null) {
      return Center(child: Text('Sin solicitud de contrato', style: NothingTheme.body));
    }
    final estado = contrato!['estado'] ?? 'pendiente';
    Color estadoColor;
    String estadoTexto;
    switch (estado) {
      case 'aceptado':  estadoColor = NothingTheme.success; estadoTexto = 'APROBADO'; break;
      case 'rechazado': estadoColor = NothingTheme.error;   estadoTexto = 'RECHAZADO'; break;
      default:          estadoColor = NothingTheme.warning; estadoTexto = 'PENDIENTE';
    }
    return NothingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ESTADO DEL CONTRATO', style: NothingTheme.label),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: estadoColor.withOpacity(0.1),
                  border: Border.all(color: estadoColor),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(estadoTexto, style: TextStyle(
                    color: estadoColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Empresa: ${contrato!['empresa'] ?? 'N/A'}', style: NothingTheme.body),
          Text('Comisión: ${contrato!['comision_porcentaje']}%', style: NothingTheme.body),
          if (contrato!['razon_rechazo'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NothingTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Razón del rechazo:',
                    style: NothingTheme.label.copyWith(color: NothingTheme.error)),
                const SizedBox(height: 4),
                Text(contrato!['razon_rechazo'],
                    style: NothingTheme.body.copyWith(fontSize: 12)),
              ]),
            ),
          ],
          if (estado == 'pendiente') ...[
            const SizedBox(height: 16),
            NothingButton(
              label: 'ACEPTAR CONTRATO',
              onTap: _aceptarContrato,
              filled: true,
              icon: Icons.check,
              color: NothingTheme.success,
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirListaPagos() {
    if (pagos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text('Sin registros de pagos', style: NothingTheme.body),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pagos.length,
      itemBuilder: (context, index) {
        final pago     = pagos[index];
        final comision = double.tryParse(pago['comision_conductor'].toString()) ?? 0.0;
        final estado   = pago['estado'] ?? 'pendiente';
        final fecha    = DateTime.parse(
            pago['fecha_pago'] ?? DateTime.now().toIso8601String());
        Color estadoColor;
        switch (estado) {
          case 'abonado':  estadoColor = NothingTheme.success; break;
          case 'retirado': estadoColor = NothingTheme.accentBlue; break;
          default:         estadoColor = NothingTheme.warning;
        }
        return NothingCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pasajero CI: ${pago['usuario_pasajero_ci']}',
                      style: NothingTheme.body),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                      style: NothingTheme.body.copyWith(fontSize: 11)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Bs ${comision.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: NothingTheme.accentGreen)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(0.1),
                    border: Border.all(color: estadoColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(estado.toUpperCase(),
                      style: TextStyle(fontSize: 10,
                          color: estadoColor, fontWeight: FontWeight.bold)),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _construirBotonFiltro(String label, String valor) {
    final isSelected = _filtroEstado == valor;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _filtroEstado = valor);
        _cargarDatos();
      },
      backgroundColor: NothingTheme.surface,
      selectedColor: NothingTheme.accentOrange,
      checkmarkColor: NothingTheme.background,
      labelStyle: TextStyle(
          color: isSelected ? NothingTheme.background : NothingTheme.primary),
      side: BorderSide(color: NothingTheme.divider, width: 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(
        title: 'PANEL CONDUCTOR',
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              color: NothingTheme.primary,
              backgroundColor: NothingTheme.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (conductor != null)
                      NothingCard(
                        child: Column(children: [
                          const Icon(Icons.directions_bus,
                              size: 48, color: NothingTheme.accentOrange),
                          const SizedBox(height: 8),
                          Text('${conductor!['nombre']} ${conductor!['apellido']}',
                              style: NothingTheme.title, textAlign: TextAlign.center),
                          Text(conductor!['empresa'] ?? 'Sin empresa',
                              style: NothingTheme.body),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: conductor!['estado'] == 'activo'
                                  ? NothingTheme.success.withOpacity(0.1)
                                  : NothingTheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: conductor!['estado'] == 'activo'
                                    ? NothingTheme.success
                                    : NothingTheme.error,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              conductor!['estado'] == 'activo'
                                  ? 'ACTIVO'
                                  : conductor!['estado'].toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: conductor!['estado'] == 'activo'
                                    ? NothingTheme.success
                                    : NothingTheme.error,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 20),

                    Text('SERVICIO EN RUTA', style: NothingTheme.label),
                    const SizedBox(height: 12),
                    _construirToggleServicio(),
                    const SizedBox(height: 20),

                    _construirCardResumen(),
                    const SizedBox(height: 20),

                    Text('CONTRATO', style: NothingTheme.label),
                    const SizedBox(height: 12),
                    _construirCardContrato(),
                    const SizedBox(height: 20),

                    Text('HISTORIAL DE PAGOS', style: NothingTheme.label),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _construirBotonFiltro('Todos', 'todos'),
                        const SizedBox(width: 8),
                        _construirBotonFiltro('Pendiente', 'pendiente'),
                        const SizedBox(width: 8),
                        _construirBotonFiltro('Abonado', 'abonado'),
                        const SizedBox(width: 8),
                        _construirBotonFiltro('Retirado', 'retirado'),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _construirListaPagos(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }
}
