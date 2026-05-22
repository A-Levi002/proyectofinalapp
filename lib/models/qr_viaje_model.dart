class QRViaje {
  final String usuarioCi;
  final String tipoUsuario;
  final double tarifaAplicada;
  final double saldoRestante;
  final DateTime timestamp;
  final String sessionId; // Para invalidar QRs después de 30s

  QRViaje({
    required this.usuarioCi,
    required this.tipoUsuario,
    required this.tarifaAplicada,
    required this.saldoRestante,
    required this.timestamp,
    required this.sessionId,
  });

  // Verificar si el QR aún es válido (máximo 30 segundos)
  bool get esValido {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(timestamp).inSeconds;
    return diferencia <= 30;
  }

  // Convertir a JSON para codificar en el QR
  String toJsonString() {
    return '$usuarioCi|$tipoUsuario|$tarifaAplicada|$saldoRestante|${timestamp.millisecondsSinceEpoch}|$sessionId';
  }

  // Parsear desde string del QR
  static QRViaje? fromString(String data) {
    try {
      final partes = data.split('|');
      if (partes.length != 6) return null;

      return QRViaje(
        usuarioCi: partes[0],
        tipoUsuario: partes[1],
        tarifaAplicada: double.parse(partes[2]),
        saldoRestante: double.parse(partes[3]),
        timestamp: DateTime.fromMillisecondsSinceEpoch(int.parse(partes[4])),
        sessionId: partes[5],
      );
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    return 'QRViaje(ci: $usuarioCi, tarifa: $tarifaAplicada, esValido: $esValido)';
  }
}
