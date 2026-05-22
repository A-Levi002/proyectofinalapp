import 'dart:convert';

class CIExtractorService {
  /// Extrae datos del QR del Carnet de Identidad Boliviano
  /// Soporta múltiples formatos reales:
  ///
  /// FORMATOS SOPORTADOS:
  /// 1. "CI;1234567;GARCIA;JUAN;01011990" (formato estándar)
  /// 2. "CI;1234567 LP;GARCIA PEREZ;JUAN CARLOS;01/01/1990"
  /// 3. "1234567;GARCIA;PEREZ;JUAN CARLOS;01011990;correo@ejemplo.com"
  /// 4. "1234567;GARCIA PEREZ;JUAN CARLOS;01011990"
  /// 5. Formato JSON: {"ci":"1234567","nombre":"Juan","apellido":"Garcia"}
  /// 6. Formato texto plano con espacios
  ///
  /// Para estudiantes, genera email automático basado en CI y nombre
  static Map<String, dynamic>? extraerDatosCI(
    String qrContent, {
    String tipoUsuario = 'general',
  }) {
    if (qrContent.isEmpty) return null;

    try {
      // Limpiar el contenido (espacios extras, saltos de línea)
      final limpio = qrContent.trim().replaceAll(RegExp(r'\s+'), ' ');

      // Caso 1: Formato JSON
      if (limpio.startsWith('{') && limpio.endsWith('}')) {
        return _extraerDesdeJson(limpio, tipoUsuario);
      }

      // Caso 2: Formato con prefijo "CI;"
      if (limpio.toUpperCase().startsWith('CI;')) {
        return _extraerDesdeFormatoCI(limpio, tipoUsuario);
      }

      // Caso 3: Formato separado por punto y coma
      if (limpio.contains(';')) {
        return _extraerDesdePuntoYComa(limpio, tipoUsuario);
      }

      // Caso 4: Formato separado por espacios
      if (limpio.contains(' ')) {
        return _extraerDesdeEspacios(limpio, tipoUsuario);
      }

      // Caso 5: Solo números (solo CI)
      if (RegExp(r'^\d{7,10}$').hasMatch(limpio)) {
        return {
          'ci': limpio,
          'ciFull': limpio,
          'nombre': '',
          'apellido': '',
          'fechaNacimiento': null,
          'email': tipoUsuario == 'estudiante'
              ? _generarEmailEstudiante(limpio, '', '')
              : null,
          'email_generado': tipoUsuario == 'estudiante',
        };
      }

      return null;
    } catch (e) {
      print('Error extrayendo datos del CI: $e');
      return null;
    }
  }

  /// Extraer desde formato JSON
  static Map<String, dynamic>? _extraerDesdeJson(String jsonStr, String tipoUsuario) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final ci = data['ci']?.toString() ?? data['carnet']?.toString() ?? '';
      final nombre = data['nombre']?.toString() ?? '';
      final apellido = data['apellido']?.toString() ?? data['apellidos']?.toString() ?? '';
      String? email = data['email']?.toString();

      if (ci.isEmpty) return null;

