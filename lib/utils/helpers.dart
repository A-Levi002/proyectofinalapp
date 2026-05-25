class TarifasHelper {
  static const double tarifaBase = 2.50; // Bs 2.50

  static const Map<String, double> descuentosPorTipo = {
    'estudiante': 0.50, // 50%
    'adultomayor': 0.30, // 30%
    'discapacidad': 1.00, // 100% (gratuito)
    'general': 0.00, // 0%
  };

  static double calcularTarifa({
    required String tipoUsuario,
    double? tarifaBaseCustom,
  }) {
    final tarifa = tarifaBaseCustom ?? tarifaBase;
    final descuento = descuentosPorTipo[tipoUsuario.toLowerCase()] ?? 0.0;
    final montoDescuento = tarifa * descuento;
    return tarifa - montoDescuento;
  }

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

  static bool tieneSaldoSuficiente({
    required double saldoActual,
    required String tipoUsuario,
  }) {
    final tarifaRequerida = calcularTarifa(tipoUsuario: tipoUsuario);
    if (tarifaRequerida == 0.0) return true;
    return saldoActual >= tarifaRequerida;
  }

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

  static bool esValidoTipoUsuario(String tipo) {
    return descuentosPorTipo.containsKey(tipo.toLowerCase());
  }
}

class ValidatorsHelper {
  /// Acepta dominios universitarios bolivianos reales
  static bool esEmailUniversitario(String email) {
    final emailLower = email.toLowerCase();

    // Dominio generado automáticamente por la app
    if (emailLower.endsWith('@univ.edu.bo')) return true;

    // Lista ampliada con UPDS y otras universidades bolivianas
    final dominiosValidos = [
      '@estudiante.univ.edu.bo',
      '@upds.edu.bo',           // Universidad Privada Domingo Savio
      '@est.upds.edu.bo',       // subdominio estudiantes UPDS
      '@umsa.bo',               // UMSA
      '@umss.edu.bo',           // UMSS Cochabamba
      '@est.umss.edu.bo',
      '@ucb.edu.bo',            // UCB
      '@estudiante.ucb.edu.bo',
      '@uab.edu.bo',            // UAB
      '@ujms.edu.bo',           // UJMS
      '@unifranz.edu.bo',       // UNIFRANZ
      '@uagrm.edu.bo',          // UAGRM
      '@udabol.edu.bo',         // UDABOL
      '@uatf.edu.bo',           // UATF
      '@univ.edu.bo',
    ];

    return dominiosValidos.any((dominio) => emailLower.endsWith(dominio));
  }

  static bool esEmailValido(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  static bool esValidoCI(String ci) {
    final limpio = ci.replaceAll(RegExp(r'[^0-9]'), '');
    return limpio.length >= 7 && limpio.length <= 10;
  }

  static bool esValidoPIN(String pin) {
    final limpio = pin.replaceAll(RegExp(r'[^0-9]'), '');
    return limpio.length == 4;
  }

  static bool esValidoTelefono(String telefono) {
    final limpio = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    return limpio.length == 8 || limpio.length == 10 || limpio.length == 12;
  }

  static bool tieneEdadMinima(DateTime fechaNacimiento, int edadMinima) {
    final hoy = DateTime.now();
    int edad = hoy.year - fechaNacimiento.year;
    if (hoy.month < fechaNacimiento.month ||
        (hoy.month == fechaNacimiento.month && hoy.day < fechaNacimiento.day)) {
      edad--;
    }
    return edad >= edadMinima;
  }

  static bool esValidoNombre(String nombre) {
    return nombre.isNotEmpty &&
        nombre.length >= 2 &&
        !RegExp(r'[0-9]').hasMatch(nombre);
  }
}

class FormateoHelper {
  static String formatearCI(String ci) => ci.toUpperCase();

  static String formatearMoneda(double monto) =>
      'Bs. ${monto.toStringAsFixed(2)}';

  static String formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'No registrada';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  static String formatearFechaHora(DateTime? fecha) {
    if (fecha == null) return 'No registrada';
    return '${formatearFecha(fecha)} '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
  }

  static String formatearTelefono(String telefono) {
    final limpio = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpio.length == 8) {
      return '${limpio.substring(0, 4)}-${limpio.substring(4)}';
    }
    return limpio;
  }
}
