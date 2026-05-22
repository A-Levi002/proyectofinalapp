import 'package:qr_flutter/qr_flutter.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

class QRService {
  /// Generar QR de viaje en formato PNG
  /// Data: "usuarioCi|tipoUsuario|tarifaAplicada|saldoRestante|timestamp|sessionId"
  static Future<Uint8List?> generarQRViaje({
    required String usuarioCi,
    required String tipoUsuario,
    required double tarifaAplicada,
    required double saldoRestante,
    required int timestamp,
    required String sessionId,
  }) async {
    try {
      final data = '$usuarioCi|$tipoUsuario|$tarifaAplicada|$saldoRestante|$timestamp|$sessionId';

      final qrPainter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: false,
        emptyColor: const ui.Color(0xffffffff),
        color: const ui.Color(0xff000000),
      );

      final image = await qrPainter.toImage(200); // 200x200 px
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Error generando QR: $e');
      return null;
    }
  }

  /// Crear QR rápido (sin captura de imagen)
  static String obtenerDatosQRViaje({
    required String usuarioCi,
    required String tipoUsuario,
    required double tarifaAplicada,
    required double saldoRestante,
    required int timestamp,
    required String sessionId,
  }) {
    return '$usuarioCi|$tipoUsuario|$tarifaAplicada|$saldoRestante|$timestamp|$sessionId';
  }

  /// Validar e interpretador datos del QR
  static Map<String, dynamic>? parsearQRViaje(String qrString) {
    try {
      final partes = qrString.split('|');
      if (partes.length != 6) return null;

      final timestamp = int.parse(partes[4]);
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final diferencia = (ahora - timestamp) ~/ 1000; // Segundos

      if (diferencia > 30) {
        return {
          'valido': false,
          'razon': 'QR expirado',
        };
      }

      return {
        'valido': true,
        'usuarioCi': partes[0],
        'tipoUsuario': partes[1],
        'tarifaAplicada': double.parse(partes[2]),
        'saldoRestante': double.parse(partes[3]),
        'timestamp': timestamp,
        'sessionId': partes[5],
        'segundosRestantes': 30 - diferencia,
      };
    } catch (e) {
      return {
        'valido': false,
        'razon': 'Error parseando QR: $e',
      };
    }
  }
}
