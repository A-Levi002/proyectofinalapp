import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/nothing_theme.dart';
import '../models/usuario_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';

class GenerarQRScreen extends StatefulWidget {
  final StorageService? storageService;
  const GenerarQRScreen({this.storageService, super.key});

  @override
  State<GenerarQRScreen> createState() => _GenerarQRScreenState();
}

class _GenerarQRScreenState extends State<GenerarQRScreen> {
  late SupabaseService _supabaseService;
  late StorageService  _storageService;

  UsuarioModel? _usuario;

  // ── Acompañantes ──
  int _totalPersonas = 1;

  // ── Escáner ──
  MobileScannerController? _scannerCtrl;
  bool _escaneando  = false;
  bool _procesando  = false;

  // ── Resultado ──
  bool?   _exitoPago;
  String? _mensajeResultado;
  Map<String, dynamic>? _datosPago;

  @override
  void initState() {
    super.initState();
    _storageService  = widget.storageService ?? StorageService();
    _supabaseService = SupabaseService(_storageService);
    _cargarUsuario();
    themeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    _scannerCtrl?.dispose();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _cargarUsuario() async {
    try {
      final u = _storageService.obtenerUsuario();
      setState(() => _usuario = u);
      // Refrescar desde Supabase
      final fresco = await _supabaseService.obtenerPerfil();
      if (fresco != null && mounted) {
        await _storageService.guardarUsuario(fresco);
        setState(() => _usuario = fresco);
      }
    } catch (_) {}
  }

  // ── Tarifas ──
  double get _tarifaPropia =>
      TarifasHelper.calcularTarifa(tipoUsuario: _usuario?.tipoUsuario ?? 'general');
  int    get _cantAcompanantes  => _totalPersonas - 1;
  double get _tarifaAcompanantes => _cantAcompanantes * TarifasHelper.tarifaBase;
  double get _totalACobrar       => _tarifaPropia + _tarifaAcompanantes;

  // ── Abrir escáner ──
  void _abrirEscaner() {
    _scannerCtrl = MobileScannerController(
      autoStart: true,
      torchEnabled: false,
      facing: CameraFacing.back,
    );
    setState(() {
      _escaneando       = true;
      _exitoPago        = null;
      _mensajeResultado = null;
      _datosPago        = null;
    });
  }

  void _cerrarEscaner() {
    _scannerCtrl?.dispose();
    _scannerCtrl = null;
    setState(() { _escaneando = false; _procesando = false; });
  }

  // ── Procesar QR del conductor ──
  Future<void> _procesarQRConductor(String qrData) async {
    if (_procesando) return;
    if (!qrData.startsWith('conductor_')) {
      _mostrarSnack('QR inválido. Escanea el código del conductor.');
      return;
    }

    setState(() => _procesando = true);
    _scannerCtrl?.stop();

    try {
      final resultado = await _supabaseService.procesarPagoQRConductor(
        qrData: qrData,
        cantidadPersonas: _totalPersonas,
        montoExtra: _tarifaAcompanantes,
      );

      _scannerCtrl?.dispose();
      _scannerCtrl = null;

      if (!mounted) return;
      setState(() {
        _escaneando       = false;
        _procesando       = false;
        _exitoPago        = resultado['exito'] == true;
        _mensajeResultado = resultado['mensaje'];
        _datosPago        = resultado['exito'] == true ? resultado : null;
      });

      if (resultado['exito'] == true) {
        // Refrescar saldo
        await _cargarUsuario();
        // Resetear acompañantes
        setState(() => _totalPersonas = 1);
      }
    } catch (e) {
      if (!mounted) return;
      _scannerCtrl?.dispose();
      _scannerCtrl = null;
      setState(() {
        _escaneando       = false;
        _procesando       = false;
        _exitoPago        = false;
        _mensajeResultado = 'Error: $e';
      });
    }
  }

  void _mostrarSnack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: NothingTheme.error,
        duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    // Vista del escáner
    if (_escaneando && _scannerCtrl != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          MobileScanner(
            controller: _scannerCtrl!,
            onDetect: (capture) {
              if (_procesando) return;
              for (final barcode in capture.barcodes) {
                final val = barcode.rawValue;
                if (val != null && val.isNotEmpty) {
                  _procesarQRConductor(val);
                  break;
                }
              }
            },
            errorBuilder: (_, __, ___) => Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.camera_alt, size: 64, color: Colors.white54),
                const SizedBox(height: 16),
                const Text('Error al acceder a la cámara',
                    style: TextStyle(fontFamily: 'monospace', color: Colors.white70)),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _cerrarEscaner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: NothingTheme.error,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('VOLVER', style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11,
                        fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),

          // Marco de escaneo
          Center(child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: NothingTheme.accentGreen, width: 2.5),
              borderRadius: BorderRadius.circular(18),
            ),
          )),

          // Overlay superior
          Positioned(top: 60, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _procesando ? 'Procesando pago...' : 'Apunta al QR del conductor',
                style: const TextStyle(fontFamily: 'monospace',
                    fontSize: 12, color: Colors.white),
              ),
            )),
          ),

          // Loading overlay
          if (_procesando)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(
                  color: NothingTheme.accentGreen)),
            ),

          // Botones inferiores
          if (!_procesando)
            Positioned(bottom: 48, left: 20, right: 20,
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _cerrarEscaner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: NothingTheme.error.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Text('CANCELAR',
                        style: TextStyle(fontFamily: 'monospace',
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: Colors.white))),
                  ),
                )),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _scannerCtrl?.toggleTorch(),
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flash_on, color: Colors.white, size: 22),
                  ),
                ),
              ]),
            ),
        ]),
      );
    }

    // Vista principal
    return Scaffold(
      backgroundColor: bg,
      appBar: const NothingAppBar(title: 'PAGAR VIAJE'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const SizedBox(height: 8),

          // Card usuario
          if (_usuario != null) ...[
            _buildCardUsuario(dark, prim, sec, div, surf),
            const SizedBox(height: 16),
            _buildCardAcompanantes(dark, prim, sec, div, surf),
            const SizedBox(height: 16),
            _buildCardTarifa(dark, prim, sec, div, surf),
            const SizedBox(height: 24),
          ],

          // Resultado del pago
          if (_exitoPago == true && _datosPago != null) ...[
            _buildPagoExitoso(dark, prim, sec, div, surf),
            const SizedBox(height: 20),
          ] else if (_exitoPago == false) ...[
            _buildPagoError(dark, sec),
            const SizedBox(height: 20),
          ],

          // Botón escanear
          _buildBotonEscanear(dark),

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
              const Icon(Icons.qr_code_scanner, size: 18,
                  color: NothingTheme.accentBlue),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Escanea el código QR que muestra el conductor en su panel. '
                'El cobro se aplica automáticamente según tu tipo de usuario.',
                style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: sec),
              )),
            ]),
          ),

          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── Card usuario ──
  Widget _buildCardUsuario(bool dark, Color prim, Color sec, Color div, Color surf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: div, width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: NothingTheme.accentGreen.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
                color: NothingTheme.accentGreen.withOpacity(0.4), width: 0.5),
          ),
          child: Center(child: Text(
            _usuario!.nombre.isNotEmpty
                ? _usuario!.nombre[0].toUpperCase() : 'U',
            style: TextStyle(fontFamily: 'monospace', fontSize: 20,
                fontWeight: FontWeight.w900, color: prim),
          )),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_usuario!.nombre} ${_usuario!.apellido}',
              style: TextStyle(fontFamily: 'monospace', fontSize: 13,
                  fontWeight: FontWeight.w700, color: prim)),
          const SizedBox(height: 3),
          NothingBadge(
              label: _usuario!.tipoUsuario.toUpperCase(),
              color: NothingTheme.accentGreen),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('SALDO', style: TextStyle(fontFamily: 'monospace',
              fontSize: 8, letterSpacing: 1.5, color: sec)),
          Text(FormateoHelper.formatearMoneda(_usuario!.saldo),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: NothingTheme.accentGreen)),
        ]),
      ]),
    );
  }

  // ── Card acompañantes ──
  Widget _buildCardAcompanantes(bool dark, Color prim, Color sec, Color div, Color surf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _cantAcompanantes > 0
              ? NothingTheme.accentOrange.withOpacity(0.5) : div,
          width: _cantAcompanantes > 0 ? 1.0 : 0.5,
        ),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.group_outlined, size: 16,
              color: _cantAcompanantes > 0 ? NothingTheme.accentOrange : sec),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ACOMPAÑANTES', style: TextStyle(fontFamily: 'monospace',
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2,
                color: _cantAcompanantes > 0 ? NothingTheme.accentOrange : sec)),
            const SizedBox(height: 2),
            Text(
              _cantAcompanantes == 0
                  ? 'Solo tú (sin acompañantes)'
                  : '$_cantAcompanantes acompañante${_cantAcompanantes > 1 ? 's' : ''} · Bs 2.50 c/u',
              style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: sec)),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          // Botón -
          GestureDetector(
            onTap: _totalPersonas > 1
                ? () => setState(() => _totalPersonas--) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _totalPersonas > 1
                    ? NothingTheme.accentOrange.withOpacity(0.15) : div.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _totalPersonas > 1
                      ? NothingTheme.accentOrange.withOpacity(0.5) : div,
                  width: 0.5),
              ),
              child: Icon(Icons.remove, size: 18,
                  color: _totalPersonas > 1
                      ? NothingTheme.accentOrange : sec.withOpacity(0.3)),
            ),
          ),
          // Íconos personas
          Expanded(child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final activo = i < _totalPersonas;
              final esAcomp = i > 0;
              return GestureDetector(
                onTap: () => setState(() => _totalPersonas = i + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40, height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: activo
                        ? (esAcomp
                            ? NothingTheme.accentOrange.withOpacity(0.12)
                            : NothingTheme.accentGreen.withOpacity(0.12))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: activo
                          ? (esAcomp
                              ? NothingTheme.accentOrange.withOpacity(0.5)
                              : NothingTheme.accentGreen.withOpacity(0.5))
                          : div.withOpacity(0.4),
                      width: 0.5),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(i == 0 ? Icons.person : Icons.person_outline, size: 20,
                        color: activo
                            ? (esAcomp ? NothingTheme.accentOrange : NothingTheme.accentGreen)
                            : sec.withOpacity(0.3)),
                    const SizedBox(height: 2),
                    Text(i == 0 ? 'YO' : '+$i',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: activo
                                ? (esAcomp ? NothingTheme.accentOrange : NothingTheme.accentGreen)
                                : sec.withOpacity(0.3))),
                  ]),
                ),
              );
            }),
          )),
          // Botón +
          GestureDetector(
            onTap: _totalPersonas < 4
                ? () => setState(() => _totalPersonas++) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _totalPersonas < 4
                    ? NothingTheme.accentOrange.withOpacity(0.15) : div.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _totalPersonas < 4
                      ? NothingTheme.accentOrange.withOpacity(0.5) : div,
                  width: 0.5),
              ),
              child: Icon(Icons.add, size: 18,
                  color: _totalPersonas < 4
                      ? NothingTheme.accentOrange : sec.withOpacity(0.3)),
            ),
          ),
        ]),
        if (_cantAcompanantes > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NothingTheme.accentOrange.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 12, color: NothingTheme.accentOrange),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Los acompañantes pagan tarifa general (Bs 2.50 c/u). '
                'El descuento aplica solo a tu pasaje.',
                style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                    color: NothingTheme.accentOrange),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Card tarifa ──
  Widget _buildCardTarifa(bool dark, Color prim, Color sec, Color div, Color surf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: div, width: 0.5),
      ),
      child: Column(children: [
        Text('RESUMEN DE COBRO', style: TextStyle(fontFamily: 'monospace',
            fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 14),
        _FilaTarifa(
          label: 'Mi pasaje (${_usuario?.tipoUsuario ?? ''})',
          valor: FormateoHelper.formatearMoneda(_tarifaPropia),
          color: NothingTheme.accentGreen, dark: dark,
        ),
        if (_cantAcompanantes > 0) ...[
          const SizedBox(height: 6),
          _FilaTarifa(
            label: '$_cantAcompanantes acompañante${_cantAcompanantes > 1 ? 's' : ''} × Bs 2.50',
            valor: FormateoHelper.formatearMoneda(_tarifaAcompanantes),
            color: NothingTheme.accentOrange, dark: dark,
          ),
        ],
        Divider(color: div, height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('TOTAL A PAGAR', style: TextStyle(fontFamily: 'monospace',
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: prim)),
          Text(FormateoHelper.formatearMoneda(_totalACobrar),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 20,
                  fontWeight: FontWeight.w900, color: NothingTheme.accentGreen)),
        ]),
        // Saldo insuficiente
        if (_usuario != null && _usuario!.saldo < _totalACobrar) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: NothingTheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: NothingTheme.error.withOpacity(0.3), width: 0.5),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_outlined, size: 12, color: NothingTheme.error),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Saldo insuficiente para $_totalPersonas persona${_totalPersonas > 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                    color: NothingTheme.error))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/recarga'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: NothingTheme.accentGreen,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('RECARGAR', style: TextStyle(
                      fontFamily: 'monospace', fontSize: 8,
                      fontWeight: FontWeight.w700, color: Colors.black)),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Pago exitoso ──
  Widget _buildPagoExitoso(bool dark, Color prim, Color sec, Color div, Color surf) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NothingTheme.accentGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: NothingTheme.accentGreen.withOpacity(0.4), width: 1),
      ),
      child: Column(children: [
        const Icon(Icons.check_circle, color: NothingTheme.accentGreen, size: 44),
        const SizedBox(height: 12),
        Text('PAGO EXITOSO', style: TextStyle(fontFamily: 'monospace',
            fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3,
            color: NothingTheme.accentGreen)),
        const SizedBox(height: 16),
        if (_datosPago != null) ...[
          _FilaResultado('Conductor', _datosPago!['conductorNombre']?.toString() ?? '—', prim, sec),
          const SizedBox(height: 6),
          _FilaResultado('Personas', '${_datosPago!['cantidadPersonas'] ?? 1}', prim, sec),
          const SizedBox(height: 6),
          _FilaResultado(
            'Cobrado',
            FormateoHelper.formatearMoneda(
                (_datosPago!['tarifaAplicada'] as num?)?.toDouble() ?? 0),
            NothingTheme.accentGreen, sec,
          ),
          const SizedBox(height: 6),
          _FilaResultado(
            'Saldo restante',
            FormateoHelper.formatearMoneda(
                (_datosPago!['saldoRestante'] as num?)?.toDouble() ?? 0),
            prim, sec,
          ),
        ],
      ]),
    );
  }

  // ── Pago error ──
  Widget _buildPagoError(bool dark, Color sec) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NothingTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NothingTheme.error.withOpacity(0.3), width: 0.5),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 20, color: NothingTheme.error),
        const SizedBox(width: 10),
        Expanded(child: Text(_mensajeResultado ?? 'Error al procesar el pago',
            style: const TextStyle(fontFamily: 'monospace',
                fontSize: 11, color: NothingTheme.error))),
      ]),
    );
  }

  // ── Botón escanear ──
  Widget _buildBotonEscanear(bool dark) {
    final saldoOk = _usuario == null || _usuario!.saldo >= _totalACobrar;
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: saldoOk ? _abrirEscaner : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: saldoOk
                ? NothingTheme.accentGreen
                : NothingTheme.accentGreen.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.qr_code_scanner, size: 22, color: Colors.black),
            SizedBox(width: 12),
            Text('ESCANEAR QR DEL CONDUCTOR', style: TextStyle(
                fontFamily: 'monospace', fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
                color: Colors.black)),
          ]),
        ),
      ),
    );
  }
}

// ── Fila tarifa ──
class _FilaTarifa extends StatelessWidget {
  final String label, valor;
  final Color color;
  final bool dark;
  const _FilaTarifa({required this.label, required this.valor,
      required this.color, required this.dark});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11,
          color: NothingTheme.sec(dark))),
      Text(valor, style: TextStyle(fontFamily: 'monospace', fontSize: 13,
          fontWeight: FontWeight.w700, color: color)),
    ],
  );
}

// ── Fila resultado ──
class _FilaResultado extends StatelessWidget {
  final String label, valor;
  final Color colorValor, sec;
  const _FilaResultado(this.label, this.valor, this.colorValor, this.sec);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: sec)),
      Text(valor, style: TextStyle(fontFamily: 'monospace', fontSize: 12,
          fontWeight: FontWeight.w700, color: colorValor)),
    ],
  );
}
