class Recarga {
  final String id;
  final String usuarioCi;
  final double monto;
  final DateTime fecha;
  final String metodo; // 'paypal', 'tarjeta', 'otro'
  final String transaccionId; // ID de PayPal o banco
  final String estado; // 'pendiente', 'completada', 'fallida', 'cancelada'
  final String? comprobante;
  final String? observaciones;

  Recarga({
    required this.id,
    required this.usuarioCi,
    required this.monto,
    required this.fecha,
    required this.metodo,
    required this.transaccionId,
    required this.estado,
    this.comprobante,
    this.observaciones,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'usuarioCi': usuarioCi,
      'monto': monto,
      'fecha': fecha.toIso8601String(),
      'metodo': metodo,
      'transaccionId': transaccionId,
      'estado': estado,
      'comprobante': comprobante,
      'observaciones': observaciones,
    };
  }

  factory Recarga.fromJson(Map<String, dynamic> json) {
    return Recarga(
      id: json['id'] as String,
      usuarioCi: json['usuarioCi'] as String,
      monto: (json['monto'] as num).toDouble(),
      fecha: DateTime.parse(json['fecha'] as String),
      metodo: json['metodo'] as String,
      transaccionId: json['transaccionId'] as String,
      estado: json['estado'] as String? ?? 'pendiente',
      comprobante: json['comprobante'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }
}