      return _construirResultado(
        ci: ci,
        nombre: nombre,
        apellido: apellido,
        email: email,
        fechaStr: data['fechaNacimiento']?.toString(),
        tipoUsuario: tipoUsuario,
      );
    } catch (e) {
      return null;
    }
  }

  /// Extraer desde formato con prefijo "CI;"
  static Map<String, dynamic>? _extraerDesdeFormatoCI(String texto, String tipoUsuario) {
    // Eliminar el prefijo "CI;" y "ci;"
    String sinPrefijo = texto;
    if (sinPrefijo.toUpperCase().startsWith('CI;')) {
      sinPrefijo = sinPrefijo.substring(3);
    }

    final partes = sinPrefijo.split(';').map((p) => p.trim()).toList();

    if (partes.length < 3) return null;

    // Formato: CI;1234567;APELLIDO;NOMBRE;FECHA;EMAIL
    // indices:    0      1        2        3       4      5
    final ci = partes[0];
    final apellido = partes.length > 1 ? partes[1] : '';
    final nombre = partes.length > 2 ? partes[2] : '';
    final fechaStr = partes.length > 3 ? partes[3] : null;
    final email = partes.length > 4 && partes[4].contains('@') ? partes[4] : null;

    return _construirResultado(
      ci: ci,
      nombre: nombre,
      apellido: apellido,
      email: email,
      fechaStr: fechaStr,
      tipoUsuario: tipoUsuario,
    );
  }

  /// Extraer desde formato separado por punto y coma
  static Map<String, dynamic>? _extraerDesdePuntoYComa(String texto, String tipoUsuario) {
    final partes = texto.split(';').map((p) => p.trim()).toList();

    if (partes.isEmpty) return null;

    // Buscar el CI (primer elemento que parece CI)
    String? ci;
    int ciIndex = -1;

    for (int i = 0; i < partes.length; i++) {
      final parte = partes[i];
      if (_esCI(parte)) {
        ci = _limpiarCI(parte);
        ciIndex = i;
        break;
      }
    }

    if (ci == null) return null;

    // Intentar identificar nombre y apellido
    String nombre = '';
    String apellido = '';
    String? email;
    String? fechaStr;

    // Buscar email (contiene @)
    for (final parte in partes) {
      if (parte.contains('@') && !parte.contains('http')) {
        email = parte;
        break;
      }
    }

    // Buscar fecha (contiene números con formato fecha)
    for (final parte in partes) {
      if (_esFecha(parte)) {
        fechaStr = parte;
        break;
      }
    }

    // El resto de partes podrían ser nombre y apellido
    final resto = <String>[];
    for (int i = 0; i < partes.length; i++) {
      if (i != ciIndex && partes[i] != email && !_esFecha(partes[i])) {
        resto.add(partes[i]);
      }
    }

    if (resto.isNotEmpty) {
      if (resto.length == 1) {
        // Puede ser nombre completo o apellido
        if (resto[0].split(' ').length > 1) {
          nombre = resto[0];
        } else {
          apellido = resto[0];
        }
      } else if (resto.length >= 2) {
        // Asumir que el último es nombre y los anteriores apellido
        nombre = resto.last;
        apellido = resto.sublist(0, resto.length - 1).join(' ');
      }
    }

    return _construirResultado(
      ci: ci,
      nombre: nombre,
      apellido: apellido,
      email: email,
      fechaStr: fechaStr,
      tipoUsuario: tipoUsuario,
    );
  }

  /// Extraer desde formato separado por espacios
  static Map<String, dynamic>? _extraerDesdeEspacios(String texto, String tipoUsuario) {
    final partes = texto.split(' ').map((p) => p.trim()).toList();

    if (partes.isEmpty) return null;

    // Buscar CI
    String? ci;
    for (final parte in partes) {
      if (_esCI(parte)) {
        ci = _limpiarCI(parte);
        break;
      }
    }

    if (ci == null) return null;

    // Buscar email
    String? email;
    for (final parte in partes) {
      if (parte.contains('@')) {
        email = parte;
        break;
      }
    }

    // Buscar fecha
    String? fechaStr;
    for (final parte in partes) {
      if (_esFecha(parte)) {
        fechaStr = parte;
        break;
      }
    }

    // El resto podría ser nombre y apellido
    final resto = <String>[];
    for (final parte in partes) {
      if (parte != ci && parte != email && !_esFecha(parte) && parte.length > 2) {
        resto.add(parte);
      }
    }

    String nombre = '';
    String apellido = '';

    if (resto.isNotEmpty) {
      if (resto.length == 1) {
        nombre = resto[0];
      } else if (resto.length >= 2) {
        nombre = resto.last;
        apellido = resto.sublist(0, resto.length - 1).join(' ');
      }
    }

    return _construirResultado(
      ci: ci,
      nombre: nombre,
      apellido: apellido,
      email: email,
      fechaStr: fechaStr,
      tipoUsuario: tipoUsuario,
    );
  }

  /// Construir resultado final con validaciones
  static Map<String, dynamic> _construirResultado({
    required String ci,
    required String nombre,
    required String apellido,
    String? email,
    String? fechaStr,
    required String tipoUsuario,
  }) {
    // Limpiar CI
    final ciLimpio = _limpiarCI(ci);
    final ciFull = ci.contains(RegExp(r'[A-Za-z]')) ? ci : ciLimpio;

    // Procesar fecha
    DateTime? fechaNacimiento;
    if (fechaStr != null && fechaStr.isNotEmpty) {
      fechaNacimiento = _parsearFecha(fechaStr);
    }

    // Procesar email
    String? emailFinal;
    bool emailGenerado = false;

    if (tipoUsuario == 'estudiante') {
      if (email != null && email.isNotEmpty && _esEmailValido(email)) {
        emailFinal = email.toLowerCase();
      } else {
        // Generar email automático
        emailFinal = _generarEmailEstudiante(ciLimpio, nombre, apellido);
        emailGenerado = true;
      }
    } else {
      emailFinal = (email != null && email.isNotEmpty && _esEmailValido(email))
          ? email.toLowerCase()
          : null;
    }

    return {
      'ci': ciLimpio,
      'ciFull': ciFull,
      'nombre': _capitalizar(nombre),
      'apellido': _capitalizar(apellido),
      'fechaNacimiento': fechaNacimiento,
      'email': emailFinal,
      'email_generado': emailGenerado,
    };
  }

  /// Validar si una cadena parece un CI
  static bool _esCI(String texto) {
    final numeros = texto.replaceAll(RegExp(r'[^0-9]'), '');
    return numeros.length >= 7 && numeros.length <= 10;
  }

  /// Limpiar CI (solo números)
  static String _limpiarCI(String ci) {
    return ci.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Validar si una cadena parece una fecha
  static bool _esFecha(String texto) {
    // Busca patrones de fecha: DDMMYYYY, DD/MM/YYYY, DD-MM-YYYY
    final patrones = [
      RegExp(r'^\d{2}\d{2}\d{4}$'),     // DDMMYYYY
      RegExp(r'^\d{2}[-/]\d{2}[-/]\d{4}$'), // DD/MM/YYYY
      RegExp(r'^\d{4}[-/]\d{2}[-/]\d{2}$'), // YYYY-MM-DD
    ];
    return patrones.any((p) => p.hasMatch(texto));
  }

  /// Validar email
  static bool _esEmailValido(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return regex.hasMatch(email);
  }

  /// Parsear fecha desde múltiples formatos
  static DateTime? _parsearFecha(String fechaStr) {
    try {
      String limpio = fechaStr.trim();

      // Formato DDMMYYYY
      if (RegExp(r'^\d{8}$').hasMatch(limpio)) {
        final dia = int.parse(limpio.substring(0, 2));
        final mes = int.parse(limpio.substring(2, 4));
        final anio = int.parse(limpio.substring(4, 8));
        if (_fechaValida(anio, mes, dia)) {
          return DateTime(anio, mes, dia);
        }
      }

      // Formato DD/MM/YYYY o DD-MM-YYYY
      if (limpio.contains('/') || limpio.contains('-')) {
        final separador = limpio.contains('/') ? '/' : '-';
        final partes = limpio.split(separador);
        if (partes.length == 3) {
          final dia = int.parse(partes[0]);
          final mes = int.parse(partes[1]);
          final anio = int.parse(partes[2]);
          if (_fechaValida(anio, mes, dia)) {
            return DateTime(anio, mes, dia);
          }
        }
      }

      // Formato YYYY-MM-DD
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(limpio)) {
        return DateTime.parse(limpio);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static bool _fechaValida(int anio, int mes, int dia) {
    if (anio < 1900 || anio > DateTime.now().year) return false;
    if (mes < 1 || mes > 12) return false;
    if (dia < 1 || dia > 31) return false;
    return true;
  }

  /// Generar email automático para estudiantes
  static String _generarEmailEstudiante(String ci, String nombre, String apellido) {
    try {
      final ciLimpio = ci.replaceAll(RegExp(r'[^0-9]'), '');

      String nombreProcesado = nombre
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '.');

      if (nombreProcesado.isEmpty) nombreProcesado = 'estudiante';

      String apellidoProcesado = apellido
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), '.')
          .split('.')
          .first; // Solo primer apellido

      String email;
      if (apellidoProcesado.isNotEmpty && apellidoProcesado != nombreProcesado) {
        email = '$nombreProcesado.$apellidoProcesado.$ciLimpio@univ.edu.bo';
      } else {
        email = '$nombreProcesado.$ciLimpio@univ.edu.bo';
      }

      // Limpiar dobles puntos
      email = email.replaceAll(RegExp(r'\.{2,}'), '.');
      // Limpiar puntos al inicio o final
      email = email.replaceAll(RegExp(r'^\.|\.$'), '');

      return email;
    } catch (e) {
      return 'estudiante.${ci.replaceAll(RegExp(r'[^0-9]'), '')}@univ.edu.bo';
    }
  }

  /// Capitalizar nombre/apellido
  static String _capitalizar(String texto) {
    if (texto.isEmpty) return '';
    return texto.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Validar estructura de CI
  static bool validarEstructuraCI(String ci) {
    final limpio = ci.replaceAll(RegExp(r'[^0-9]'), '');
    return limpio.length >= 7 && limpio.length <= 10;
  }

  /// Extraer solo números del CI
  static String extraerCILimpio(String ciConComplemento) {
    return ciConComplemento.replaceAll(RegExp(r'[^0-9]'), '');
  }
}