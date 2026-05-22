import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';

class TrufisScreen extends StatefulWidget {
  final StorageService? storageService;
  const TrufisScreen({this.storageService, super.key});

  @override
  State<TrufisScreen> createState() => _TrufisScreenState();
}

class _TrufisScreenState extends State<TrufisScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  GoogleMapController? _mapController;
  Position? _miPosicion;
  final Map<String, Marker> _marcadores = {};
  final Map<String, Map<String, dynamic>> _trufisData = {};
  Map<String, dynamic>? _trufiSeleccionado;

  StreamSubscription? _realtimeSub;
  bool _cargando = true;
  String? _error;

  static const LatLng _cochabamba = LatLng(-17.3935, -66.1570);

  // Colores de rutas
  static const Map<String, Color> _coloresRuta = {
    '101': Color(0xFFE53E3E),
    '202': Color(0xFF2B6CB0),
    '103': Color(0xFF276749),
    '305': Color(0xFFB7791F),
    '107': Color(0xFF553C9A),
  };

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    await _obtenerMiUbicacion();
    await _cargarTrufisIniciales();
    _suscribirRealtime();
  }

  Future<void> _obtenerMiUbicacion() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _miPosicion = pos);
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
    }
  }

  Future<void> _cargarTrufisIniciales() async {
    try {
      setState(() { _cargando = true; _error = null; });

      final response = await _supabase
          .from('conductor_ubicaciones')
          .select('''
            conductor_id, latitud, longitud, velocidad, rumbo, en_servicio, updated_at,
            conductores(id, nombre, apellido, numero_bus, empresa, estado,
              rutas_trufis(codigo, nombre, color_hex))
          ''')
          .eq('en_servicio', true)
          .gte('updated_at',
              DateTime.now().subtract(const Duration(seconds: 60)).toIso8601String());

      for (final item in response) {
        _procesarUbicacion(item);
      }

      setState(() => _cargando = false);
    } catch (e) {
      setState(() {
        _error = 'Error cargando trufis: $e';
        _cargando = false;
      });
    }
  }

  void _suscribirRealtime() {
    _realtimeSub = _supabase
        .from('conductor_ubicaciones')
        .stream(primaryKey: ['id'])
        .listen((data) {
      for (final item in data) {
        if (item['en_servicio'] == true) {
          _actualizarMarcadorDesdeStream(item);
        } else {
          _eliminarMarcador(item['conductor_id']);
        }
      }
    });
  }

  void _procesarUbicacion(Map<String, dynamic> item) {
    final conductorId = item['conductor_id'] as String?;
    if (conductorId == null) return;

    final conductor = item['conductores'] as Map<String, dynamic>?;
    if (conductor == null) return;
    if (conductor['estado'] != 'activo') return;

    final lat = double.tryParse(item['latitud'].toString()) ?? 0;
    final lng = double.tryParse(item['longitud'].toString()) ?? 0;
    final velocidad = double.tryParse(item['velocidad'].toString()) ?? 0;

    final ruta = conductor['rutas_trufis'] as Map<String, dynamic>?;
    final rutaCodigo = ruta?['codigo'] as String? ?? '?';
    final rutaNombre = ruta?['nombre'] as String? ?? 'Sin ruta';
    final colorHex = ruta?['color_hex'] as String? ?? '#6B46C1';

    final Color color = _coloresRuta[rutaCodigo] ??
        Color(int.parse(colorHex.replaceFirst('#', '0xFF')));

    final hue = _colorToHue(color);

    final data = {
      'conductor_id': conductorId,
      'nombre': '${conductor['nombre']} ${conductor['apellido']}',
      'numero_bus': conductor['numero_bus'] ?? 'S/N',
      'empresa': conductor['empresa'] ?? '',
      'ruta_codigo': rutaCodigo,
      'ruta_nombre': rutaNombre,
      'velocidad': velocidad,
      'latitud': lat,
      'longitud': lng,
      'color': color,
      'updated_at': item['updated_at'],
    };

    _trufisData[conductorId] = data;

    final marker = Marker(
      markerId: MarkerId(conductorId),
      position: LatLng(lat, lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(
        title: 'Línea $rutaCodigo',
        snippet: 'Bus ${conductor['numero_bus'] ?? 'S/N'} · ${velocidad.toStringAsFixed(0)} km/h',
      ),
      onTap: () => _mostrarDetalleTrufi(conductorId),
    );

    if (mounted) {
      setState(() => _marcadores[conductorId] = marker);
    }
  }

  Future<void> _actualizarMarcadorDesdeStream(Map<String, dynamic> item) async {
    final conductorId = item['conductor_id'] as String?;
    if (conductorId == null) return;

    // Si no tenemos data del conductor, buscarla
    if (!_trufisData.containsKey(conductorId)) {
      await _cargarTrufisIniciales();
      return;
    }

    final existing = _trufisData[conductorId]!;
    final lat = double.tryParse(item['latitud'].toString()) ?? 0;
    final lng = double.tryParse(item['longitud'].toString()) ?? 0;
    final velocidad = double.tryParse(item['velocidad'].toString()) ?? 0;

    existing['latitud'] = lat;
    existing['longitud'] = lng;
    existing['velocidad'] = velocidad;

    final hue = _colorToHue(existing['color'] as Color);

    final marker = Marker(
      markerId: MarkerId(conductorId),
      position: LatLng(lat, lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(
        title: 'Línea ${existing['ruta_codigo']}',
        snippet: 'Bus ${existing['numero_bus']} · ${velocidad.toStringAsFixed(0)} km/h',
      ),
      onTap: () => _mostrarDetalleTrufi(conductorId),
    );

    if (mounted) {
      setState(() {
        _trufisData[conductorId] = existing;
        _marcadores[conductorId] = marker;
      });
    }
  }

  void _eliminarMarcador(String? conductorId) {
    if (conductorId == null) return;
    if (mounted) {
      setState(() {
        _marcadores.remove(conductorId);
        _trufisData.remove(conductorId);
      });
    }
  }

  double _colorToHue(Color color) {
    final r = color.red / 255;
    final g = color.green / 255;
    final b = color.blue / 255;
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    if (max == min) return 0;
    final d = max - min;
    double h;
    if (max == r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (max == g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    return (h / 6 * 360).clamp(0, 360);
  }

  void _mostrarDetalleTrufi(String conductorId) {
    final data = _trufisData[conductorId];
    if (data == null) return;

    setState(() => _trufiSeleccionado = data);

    // Animar cámara al trufi
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(data['latitud'], data['longitud']),
        16,
      ),
    );
  }

  String _calcularTiempoEstimado(Map<String, dynamic> data) {
    if (_miPosicion == null) return '-- min';
    final dist = Geolocator.distanceBetween(
      _miPosicion!.latitude,
      _miPosicion!.longitude,
      data['latitud'],
      data['longitud'],
    ) / 1000;
    final vel = (data['velocidad'] as double?) ?? 0;
    if (vel < 1) return '~${(dist * 4).toInt()} min';
    final mins = (dist / vel * 60).ceil();
    return '$mins min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      body: Stack(
        children: [
          // Mapa
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _miPosicion != null
                  ? LatLng(_miPosicion!.latitude, _miPosicion!.longitude)
                  : _cochabamba,
              zoom: 14,
            ),
            markers: Set<Marker>.of(_marcadores.values),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              // Tema oscuro para el mapa
              controller.setMapStyle(_mapStyleDark);
            },
            onTap: (_) => setState(() => _trufiSeleccionado = null),
          ),

          // AppBar superior
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NothingTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NothingTheme.divider, width: 0.5),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 16, color: NothingTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: NothingTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NothingTheme.divider, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_bus,
                              size: 16, color: NothingTheme.accentGreen),
                          const SizedBox(width: 8),
                          Text(
                            'TRUFIS EN TIEMPO REAL',
                            style: NothingTheme.label,
                          ),
                          const Spacer(),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: NothingTheme.accentGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_marcadores.length}',
                            style: NothingTheme.label.copyWith(
                              color: NothingTheme.accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      if (_miPosicion != null) {
                        _mapController?.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            LatLng(_miPosicion!.latitude, _miPosicion!.longitude),
                            15,
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NothingTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NothingTheme.divider, width: 0.5),
                      ),
                      child: const Icon(Icons.my_location,
                          size: 16, color: NothingTheme.accentBlue),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading
          if (_cargando)
            const Center(child: CircularProgressIndicator()),

          // Error
          if (_error != null)
            Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NothingTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: NothingTheme.error, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, style: NothingTheme.body, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    NothingButton(
                      label: 'REINTENTAR',
                      onTap: _cargarTrufisIniciales,
                      filled: false,
                    ),
                  ],
                ),
              ),
            ),

          // Sin trufis
          if (!_cargando && _error == null && _marcadores.isEmpty)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: NothingTheme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: NothingTheme.divider, width: 0.5),
                  ),
                  child: Text(
                    'No hay trufis activos cerca',
                    style: NothingTheme.body,
                  ),
                ),
              ),
            ),

          // Bottom sheet con detalle del trufi seleccionado
          if (_trufiSeleccionado != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildDetalleTrufi(_trufiSeleccionado!),
            ),

          // Botón refrescar
          Positioned(
            bottom: _trufiSeleccionado != null ? 220 : 24,
            right: 16,
            child: GestureDetector(
              onTap: _cargarTrufisIniciales,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NothingTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NothingTheme.divider, width: 0.5),
                ),
                child: const Icon(Icons.refresh,
                    size: 20, color: NothingTheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleTrufi(Map<String, dynamic> data) {
    final color = data['color'] as Color? ?? NothingTheme.accentGreen;
    final tiempoEst = _calcularTiempoEstimado(data);

    return Container(
      decoration: BoxDecoration(
        color: NothingTheme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NothingTheme.divider, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: NothingTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Línea y bus
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 1),
                ),
                child: Center(
                  child: Text(
                    data['ruta_codigo'] as String,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['ruta_nombre'] as String,
                      style: NothingTheme.title.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bus ${data['numero_bus']} · ${data['empresa']}',
                      style: NothingTheme.body,
                    ),
                  ],
                ),
              ),
              // Estado activo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: NothingTheme.accentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: NothingTheme.accentGreen, width: 0.5),
                ),
                child: Text(
                  'ACTIVO',
                  style: NothingTheme.label.copyWith(
                    color: NothingTheme.accentGreen,
                    fontSize: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats
          Row(
            children: [
              _buildStat(
                Icons.speed,
                '${(data['velocidad'] as double).toStringAsFixed(0)} km/h',
                'VELOCIDAD',
                NothingTheme.accentBlue,
              ),
              _buildDivider(),
              _buildStat(
                Icons.access_time,
                tiempoEst,
                'TIEMPO EST.',
                NothingTheme.accentOrange,
              ),
              _buildDivider(),
              _buildStat(
                Icons.attach_money,
                'Bs 2.50',
                'TARIFA',
                NothingTheme.accentGreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String valor, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            valor,
            style: NothingTheme.title.copyWith(fontSize: 14, color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: NothingTheme.label.copyWith(fontSize: 8)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1, height: 40,
      color: NothingTheme.divider,
    );
  }
}

// Estilo oscuro para Google Maps
const String _mapStyleDark = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0a0a0a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0a0a0a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#222222"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1f1f1f"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050505"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#0f0f0f"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#111111"}]}
]
''';
