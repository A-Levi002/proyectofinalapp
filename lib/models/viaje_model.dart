class Viaje {
  final String id;
  final String usuarioCi;
  final DateTime fecha;
  final double montoOriginal;
  final double montoDescuento;
  final double montoFinal;
  final String tipoUsuario;
  final String? origen;
  final String? destino;
  final String? qrGenerado;
  final bool qrEscaneado;
  final String estado;
  final String? observaciones;
  final int cantidadPersonas;

  Viaje({
    required this.id,
    required this.usuarioCi,
    required this.fecha,
    required this.montoOriginal,
    required this.montoDescuento,
    required this.montoFinal,
    required this.tipoUsuario,
    this.origen,
    this.destino,
    this.qrGenerado,
    this.qrEscaneado = false,
    required this.estado,
    this.observaciones,
    this.cantidadPersonas = 1,
  });

  factory Viaje.fromJson(Map<String, dynamic> json) {
    String? parseStr(String snake, [String? camel]) =>
        json[snake] as String? ?? (camel != null ? json[camel] as String? : null);

    DateTime parseDate(String snake, [String? camel]) {
      final raw = parseStr(snake, camel);
      if (raw != null) try { return DateTime.parse(raw); } catch (_) {}
      return DateTime.now();
    }

    return Viaje(
      id:               parseStr('id') ?? '',
      usuarioCi:        parseStr('usuario_ci', 'usuarioCi') ?? '',
      fecha:            parseDate('fecha'),
      montoOriginal:    (json['monto_original']  ?? json['montoOriginal']  ?? 0).toDouble(),
      montoDescuento:   (json['monto_descuento'] ?? json['montoDescuento'] ?? 0).toDouble(),
      montoFinal:       (json['monto_final']     ?? json['montoFinal']     ?? 0).toDouble(),
      tipoUsuario:      parseStr('tipo_usuario', 'tipoUsuario') ?? 'general',
      origen:           parseStr('origen'),
      destino:          parseStr('destino'),
      qrGenerado:       parseStr('qr_generado', 'qrGenerado'),
      qrEscaneado:      (json['qr_escaneado'] ?? json['qrEscaneado'] ?? false) as bool,
      estado:           parseStr('estado') ?? 'pendiente',
      observaciones:    parseStr('observaciones'),
      cantidadPersonas: (json['cantidad_personas'] ?? json['cantidadPersonas'] ?? 1) as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'usuario_ci':       usuarioCi,
    'fecha':            fecha.toIso8601String(),
    'monto_original':   montoOriginal,
    'monto_descuento':  montoDescuento,
    'monto_final':      montoFinal,
    'tipo_usuario':     tipoUsuario,
    'origen':           origen,
    'destino':          destino,
    'qr_generado':      qrGenerado,
    'qr_escaneado':     qrEscaneado,
    'estado':           estado,
    'observaciones':    observaciones,
    'cantidad_personas': cantidadPersonas,
  };
}
