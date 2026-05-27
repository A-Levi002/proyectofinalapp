import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/nothing_theme.dart';

class PanelConductorScreen extends StatefulWidget {
  const PanelConductorScreen({super.key});
  @override
  State<PanelConductorScreen> createState() => _PanelConductorScreenState();
}

class _PanelConductorScreenState extends State<PanelConductorScreen>
    with SingleTickerProviderStateMixin {
  late SupabaseService supabaseService;
  late StorageService  storageService;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Tabs
  late TabController _tabCtrl;
  final List<String> _tabs = ['INICIO', 'MAPA', 'QR', 'RUTA', 'PAGOS'];

  bool _cargando = true;
  Map<String, dynamic>? conductor;
  Map<String, dynamic>? contrato;
  Map<String, dynamic>? resumenGanancias;
  Map<String, dynamic>? rutaAsignada;
  List<dynamic> pagos = [];
  String _filtroEstado = 'todos';

  // ── GPS / Servicio ──
  bool _enServicio     = false;
  bool _iniciandoServ  = false;
  StreamSubscription<Position>? _gpsSub;
  Position? _ultimaPos;
  Timer? _timerServicio;
  int   _segundos = 0;

  // ── Mapa ──
  GoogleMapController? _mapCtrl;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // ── QR Scanner ──
  bool _escaneando      = false;
  bool _procesandoQR    = false;
  String? _resultadoQR;
  MobileScannerController? _qrCtrl;

  // ── Resumen del día ──
  int    _viajesHoy     = 0;
  double _gananciaHoy   = 0.0;
  double _kmHoy         = 0.0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    storageService  = StorageService();
    supabaseService = SupabaseService(storageService);
    themeNotifier.addListener(_rebuild);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _detenerServicio();
    _qrCtrl?.dispose();
    _mapCtrl?.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // ────────────────────────────────────────────
  //  Carga de datos
  // ────────────────────────────────────────────
  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final cRes  = await supabaseService.obtenerConductor();
      final tRes  = await supabaseService.obtenerContratoConductor();
      final gRes  = await supabaseService.obtenerResumenGanancias();
      final pRes  = await supabaseService.obtenerPagosConductor(
          filtroEstado: _filtroEstado == 'todos' ? null : _filtroEstado);

      if (cRes['exito'] == true) conductor = cRes['conductor'];
      if (tRes['exito'] == true) contrato  = tRes['contrato'];
      resumenGanancias = gRes;
      pagos = pRes;

      // Cargar ruta asignada
      if (conductor?['ruta_id'] != null) {
        final r = await _supabase.from('rutas_trufis')
            .select()
            .eq('id', conductor!['ruta_id'])
            .maybeSingle();
        rutaAsignada = r;
        if (r != null) _buildRoutePolyline(r);
      }

      _viajesHoy   = gRes['viajes_hoy']     ?? 0;
      _gananciaHoy = double.tryParse(gRes['total_ganancias']?.toString() ?? '0') ?? 0.0;
    } catch (e) {
      debugPrint('Error cargarDatos: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _buildRoutePolyline(Map<String, dynamic> ruta) {
    final paradas = ruta['paradas'];
    if (paradas == null) return;
    try {
      final List pts = paradas is List ? paradas : [];
      final points = pts.map<LatLng>((p) =>
          LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
      if (points.length < 2) return;
      setState(() {
        _polylines.add(Polyline(
          polylineId: const PolylineId('ruta'),
          points: points,
          color: NothingTheme.accentOrange,
          width: 4,
        ));
        _markers.add(Marker(
          markerId: const MarkerId('origen'),
          position: points.first,
          infoWindow: InfoWindow(title: 'Origen: ${ruta['origen']}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ));
        _markers.add(Marker(
          markerId: const MarkerId('destino'),
          position: points.last,
          infoWindow: InfoWindow(title: 'Destino: ${ruta['destino']}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
      });
    } catch (e) {
      debugPrint('Error buildRoutePolyline: $e');
    }
  }

  // ────────────────────────────────────────────
  //  GPS / Servicio
  // ────────────────────────────────────────────
  Future<void> _toggleServicio() async {
    _enServicio ? await _detenerServicio() : await _iniciarServicio();
  }

  Future<void> _iniciarServicio() async {
    setState(() => _iniciandoServ = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Activa el GPS de tu dispositivo', error: true); return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          _snack('Se necesita permiso de ubicación', error: true); return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        _snack('Permiso bloqueado. Ve a Configuración.', error: true); return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _publicarUbicacion(pos, enServicio: true);

      // Mover cámara del mapa
      if (mounted && _mapCtrl != null) {
        try {
          _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(
              LatLng(pos.latitude, pos.longitude), 15));
        } catch (_) {}
      }

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((p) {
        _ultimaPos = p;
        _kmHoy += Geolocator.distanceBetween(
            _ultimaPos?.latitude ?? p.latitude,
            _ultimaPos?.longitude ?? p.longitude,
            p.latitude, p.longitude) / 1000;
        _publicarUbicacion(p, enServicio: true);
        _actualizarMarkerConductor(p);
        if (mounted) setState(() {});
      });

      _timerServicio = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _segundos++);
      });

      setState(() {
        _enServicio = true; _iniciandoServ = false;
        _ultimaPos = pos; _segundos = 0;
      });
    } catch (e) {
      _snack('Error iniciando servicio: $e', error: true);
      setState(() => _iniciandoServ = false);
    }
  }

  Future<void> _detenerServicio() async {
    _gpsSub?.cancel(); _gpsSub = null;
    _timerServicio?.cancel(); _timerServicio = null;
    if (conductor != null && _ultimaPos != null) {
      await supabaseService.actualizarUbicacionConductor(
        conductorId: conductor!['id'],
        latitud: _ultimaPos!.latitude,
        longitud: _ultimaPos!.longitude,
        velocidad: 0, rumbo: 0, enServicio: false,
      );
    }
    if (mounted) setState(() { _enServicio = false; _segundos = 0; });
  }

  Future<void> _publicarUbicacion(Position pos, {required bool enServicio}) async {
    final id = conductor?['id'] as String?;
    if (id == null) return;
    await supabaseService.actualizarUbicacionConductor(
      conductorId: id,
      latitud: pos.latitude,
      longitud: pos.longitude,
      velocidad: pos.speed * 3.6,
      rumbo: pos.heading,
      precision: pos.accuracy,
      enServicio: enServicio,
    );
  }

  void _actualizarMarkerConductor(Position pos) {
    _markers.removeWhere((m) => m.markerId.value == 'conductor');
    _markers.add(Marker(
      markerId: const MarkerId('conductor'),
      position: LatLng(pos.latitude, pos.longitude),
      infoWindow: const InfoWindow(title: 'Mi posición'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ));
    if (mounted && _mapCtrl != null) {
      try {
        _mapCtrl!.animateCamera(CameraUpdate.newLatLng(
            LatLng(pos.latitude, pos.longitude)));
      } catch (_) {}
    }
  }

  // ────────────────────────────────────────────
  //  QR Scanner
  // ────────────────────────────────────────────
  void _abrirScanner() {
    _qrCtrl = MobileScannerController();
    setState(() { _escaneando = true; _resultadoQR = null; });
  }

  void _cerrarScanner() {
    _qrCtrl?.dispose(); _qrCtrl = null;
    setState(() { _escaneando = false; _procesandoQR = false; });
  }

  Future<void> _procesarQR(String token) async {
    if (_procesandoQR) return;
    setState(() { _procesandoQR = true; });
    _qrCtrl?.stop();

    try {
      // Buscar el QR dinámico en la BD
      final qr = await _supabase.from('qr_viaje_dinamico')
          .select()
          .eq('token_qr', token)
          .maybeSingle();

      if (qr == null) {
        _mostrarResultadoQR(false, 'QR no encontrado o inválido');
        return;
      }
      if (qr['usado'] == true) {
        _mostrarResultadoQR(false, 'Este QR ya fue utilizado');
        return;
      }
      final expira = DateTime.parse(qr['expira_en']);
      if (expira.isBefore(DateTime.now())) {
        _mostrarResultadoQR(false, 'QR expirado');
        return;
      }

      final usuarioCi  = qr['usuario_ci'] as String;
      final monto      = double.tryParse(qr['monto_a_descontar'].toString()) ?? 0.0;
      final perfil     = qr['perfil_aplicado'] as String? ?? 'general';
      final cantidad   = qr['cantidad_personas'] as int? ?? 1;

      // Marcar QR como usado
      await _supabase.from('qr_viaje_dinamico').update({
        'usado': true,
        'escaneado_en': DateTime.now().toIso8601String(),
        'dispositivo_validador': conductor?['ci'] ?? '',
      }).eq('token_qr', token);

      // Crear registro de viaje
      final viaje = await _supabase.from('viajes').insert({
        'usuario_ci':    usuarioCi,
        'monto_original': 2.50 * cantidad,
        'monto_descuento': (2.50 - monto) * cantidad,
        'monto_final':   monto * cantidad,
        'tipo_usuario':  perfil,
        'qr_generado':   token,
        'qr_escaneado':  true,
        'fecha_validacion': DateTime.now().toIso8601String(),
        'estado':        'validado',
        'cantidad_personas': cantidad,
      }).select('id').single();

      final viajeId = viaje['id'] as String;

      // Descontar saldo del pasajero
      await supabaseService.descontarSaldoUsuario(ci: usuarioCi, monto: monto * cantidad);

      // Registrar comisión del conductor
      final comisionPorc = double.tryParse(
          contrato?['comision_porcentaje']?.toString() ?? '10') ?? 10.0;
      final montoTotal   = monto * cantidad;
      final comisionCond = montoTotal * (comisionPorc / 100);
      final comisionEmp  = montoTotal - comisionCond;

      await _supabase.from('pagos_conductores').insert({
        'conductor_id':       conductor!['id'],
        'usuario_pasajero_ci': usuarioCi,
        'viaje_id':           viajeId,
        'monto_bruto':        montoTotal,
        'comision_conductor': comisionCond,
        'comision_empresa':   comisionEmp,
        'estado':             'pendiente',
      });

      // Actualizar saldo de comisiones del conductor
      final saldoActual = double.tryParse(
          conductor!['saldo_comisiones']?.toString() ?? '0') ?? 0.0;
      await _supabase.from('conductores').update({
        'saldo_comisiones': saldoActual + comisionCond,
      }).eq('id', conductor!['id']);

      setState(() {
        _viajesHoy++;
        _gananciaHoy += comisionCond;
        conductor!['saldo_comisiones'] = saldoActual + comisionCond;
      });

      _mostrarResultadoQR(true,
          'Viaje validado\n'
          'Pasajero CI: $usuarioCi\n'
          'Personas: $cantidad\n'
          'Monto: Bs ${montoTotal.toStringAsFixed(2)}\n'
          'Tu comisión: Bs ${comisionCond.toStringAsFixed(2)}');
    } catch (e) {
      _mostrarResultadoQR(false, 'Error: $e');
    }
  }

  void _mostrarResultadoQR(bool exito, String mensaje) {
    _qrCtrl?.dispose(); _qrCtrl = null;
    setState(() {
      _escaneando   = false;
      _procesandoQR = false;
      _resultadoQR  = mensaje;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: NothingTheme.surf(themeNotifier.isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(exito ? Icons.check_circle : Icons.cancel,
              color: exito ? NothingTheme.accentGreen : NothingTheme.error, size: 24),
          const SizedBox(width: 10),
          Text(exito ? 'VALIDADO' : 'ERROR', style: TextStyle(
              fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: exito ? NothingTheme.accentGreen : NothingTheme.error)),
        ]),
        content: Text(mensaje, style: TextStyle(fontFamily: 'monospace', fontSize: 11,
            color: NothingTheme.prim(themeNotifier.isDark))),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); setState(() => _resultadoQR = null); },
            child: const Text('CERRAR'),
          ),
          if (exito)
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _abrirScanner(); },
              style: ElevatedButton.styleFrom(backgroundColor: NothingTheme.accentGreen),
              child: const Text('ESCANEAR OTRO', style: TextStyle(color: Colors.black)),
            ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────
  //  Helpers
  // ────────────────────────────────────────────
  Future<void> _aceptarContrato() async {
    final dark = themeNotifier.isDark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NothingTheme.surf(dark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('ACEPTAR CONTRATO'),
        content: const Text('¿Estás de acuerdo con los términos y condiciones?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: NothingTheme.accentGreen),
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await supabaseService.aceptarContratoAsIConductor();
    if (r['exito'] == true) {
      _snack('✓ Contrato aceptado');
      _cargarDatos();
    } else {
      _snack(r['mensaje'] ?? 'Error', error: true);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      backgroundColor: error ? NothingTheme.error : NothingTheme.accentGreen,
      duration: const Duration(seconds: 3),
    ));
  }

  String _tiempoServicio() {
    final h = _segundos ~/ 3600;
    final m = (_segundos % 3600) ~/ 60;
    final s = _segundos % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);

    return Scaffold(
      backgroundColor: bg,
      appBar: NothingAppBar(
        title: 'PANEL CONDUCTOR',
        actions: [
          IconButton(icon: const Icon(Icons.person_outline, size: 20),
              onPressed: () => Navigator.pushNamed(context, '/perfil-conductor')),
          IconButton(icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () => Navigator.pushNamed(context, '/ajustes-conductor')),
          IconButton(icon: const Icon(Icons.refresh, size: 20),
              onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: NothingTheme.accentOrange))
          : Column(children: [

              // ── Tab Bar ──
              Container(
                color: bg,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: prim,
                  unselectedLabelColor: sec,
                  indicatorColor: NothingTheme.accentOrange,
                  indicatorWeight: 0.5,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  dividerColor: div,
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildTabInicio(dark, bg, prim, sec, div),
                    _buildTabMapa(dark, bg, prim, sec, div),
                    _buildTabQR(dark, bg, prim, sec, div),
                    _buildTabRuta(dark, bg, prim, sec, div),
                    _buildTabPagos(dark, bg, prim, sec, div),
                  ],
                ),
              ),
            ]),
    );
  }

  // ─────────────────────────────────────────────
  //  TAB 1 — INICIO
  // ─────────────────────────────────────────────
  Widget _buildTabInicio(bool dark, Color bg, Color prim, Color sec, Color div) {
    final surf = NothingTheme.surf(dark);
    final saldo = double.tryParse(conductor?['saldo_comisiones']?.toString() ?? '0') ?? 0.0;

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      color: NothingTheme.accentOrange,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // ── Header conductor ──
          if (conductor != null)
            NothingCard(
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: NothingTheme.accentOrange.withOpacity(0.15),
                  child: conductor!['foto_carnet'] != null
                      ? ClipOval(child: Image.network(conductor!['foto_carnet'],
                          width: 56, height: 56, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.directions_bus,
                                  color: NothingTheme.accentOrange)))
                      : const Icon(Icons.directions_bus,
                          color: NothingTheme.accentOrange, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${conductor!['nombre']} ${conductor!['apellido']}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 14,
                            fontWeight: FontWeight.w700, color: prim)),
                    const SizedBox(height: 2),
                    Text(conductor!['empresa'] ?? 'Sin empresa',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: sec)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: conductor!['estado'] == 'activo'
                          ? NothingTheme.accentGreen.withOpacity(0.12)
                          : NothingTheme.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: conductor!['estado'] == 'activo'
                            ? NothingTheme.accentGreen
                            : NothingTheme.error,
                        width: 0.5,
                      ),
                    ),
                    child: Text((conductor!['estado'] ?? 'inactivo').toUpperCase(),
                        style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: conductor!['estado'] == 'activo'
                                ? NothingTheme.accentGreen
                                : NothingTheme.error)),
                  ),
                ]),
              ]),
            ),
          const SizedBox(height: 16),

          // ── Toggle servicio ──
          _buildToggleServicio(dark, prim, sec, surf),
          const SizedBox(height: 16),

          // ── Resumen del día ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NothingTheme.accentOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: NothingTheme.accentOrange.withOpacity(0.3), width: 0.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RESUMEN DE HOY', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2.5,
                  color: sec)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _StatBox(value: '$_viajesHoy', label: 'Viajes',
                    icon: Icons.qr_code_scanner, color: NothingTheme.accentGreen),
                _StatBox(value: 'Bs ${_gananciaHoy.toStringAsFixed(2)}',
                    label: 'Ganancia', icon: Icons.attach_money,
                    color: NothingTheme.accentOrange),
                _StatBox(value: '${_kmHoy.toStringAsFixed(1)} km',
                    label: 'Recorrido', icon: Icons.route,
                    color: NothingTheme.accentBlue),
              ]),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Saldo comisiones ──
          NothingCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SALDO COMISIONES', style: TextStyle(fontFamily: 'monospace',
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 2.5, color: sec)),
                  const SizedBox(height: 6),
                  Text('Bs ${saldo.toStringAsFixed(2)}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: NothingTheme.accentGreen)),
                ]),
                Icon(Icons.account_balance_wallet_outlined,
                    size: 40, color: NothingTheme.accentGreen.withOpacity(0.3)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Contrato ──
          Text('CONTRATO', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
          const SizedBox(height: 8),
          _buildCardContrato(dark, prim, sec, div, surf),
          const SizedBox(height: 16),

          // ── Acceso rápido QR ──
          GestureDetector(
            onTap: () { _tabCtrl.animateTo(2); _abrirScanner(); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: NothingTheme.accentGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.qr_code_scanner, color: Colors.black, size: 22),
                SizedBox(width: 10),
                Text('ESCANEAR QR DE PASAJERO', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12,
                    fontWeight: FontWeight.w700, letterSpacing: 2,
                    color: Colors.black)),
              ]),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  TAB 2 — MAPA
  // ─────────────────────────────────────────────
  Widget _buildTabMapa(bool dark, Color bg, Color prim, Color sec, Color div) {
    final initialPos = _ultimaPos != null
        ? LatLng(_ultimaPos!.latitude, _ultimaPos!.longitude)
        : const LatLng(-17.3895, -66.1568); // Cochabamba

    return Stack(children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(target: initialPos, zoom: 13),
        onMapCreated: (ctrl) => _mapCtrl = ctrl,
        markers: _markers,
        polylines: _polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        mapType: MapType.normal,
        mapToolbarEnabled: false,
        zoomControlsEnabled: false,
        style: dark ? _darkMapStyle : null,
      ),

      // Botón centrar en mi posición
      Positioned(bottom: 100, right: 16,
        child: FloatingActionButton.small(
          heroTag: 'center',
          backgroundColor: NothingTheme.surf(dark),
          onPressed: () {
            if (_ultimaPos != null) {
              if (mounted && _mapCtrl != null) {
                try {
                  _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(
                      LatLng(_ultimaPos!.latitude, _ultimaPos!.longitude), 15));
                } catch (_) {}
              }
            }
          },
          child: Icon(Icons.my_location, color: prim, size: 18),
        ),
      ),

      // Panel info inferior
      Positioned(bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NothingTheme.surf(dark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: div, width: 0.5)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 3, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: div.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2))),
            Row(children: [
              _enServicio
                  ? Row(children: [
                      Container(width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: NothingTheme.accentGreen, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('En servicio — ${_tiempoServicio()}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                              color: NothingTheme.accentGreen)),
                    ])
                  : Text('Fuera de servicio', style: TextStyle(
                      fontFamily: 'monospace', fontSize: 10, color: sec)),
              const Spacer(),
              if (_ultimaPos != null)
                Text('${(_ultimaPos!.speed * 3.6).toStringAsFixed(0)} km/h',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                        color: NothingTheme.accentBlue)),
            ]),
            if (rutaAsignada != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.route, size: 14, color: NothingTheme.accentOrange),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  '${rutaAsignada!['origen']} → ${rutaAsignada!['destino']}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: prim),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
              ]),
            ],
          ]),
        ),
      ),
    ]);
  }

  // ─────────────────────────────────────────────
  //  TAB 3 — QR
  // ─────────────────────────────────────────────
  Widget _buildTabQR(bool dark, Color bg, Color prim, Color sec, Color div) {
    final conductorId = conductor?['id'] as String?;
    final surf = NothingTheme.surf(dark);

    // QR estático basado en el ID del conductor
    final qrData = conductorId != null ? 'conductor_$conductorId' : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 16),

        // Header
        Text('MI CÓDIGO QR', style: TextStyle(fontFamily: 'monospace',
            fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 3, color: prim)),
        const SizedBox(height: 6),
        Text('Los pasajeros escanean este QR para pagar su viaje.',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),

        // QR estático
        if (qrData != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: NothingTheme.accentGreen.withOpacity(0.25),
                blurRadius: 30, spreadRadius: 4,
              )],
            ),
            child: Column(children: [
              QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: NothingTheme.accentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  conductor?['nombre'] != null
                      ? '${conductor!['nombre']} ${conductor!['apellido'] ?? ''}'.trim().toUpperCase()
                      : 'CONDUCTOR',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1.5,
                      color: NothingTheme.accentGreen),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Instrucción
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: div, width: 0.5),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18, color: NothingTheme.accentBlue),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Este QR es permanente. El pasajero lo escanea con la app y el cobro se procesa automáticamente.',
                style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: sec),
              )),
            ]),
          ),
          const SizedBox(height: 20),
        ] else ...[
          // Sin conductor cargado
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: div, width: 0.5),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.qr_code_2_outlined, size: 56, color: sec.withOpacity(0.3)),
              const SizedBox(height: 12),
              Text('Cargando QR...', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: sec)),
            ]),
          ),
          const SizedBox(height: 20),
        ],

        // Info tarifa
        NothingCard(
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('TARIFAS QUE COBRARÁS', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 2.5, color: sec)),
            ]),
            const SizedBox(height: 12),
            _TarifaRow(tipo: 'General',      tarifa: 2.50, color: prim,     sec: sec),
            _TarifaRow(tipo: 'Estudiante',   tarifa: 1.25, color: NothingTheme.accentPurple, sec: sec),
            _TarifaRow(tipo: 'Adulto mayor', tarifa: 1.75, color: NothingTheme.accentBlue,   sec: sec),
            _TarifaRow(tipo: 'Discapacidad', tarifa: 0.00, color: NothingTheme.accentOrange, sec: sec),
          ]),
        ),
        const SizedBox(height: 20),

        // Último pago recibido
        if (_resultadoQR != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NothingTheme.accentGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NothingTheme.accentGreen.withOpacity(0.3), width: 0.5),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_outline,
                  color: NothingTheme.accentGreen, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Último pago recibido:\n$_resultadoQR',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: prim))),
            ]),
          ),
        const SizedBox(height: 40),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  //  TAB 4 — RUTA
  // ─────────────────────────────────────────────
  Widget _buildTabRuta(bool dark, Color bg, Color prim, Color sec, Color div) {
    if (rutaAsignada == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.route, size: 56, color: sec.withOpacity(0.3)),
        const SizedBox(height: 16),
        Text('Sin ruta asignada', style: TextStyle(fontFamily: 'monospace',
            fontSize: 13, color: sec)),
        const SizedBox(height: 8),
        Text('El administrador debe asignarte una ruta',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: sec)),
      ]));
    }

    final ruta = rutaAsignada!;
    final paradas = (ruta['paradas'] as List?)?.cast<Map>() ?? [];
    final colorHex = ruta['color_hex'] as String? ?? '#E87F2A';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header ruta
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hexColor(colorHex).withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hexColor(colorHex).withOpacity(0.3), width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 12, height: 12,
                  decoration: BoxDecoration(color: _hexColor(colorHex),
                      shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('RUTA ${ruta['codigo'] ?? ''}', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 2.5, color: sec)),
            ]),
            const SizedBox(height: 8),
            Text(ruta['nombre'] ?? '—', style: TextStyle(fontFamily: 'monospace',
                fontSize: 16, fontWeight: FontWeight.w700, color: prim)),
            if (ruta['descripcion'] != null) ...[
              const SizedBox(height: 4),
              Text(ruta['descripcion'], style: TextStyle(
                  fontFamily: 'monospace', fontSize: 10, color: sec)),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // Origen y destino
        NothingCard(
          child: Column(children: [
            Row(children: [
              Container(width: 10, height: 10,
                  decoration: const BoxDecoration(
                      color: NothingTheme.accentGreen, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text('ORIGEN', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9, letterSpacing: 2, color: sec)),
              const Spacer(),
              Text(ruta['origen'] ?? '—', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 12, fontWeight: FontWeight.w700, color: prim)),
            ]),
            Container(margin: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                width: 2, height: 24, color: div),
            Row(children: [
              Container(width: 10, height: 10,
                  decoration: const BoxDecoration(
                      color: NothingTheme.error, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text('DESTINO', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9, letterSpacing: 2, color: sec)),
              const Spacer(),
              Text(ruta['destino'] ?? '—', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 12, fontWeight: FontWeight.w700, color: prim)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // Stats de la ruta
        Row(children: [
          Expanded(child: _RutaStat(
            label: 'DISTANCIA',
            value: ruta['distancia_km'] != null
                ? '${ruta['distancia_km']} km' : '—',
            icon: Icons.straighten, color: NothingTheme.accentBlue,
          )),
          const SizedBox(width: 12),
          Expanded(child: _RutaStat(
            label: 'DURACIÓN',
            value: ruta['duracion_minutos'] != null
                ? '${ruta['duracion_minutos']} min' : '—',
            icon: Icons.timer_outlined, color: NothingTheme.accentOrange,
          )),
        ]),
        const SizedBox(height: 16),

        // Paradas
        if (paradas.isNotEmpty) ...[
          Text('PARADAS', style: TextStyle(fontFamily: 'monospace',
              fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 2.5, color: sec)),
          const SizedBox(height: 8),
          ...paradas.asMap().entries.map((e) {
            final i    = e.key;
            final p    = e.value;
            final last = i == paradas.length - 1;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: i == 0 ? NothingTheme.accentGreen
                          : last ? NothingTheme.error
                          : NothingTheme.accentOrange,
                      shape: BoxShape.circle,
                    )),
                if (!last) Container(width: 1, height: 28, color: div),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(p['nombre']?.toString() ?? 'Parada ${i + 1}',
                      style: TextStyle(fontFamily: 'monospace',
                          fontSize: 11, color: prim)),
                ),
              ),
            ]);
          }),
        ],
        const SizedBox(height: 40),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  //  TAB 5 — PAGOS
  // ─────────────────────────────────────────────
  Widget _buildTabPagos(bool dark, Color bg, Color prim, Color sec, Color div) {
    final surf = NothingTheme.surf(dark);
    final totalGanancias = double.tryParse(
        resumenGanancias?['total_ganancias']?.toString() ?? '0') ?? 0.0;
    final pendientes = double.tryParse(
        resumenGanancias?['pagos_pendientes']?.toString() ?? '0') ?? 0.0;
    final abonados = double.tryParse(
        resumenGanancias?['pagos_abonados']?.toString() ?? '0') ?? 0.0;

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      color: NothingTheme.accentOrange,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // Resumen ganancias
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NothingTheme.accentGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: NothingTheme.accentGreen.withOpacity(0.3), width: 0.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RESUMEN DE GANANCIAS', style: TextStyle(fontFamily: 'monospace',
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 2.5, color: sec)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _StatBox(value: 'Bs ${totalGanancias.toStringAsFixed(2)}',
                    label: 'Total', icon: Icons.account_balance_wallet,
                    color: NothingTheme.accentGreen),
                _StatBox(value: 'Bs ${pendientes.toStringAsFixed(2)}',
                    label: 'Pendiente', icon: Icons.hourglass_empty,
                    color: NothingTheme.accentOrange),
                _StatBox(value: 'Bs ${abonados.toStringAsFixed(2)}',
                    label: 'Abonado', icon: Icons.check_circle_outline,
                    color: NothingTheme.accentBlue),
              ]),
            ]),
          ),
          const SizedBox(height: 16),

          // Filtros
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _Chip(label: 'Todos',     value: 'todos',     current: _filtroEstado, onTap: _setFiltro),
              const SizedBox(width: 8),
              _Chip(label: 'Pendiente', value: 'pendiente', current: _filtroEstado, onTap: _setFiltro),
              const SizedBox(width: 8),
              _Chip(label: 'Abonado',   value: 'abonado',   current: _filtroEstado, onTap: _setFiltro),
              const SizedBox(width: 8),
              _Chip(label: 'Retirado',  value: 'retirado',  current: _filtroEstado, onTap: _setFiltro),
            ]),
          ),
          const SizedBox(height: 12),

          // Lista pagos
          if (pagos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Sin registros de pagos',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec))),
            )
          else
            ...pagos.map((pago) {
              final comision = double.tryParse(pago['comision_conductor'].toString()) ?? 0.0;
              final estado   = pago['estado'] ?? 'pendiente';
              final fecha    = DateTime.tryParse(pago['fecha_pago'] ?? '') ?? DateTime.now();
              Color ec;
              switch (estado) {
                case 'abonado':  ec = NothingTheme.accentGreen; break;
                case 'retirado': ec = NothingTheme.accentBlue;  break;
                default:         ec = NothingTheme.accentOrange;
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: surf,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: div, width: 0.5)),
                child: Row(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: ec.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.qr_code, size: 18, color: ec),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CI: ${pago['usuario_pasajero_ci']}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                            fontWeight: FontWeight.w700, color: prim)),
                    const SizedBox(height: 2),
                    Text(DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: sec)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Bs ${comision.toStringAsFixed(2)}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 15,
                            fontWeight: FontWeight.w900, color: ec)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: ec.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ec.withOpacity(0.4), width: 0.5)),
                      child: Text(estado.toUpperCase(), style: TextStyle(
                          fontFamily: 'monospace', fontSize: 8,
                          fontWeight: FontWeight.w700, color: ec)),
                    ),
                  ]),
                ]),
              );
            }),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  void _setFiltro(String v) {
    setState(() => _filtroEstado = v);
    _cargarDatos();
  }

  // ─────────────────────────────────────────────
  //  Widget toggle servicio
  // ─────────────────────────────────────────────
  Widget _buildToggleServicio(bool dark, Color prim, Color sec, Color surf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _enServicio
            ? NothingTheme.accentGreen.withOpacity(0.08)
            : surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _enServicio ? NothingTheme.accentGreen : NothingTheme.div(dark),
          width: _enServicio ? 1 : 0.5,
        ),
      ),
      child: Column(children: [
        Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: _enServicio ? NothingTheme.accentGreen : sec,
              shape: BoxShape.circle,
              boxShadow: _enServicio ? [BoxShadow(
                  color: NothingTheme.accentGreen.withOpacity(0.5), blurRadius: 6)] : [],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_enServicio ? 'EN SERVICIO' : 'FUERA DE SERVICIO',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _enServicio ? NothingTheme.accentGreen : sec)),
            if (_enServicio)
              Text('Tiempo activo: ${_tiempoServicio()}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: sec)),
          ])),
          _iniciandoServ
              ? const SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: NothingTheme.accentGreen))
              : GestureDetector(
                  onTap: _toggleServicio,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 52, height: 28,
                    decoration: BoxDecoration(
                      color: _enServicio ? NothingTheme.accentGreen : NothingTheme.div(dark),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 300),
                      alignment: _enServicio ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(margin: const EdgeInsets.all(3),
                          width: 22, height: 22,
                          decoration: BoxDecoration(color: prim, shape: BoxShape.circle)),
                    ),
                  ),
                ),
        ]),
        if (_enServicio && _ultimaPos != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NothingTheme.bg(dark),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.location_on, size: 12, color: NothingTheme.accentGreen),
              const SizedBox(width: 6),
              Text('${_ultimaPos!.latitude.toStringAsFixed(5)}, '
                  '${_ultimaPos!.longitude.toStringAsFixed(5)}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: sec)),
              const Spacer(),
              Text('${(_ultimaPos!.speed * 3.6).toStringAsFixed(0)} km/h',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: NothingTheme.accentBlue)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ─────────────────────────────────────────────
  //  Widget card contrato
  // ─────────────────────────────────────────────
  Widget _buildCardContrato(bool dark, Color prim, Color sec, Color div, Color surf) {
    if (contrato == null) {
      return NothingCard(child: Center(child: Text('Sin contrato',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec))));
    }
    final estado = contrato!['estado'] ?? 'pendiente';
    Color ec;
    String et;
    switch (estado) {
      case 'aceptado':  ec = NothingTheme.accentGreen;  et = 'APROBADO';  break;
      case 'rechazado': ec = NothingTheme.error;        et = 'RECHAZADO'; break;
      default:          ec = NothingTheme.accentOrange; et = 'PENDIENTE';
    }
    return NothingCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('ESTADO DEL CONTRATO', style: TextStyle(fontFamily: 'monospace',
              fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2, color: sec)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ec.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ec.withOpacity(0.5), width: 0.5),
            ),
            child: Text(et, style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                fontWeight: FontWeight.w700, color: ec)),
          ),
        ]),
        const SizedBox(height: 10),
        Text('Empresa: ${contrato!['empresa'] ?? '—'}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: prim)),
        Text('Comisión: ${contrato!['comision_porcentaje'] ?? 10}%',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: prim)),
        if (estado == 'pendiente') ...[
          const SizedBox(height: 12),
          NothingButton(label: 'ACEPTAR CONTRATO', onTap: _aceptarContrato,
              filled: true, icon: Icons.check, color: NothingTheme.accentGreen),
        ],
      ]),
    );
  }

  // ─────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────
  Color _hexColor(String hex) {
    try {
      return Color(int.parse(hex.replaceAll('#', '0xFF')));
    } catch (_) {
      return NothingTheme.accentOrange;
    }
  }

  // Estilo oscuro para Google Maps
  static const String _darkMapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#212121"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c2c2c"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]}
  ]''';
}

// ─────────────────────────────────────────────
//  Widgets auxiliares
// ─────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatBox({required this.value, required this.label,
      required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, size: 20, color: color),
    const SizedBox(height: 6),
    Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 13,
        fontWeight: FontWeight.w900, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
        color: NothingTheme.secondary)),
  ]);
}

class _TarifaRow extends StatelessWidget {
  final String tipo;
  final double tarifa;
  final Color color, sec;
  const _TarifaRow({required this.tipo, required this.tarifa,
      required this.color, required this.sec});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(tipo, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec)),
      ]),
      Text(tarifa == 0 ? 'GRATUITO' : 'Bs ${tarifa.toStringAsFixed(2)}',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11,
              fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

class _RutaStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _RutaStat({required this.label, required this.value,
      required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Column(children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 16,
            fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 8,
            color: NothingTheme.sec(dark))),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onTap;
  const _Chip({required this.label, required this.value,
      required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? NothingTheme.accentOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? NothingTheme.accentOrange
                : NothingTheme.div(themeNotifier.isDark),
            width: sel ? 1 : 0.5,
          ),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 10,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
            color: sel ? Colors.black
                : NothingTheme.prim(themeNotifier.isDark))),
      ),
    );
  }
}