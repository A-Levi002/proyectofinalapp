class TarifasHelper {
  static const double tarifaBase = 2.50; // Bs 2.50

  static const Map<String, double> descuentosPorTipo = {
    'estudiante': 0.50, // 50%
    'adultomayor': 0.30, // 30%
    'discapacidad': 1.00, // 100% (gratuito)
    'general': 0.00, // 0%
  };

  /// Calcular tarifa final según tipo de usuario y descuento
  static double calcularTarifa({
    required String tipoUsuario,
    double? tarifaBaseCustom,
  }) {
    final tarifa = tarifaBaseCustom ?? tarifaBase;
    final descuento = descuentosPorTipo[tipoUsuario.toLowerCase()] ?? 0.0;
    final montoDescuento = tarifa * descuento;
    return tarifa - montoDescuento;
  }

  /// Desglose de la tarifa
  static Map<String, dynamic> desgloseTarifa({
    required String tipoUsuario,
    double? tarifaBaseCustom,
  }) {
    final tarifa = tarifaBaseCustom ?? tarifaBase;
    final descuento = descuentosPorTipo[tipoUsuario.toLowerCase()] ?? 0.0;
    final montoDescuento = tarifa * descuento;
    final tarifaFinal = tarifa - montoDescuento;

    return {
      'tarifaBase': tarifa,
      'porcentajeDescuento': (descuento * 100).toInt(),
      'montoDescuento': montoDescuento,
      'tarifaFinal': tarifaFinal,
      'tipoUsuario': tipoUsuario,
      'esGratuito': tarifaFinal == 0.0,
    };
  }

  /// Validar si hay saldo suficiente
  static bool tieneSaldoSuficiente({
    required double saldoActual,
    required String tipoUsuario,
  }) {
    final tarifaRequerida = calcularTarifa(tipoUsuario: tipoUsuario);
    // Para usuarios con tarifa 0 (discapacidad), siempre hay saldo suficiente
    if (tarifaRequerida == 0.0) return true;
    return saldoActual >= tarifaRequerida;
  }

  /// Obtener descripción del tipo de usuario
  static String obtenerDescripcion(String tipoUsuario) {
    switch (tipoUsuario.toLowerCase()) {
      case 'estudiante':
        return 'Estudiante (50% descuento)';
      case 'adultomayor':
        return 'Adulto Mayor (30% descuento)';
      case 'discapacidad':
        return 'Persona con Discapacidad (Gratuito)';
      case 'general':
        return 'Usuario General (Sin descuento)';
      default:
        return tipoUsuario;
    }
  }

  /// Validar si el tipo de usuario es válido
  static bool esValidoTipoUsuario(String tipo) {
    return descuentosPorTipo.containsKey(tipo.toLowerCase());
  }
}

class ValidatorsHelper {
  /// Validar formato de email universitario
  /// Acepta:
  /// - Emails generados automáticamente: ...@univ.edu.bo
  /// - Dominios universitarios específicos de Bolivia y Perú
  static bool esEmailUniversitario(String email) {
    final emailLower = email.toLowerCase();

    // Dominios generados automáticamente por nuestra app
    if (emailLower.endsWith('@univ.edu.bo')) {
      return true;
    }

    // Lista de dominios universitarios conocidos
    final dominiosValidos = [
      '@estudiante.univ.edu.bo',
      '@umsa.bo',
      '@upds.edu.bo',
      '@ucb.edu.bo',
      '@umsm.edu.pe',
      '@uni.edu.pe',
      '@univ.edu.bo', //Dominio genérico
    ];

    return dominiosValidos.any((dominio) => emailLower.endsWith(dominio));
  }

  /// Verifica si un email es válido en formato general
  static bool esEmailValido(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  /// Validar CI boliviano básico
  static bool esValidoCI(String ci) {
    final limpio = ci.replaceAll(RegExp(r'[^0-9]'), '');
    // Un CI boliviano tiene entre 7 y 10 dígitos
    return limpio.length >= 7 && limpio.length <= 10;
  }

  /// Validar PIN (4 dígitos)
  static bool esValidoPIN(String pin) {
    final limpio = pin.replaceAll(RegExp(r'[^0-9]'), '');
    return limpio.length == 4;
  }

  /// Validar número de teléfono boliviano
  static bool esValidoTelefono(String telefono) {
    final limpio = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    // Bolivia: típicamente 8 dígitos
    return limpio.length == 8 || limpio.length == 10 || limpio.length == 12;
  }

  /// Validar edad mínima
  static bool tieneEdadMinima(DateTime fechaNacimiento, int edadMinima) {
    final hoy = DateTime.now();
    int edad = hoy.year - fechaNacimiento.year;
    if (hoy.month < fechaNacimiento.month ||
        (hoy.month == fechaNacimiento.month && hoy.day < fechaNacimiento.day)) {
      edad--;
    }
    return edad >= edadMinima;
  }

  /// Validar nombre (sin números, sin caracteres especiales)
  static bool esValidoNombre(String nombre) {
    return nombre.isNotEmpty &&
        nombre.length >= 2 &&
        !RegExp(r'[0-9]').hasMatch(nombre);
  }
}

class FormateoHelper {
  /// Formatear CI para mostrar (ej: "1234567CP")
  static String formatearCI(String ci) {
    return ci.toUpperCase();
  }

  /// Formatear moneda boliviana
  static String formatearMoneda(double monto) {
    return 'Bs. ${monto.toStringAsFixed(2)}';
  }

  /// Formatear fecha (ej: "13/05/2026")
  static String formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'No registrada';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  /// Formatear fecha y hora
  static String formatearFechaHora(DateTime? fecha) {
    if (fecha == null) return 'No registrada';
    return '${formatearFecha(fecha)} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  /// Formatear teléfono (ej: "67123456" → "6712-3456")
  static String formatearTelefono(String telefono) {
    final limpio = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpio.length == 8) {
      return '${limpio.substring(0, 4)}-${limpio.substring(4)}';
    }
    return limpio;
  }
}
