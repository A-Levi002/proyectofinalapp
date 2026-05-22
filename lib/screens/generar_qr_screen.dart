import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  late StorageService _storageService;

  UsuarioModel? _usuario;
  String? _tokenQR;
  DateTime? _horaExpiracion;
  bool _cargando = false;
  int _segundosRestantes = 0;
  String? _errorMessage;
  Timer? _timer;

  // ── Acompañantes ──
  // 1 = solo yo; 2-4 = yo + acompañantes (pasajes extra a tarifa general Bs 2.50)
  int _totalPersonas = 1;

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
    _timer?.cancel();
    themeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _cargarUsuario() async {
    try {
      final u = _storageService.obtenerUsuario();
      setState(() => _usuario = u);
    } catch (e) {
      _mostrarError('Error al cargar usuario: $e');
    }
  }

  Future<void> _actualizarSaldoDesdeSupabase() async {
    try {
      final u = await _supabaseService.obtenerPerfil();
      if (u != null) {
        await _storageService.guardarUsuario(u);
        setState(() => _usuario = u);
      }
    } catch (_) {}
  }

  // ── Cálculo de tarifas ──
  double get _tarifaPropia =>
      TarifasHelper.calcularTarifa(tipoUsuario: _usuario?.tipoUsuario ?? 'general');

  // Acompañantes siempre pagan tarifa general (Bs 2.50 sin descuento)
  int get _cantAcompanantes => _totalPersonas - 1;
  double get _tarifaAcompanantes => _cantAcompanantes * TarifasHelper.tarifaBase;
  double get _totalACobrar      => _tarifaPropia + _tarifaAcompanantes;

  Future<void> _generarQR() async {
    if (_usuario == null) { _mostrarError('Usuario no cargado'); return; }

    await _actualizarSaldoDesdeSupabase();

    if (_usuario!.saldo < _totalACobrar) {
      _mostrarError(
          'Saldo insuficiente. Necesitas ${FormateoHelper.formatearMoneda(_totalACobrar)}'
          ' y tienes ${FormateoHelper.formatearMoneda(_usuario!.saldo)}.');
      return;
    }

    setState(() {
      _cargando = true;
      _errorMessage = null;
      _tokenQR = null;
      _segundosRestantes = 0;
      _timer?.cancel();
    });

    try {
      // Pasamos el monto total al service (propio + acompañantes)
      final resultado = await _supabaseService.generarQRViaje(
        montoExtra: _tarifaAcompanantes,
        cantidadPersonas: _totalPersonas,
      );

      if (resultado['exito'] == true) {
        setState(() {
          _tokenQR = resultado['qrData'];
          _cargando = false;
          _segundosRestantes = 30;
          _horaExpiracion = DateTime.now().add(const Duration(seconds: 30));
        });
        await _actualizarSaldoDesdeSupabase();
        _iniciarContadorRegresivo();
      } else {
        _mostrarError(resultado['mensaje'] ?? 'Error al generar QR');
        setState(() => _cargando = false);
      }
    } catch (e) {
      _mostrarError('Error de conexión: $e');
      setState(() => _cargando = false);
    }
  }

  void _iniciarContadorRegresivo() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_segundosRestantes > 0) {
          _segundosRestantes--;
        }
        if (_segundosRestantes <= 0) {
          timer.cancel();
          _tokenQR = null;
          // Resetear acompañantes al expirar
          _totalPersonas = 1;
        }
      });
    });
  }

  void _mostrarError(String mensaje) {
    setState(() => _errorMessage = mensaje);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: NothingTheme.error,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    return Scaffold(
      backgroundColor: bg,
      appBar: NothingAppBar(title: 'GENERAR QR'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),

            // ── Card: datos del usuario ──
            if (_usuario != null) ...[
              _buildCardUsuario(dark, prim, sec, div, surf),
              const SizedBox(height: 16),

              // ── Card: acompañantes ──
              _buildCardAcompanantes(dark, prim, sec, div, surf),
              const SizedBox(height: 16),

              // ── Card: resumen de tarifa ──
              _buildCardTarifa(dark, prim, sec, div, surf),
              const SizedBox(height: 24),
            ],

            // ── QR activo ──
            if (_tokenQR != null) ...[
              _buildQRActivo(dark, prim, sec, div, surf),
            ] else ...[
              _buildQRVacio(dark, sec, div),
              const SizedBox(height: 24),
              _buildBotonGenerar(dark),
            ],

            // ── Error ──
            if (_errorMessage != null && _tokenQR == null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NothingTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: NothingTheme.error.withOpacity(0.3), width: 0.5),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      size: 18, color: NothingTheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_errorMessage!,
                      style: TextStyle(fontFamily: 'monospace',
                          fontSize: 11, color: NothingTheme.error))),
                ]),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PASAJERO PRINCIPAL', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: NothingTheme.accentGreen.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                  color: NothingTheme.accentGreen.withOpacity(0.4), width: 0.5),
            ),
            child: Center(child: Text(
              _usuario!.nombre.isNotEmpty
                  ? _usuario!.nombre[0].toUpperCase() : 'U',
              style: TextStyle(fontFamily: 'monospace', fontSize: 18,
                  fontWeight: FontWeight.w900, color: prim),
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_usuario!.nombre} ${_usuario!.apellido}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13,
                    fontWeight: FontWeight.w700, color: prim)),
            const SizedBox(height: 2),
            Row(children: [
              NothingBadge(
                  label: _usuario!.tipoUsuario.toUpperCase(),
                  color: NothingTheme.accentGreen),
              const SizedBox(width: 8),
              Text('CI ${_usuario!.ci}', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9, color: sec)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('SALDO', style: TextStyle(fontFamily: 'monospace',
                fontSize: 8, letterSpacing: 1.5, color: sec)),
            Text(FormateoHelper.formatearMoneda(_usuario!.saldo),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: NothingTheme.accentGreen)),
          ]),
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
              ? NothingTheme.accentOrange.withOpacity(0.5)
              : div,
          width: _cantAcompanantes > 0 ? 1.0 : 0.5,
        ),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.group_outlined,
              size: 16,
              color: _cantAcompanantes > 0
                  ? NothingTheme.accentOrange : sec),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ACOMPAÑANTES', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 2,
                color: _cantAcompanantes > 0
                    ? NothingTheme.accentOrange : sec)),
            const SizedBox(height: 2),
            Text(
              _cantAcompanantes == 0
                  ? 'Solo tú (sin acompañantes)'
                  : '$_cantAcompanantes acompañante${_cantAcompanantes > 1 ? 's' : ''} · Bs 2.50 c/u',
              style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                  color: sec)),
          ])),
        ]),
        const SizedBox(height: 14),

        // Selector visual de personas
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          // Botón -
          GestureDetector(
            onTap: _totalPersonas > 1
                ? () => setState(() { _totalPersonas--; _tokenQR = null; })
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _totalPersonas > 1
                    ? NothingTheme.accentOrange.withOpacity(0.15)
                    : NothingTheme.div(dark).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _totalPersonas > 1
                      ? NothingTheme.accentOrange.withOpacity(0.5)
                      : NothingTheme.div(dark),
                  width: 0.5,
                ),
              ),
              child: Icon(Icons.remove, size: 18,
                  color: _totalPersonas > 1
                      ? NothingTheme.accentOrange : sec.withOpacity(0.3)),
            ),
          ),

          // Íconos de personas
          Expanded(child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final activo = i < _totalPersonas;
              final esAcomp = i > 0;
              return GestureDetector(
                onTap: () => setState(() {
                  _totalPersonas = i + 1;
                  _tokenQR = null;
                }),
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
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        i == 0 ? Icons.person : Icons.person_outline,
                        size: 20,
                        color: activo
                            ? (esAcomp
                                ? NothingTheme.accentOrange
                                : NothingTheme.accentGreen)
                            : sec.withOpacity(0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        i == 0 ? 'YO' : '+${i}',
                        style: TextStyle(
                          fontFamily: 'monospace', fontSize: 7,
                          fontWeight: FontWeight.w700,
                          color: activo
                              ? (esAcomp
                                  ? NothingTheme.accentOrange
                                  : NothingTheme.accentGreen)
                              : sec.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          )),

          // Botón +
          GestureDetector(
            onTap: _totalPersonas < 4
                ? () => setState(() { _totalPersonas++; _tokenQR = null; })
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _totalPersonas < 4
                    ? NothingTheme.accentOrange.withOpacity(0.15)
                    : NothingTheme.div(dark).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _totalPersonas < 4
                      ? NothingTheme.accentOrange.withOpacity(0.5)
                      : NothingTheme.div(dark),
                  width: 0.5,
                ),
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
            child: Row(children: [
              const Icon(Icons.info_outline,
                  size: 12, color: NothingTheme.accentOrange),
              const SizedBox(width: 6),
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

  // ── Card tarifa total ──
  Widget _buildCardTarifa(bool dark, Color prim, Color sec, Color div, Color surf) {
    final tieneDescuento = (_usuario?.descuento ?? 0) > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: div, width: 0.5),
      ),
      child: Column(children: [
        Text('RESUMEN DE COBRO', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 14),

        // Fila: mi pasaje
        _FilaTarifa(
          label: 'Mi pasaje (${_usuario?.tipoUsuario ?? ''})',
          valor: FormateoHelper.formatearMoneda(_tarifaPropia),
          color: NothingTheme.accentGreen,
          dark: dark,
        ),

        // Filas acompañantes
        if (_cantAcompanantes > 0) ...[
          const SizedBox(height: 6),
          _FilaTarifa(
            label: '$_cantAcompanantes acompañante${_cantAcompanantes > 1 ? 's' : ''} × Bs 2.50',
            valor: FormateoHelper.formatearMoneda(_tarifaAcompanantes),
            color: NothingTheme.accentOrange,
            dark: dark,
          ),
        ],

        Divider(color: div, height: 20),

        // Total
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('TOTAL A DESCONTAR', style: TextStyle(
              fontFamily: 'monospace', fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1,
              color: prim)),
          Text(FormateoHelper.formatearMoneda(_totalACobrar),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: NothingTheme.accentGreen)),
        ]),

        if (tieneDescuento && _cantAcompanantes == 0) ...[
          const SizedBox(height: 6),
          Text(
            'Ahorras ${FormateoHelper.formatearMoneda(TarifasHelper.tarifaBase - _tarifaPropia)} con tu descuento',
            style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                color: NothingTheme.accentOrange),
          ),
        ],

        // Advertencia saldo insuficiente
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
              const Icon(Icons.warning_amber_outlined,
                  size: 12, color: NothingTheme.error),
              const SizedBox(width: 6),
              Text('Saldo insuficiente para ${_totalPersonas} persona${_totalPersonas > 1 ? 's' : ''}',
                  style: const TextStyle(fontFamily: 'monospace',
                      fontSize: 9, color: NothingTheme.error)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── QR activo ──
  Widget _buildQRActivo(bool dark, Color prim, Color sec, Color div, Color surf) {
    final urgente = _segundosRestantes <= 10;
    return Column(children: [
      // QR
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: NothingTheme.accentGreen.withOpacity(0.25),
            blurRadius: 24, spreadRadius: 2,
          )],
        ),
        child: Column(children: [
          QrImageView(
            data: _tokenQR!,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
          ),
          if (_totalPersonas > 1) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: NothingTheme.accentOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_totalPersonas PERSONAS · ${FormateoHelper.formatearMoneda(_totalACobrar)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: NothingTheme.accentOrange),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 16),

      // Timer
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: urgente
              ? NothingTheme.error.withOpacity(0.1)
              : surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: urgente ? NothingTheme.error : div,
              width: 0.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.timer_outlined, size: 20,
              color: urgente ? NothingTheme.error : NothingTheme.accentOrange),
          const SizedBox(width: 10),
          Text('VÁLIDO POR: ${_segundosRestantes}s',
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: urgente ? NothingTheme.error : prim)),
        ]),
      ),
      const SizedBox(height: 12),

      // Instrucción
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: div, width: 0.5),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline,
              size: 16, color: NothingTheme.accentBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(
            'Muestra este QR al validador en el vehículo. '
            'Cubre ${_totalPersonas == 1 ? 'tu pasaje' : '$_totalPersonas pasajes'}.',
            style: TextStyle(fontFamily: 'monospace',
                fontSize: 10, color: sec))),
        ]),
      ),
      const SizedBox(height: 16),

      // Botón nuevo QR
      SizedBox(width: double.infinity,
        child: GestureDetector(
          onTap: _generarQR,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: NothingTheme.accentPurple.withOpacity(0.5),
                  width: 0.5),
            ),
            child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.refresh, size: 15,
                  color: NothingTheme.accentPurple),
              const SizedBox(width: 6),
              const Text('GENERAR NUEVO QR', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.5,
                  color: NothingTheme.accentPurple)),
            ])),
          ),
        )),
    ]);
  }

  // ── QR vacío ──
  Widget _buildQRVacio(bool dark, Color sec, Color div) {
    return Container(
      height: 180, width: double.infinity,
      decoration: BoxDecoration(
        color: NothingTheme.surf(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: div, width: 0.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.qr_code_2_outlined, size: 56, color: sec.withOpacity(0.4)),
        const SizedBox(height: 12),
        Text('NO HAY QR ACTIVO', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 2.5, color: sec)),
        const SizedBox(height: 4),
        Text(
          _totalPersonas == 1
              ? 'Genera un código para tu viaje'
              : 'Genera un código para $_totalPersonas personas',
          style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: sec)),
      ]),
    );
  }

  // ── Botón generar ──
  Widget _buildBotonGenerar(bool dark) {
    final saldoOk = _usuario == null || _usuario!.saldo >= _totalACobrar;
    return SizedBox(width: double.infinity,
      child: GestureDetector(
        onTap: (_cargando || !saldoOk) ? null : _generarQR,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: saldoOk
                ? NothingTheme.accentGreen
                : NothingTheme.accentGreen.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: _cargando
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.qr_code, size: 18, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(
                    _totalPersonas == 1
                        ? 'GENERAR QR'
                        : 'GENERAR QR · $_totalPersonas PERSONAS',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12,
                        fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        color: Colors.black),
                  ),
                ])),
        ),
      ));
  }
}

// ── Widget fila tarifa ──
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
