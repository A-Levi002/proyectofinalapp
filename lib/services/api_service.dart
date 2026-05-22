import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/usuario_model.dart';
import 'storage_service.dart';

class ApiService {
  // REEMPLAZA CON TU IP DEL BACKEND
  static const String baseUrl = 'http://192.168.1.100:8000/api';
  // Para pruebas locales: http://localhost:8000/api
  // Para servidor remoto: http://tu-servidor.com/api

  final StorageService storageService;
  late String? _token;

  ApiService(this.storageService) {
    _token = storageService.obtenerToken();
  }

  // ============ HEADER CON AUTENTICACIÓN ============
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // ============ VERIFICAR SI CI YA EXISTE ============
  /// Antes de registrar, verifica si el CI ya tiene cuenta
  Future<bool> ciYaExiste(String ci) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/verificar-ci/$ci'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['existe'] == true;
      }
      return false;
    } catch (e) {
      print('Error verificando CI: $e');
      return false;
    }
  }

  // ============ REGISTRO ============
  /// Crear nueva cuenta (solo si CI no existe)
  Future<Map<String, dynamic>> registrarUsuario({
    required String ci,
    required String nombre,
    required String apellido,
    required String email,
    required String telefono,
    required String tipoUsuario,
    required DateTime fechaNacimiento,
    required String pin,
  }) async {
    try {
      // Primero verifica si el CI ya existe
      final existe = await ciYaExiste(ci);
      if (existe) {
        return {
          'exito': false,
          'mensaje': 'Este CI ya tiene una cuenta registrada. No se pueden crear múltiples cuentas por usuario.',
          'codigo': 'CI_DUPLICADO',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/auth/registro'),
        headers: _headers,
         body: jsonEncode({
           'ci': ci,
           'nombre': nombre,
           'apellido': apellido,
           'email': email,
           'telefono': telefono,
           'tipoUsuario': tipoUsuario,
           'fechaNacimiento': fechaNacimiento.toIso8601String(),
           'pin': pin,
         }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        await storageService.guardarToken(_token!);
        return {
          'exito': true,
          'usuario': UsuarioModel.fromJson(data['usuario']),
          'token': _token,
        };
      } else if (response.statusCode == 409) {
        return {
          'exito': false,
          'mensaje': 'CI ya registrado en el sistema',
          'codigo': 'CI_DUPLICADO',
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error en el registro: ${response.body}',
          'codigo': 'ERROR_REGISTRO',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error de conexión: $e',
        'codigo': 'ERROR_CONEXION',
      };
    }
  }

  // ============ LOGIN ============
  Future<Map<String, dynamic>> login({
    required String ci,
    required String pin, // PIN de 4 dígitos
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'ci': ci,
          'pin': pin,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        await storageService.guardarToken(_token!);
        return {
          'exito': true,
          'usuario': UsuarioModel.fromJson(data['usuario']),
          'token': _token,
        };
      } else if (response.statusCode == 401) {
        return {
          'exito': false,
          'mensaje': 'CI o PIN incorrecto',
          'codigo': 'CREDENCIALES_INVALIDAS',
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error en login',
          'codigo': 'ERROR_LOGIN',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error de conexión: $e',
        'codigo': 'ERROR_CONEXION',
      };
    }
  }

  // ============ OBTENER PERFIL ACTUAL ============
  Future<UsuarioModel?> obtenerPerfil() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/usuario/perfil'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
         return UsuarioModel.fromJson(data['usuario']);
      }
      return null;
    } catch (e) {
      print('Error obteniendo perfil: $e');
      return null;
    }
  }

  // ============ RECARGAR SALDO ============
  Future<Map<String, dynamic>> crearRecargaPayPal({
    required double monto,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/paypal/crear-orden'),
        headers: _headers,
        body: jsonEncode({
          'monto': monto,
          'moneda': 'BOB', // Bolivianos
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'exito': true,
          'ordenId': data['ordenId'],
          'urlAprobacion': data['urlAprobacion'],
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error creando orden de PayPal',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> confirmarRecargaPayPal({
    required String ordenId,
    required String payerId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/paypal/capturar-orden'),
        headers: _headers,
        body: jsonEncode({
          'ordenId': ordenId,
          'payerId': payerId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'exito': true,
          'saldoActualizado': data['saldoActualizado'],
           'usuario': UsuarioModel.fromJson(data['usuario']),
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error confirmando pago',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  // ============ GENERAR QR DE VIAJE ============
  Future<Map<String, dynamic>> generarQRViaje() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/viaje/generar-qr'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'exito': true,
          'qrData': data['qrData'],
          'tarifaAplicada': data['tarifaAplicada'],
          'saldoRestante': data['saldoRestante'],
          'sessionId': data['sessionId'],
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error generando QR',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  // ============ VALIDAR QR (para dispositivo del chofer) ============
  Future<Map<String, dynamic>> validarQRViaje(String qrData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/viaje/validar-qr'),
        headers: _headers,
        body: jsonEncode({
          'qrData': qrData,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'exito': true,
          'usuarioNombre': data['usuarioNombre'],
          'tipoUsuario': data['tipoUsuario'],
          'tarifaAplicada': data['tarifaAplicada'],
          'saldoRestante': data['saldoRestante'],
          'viajeId': data['viajeId'],
        };
      } else if (response.statusCode == 400) {
        return {
          'exito': false,
          'mensaje': 'QR inválido o expirado (máximo 30 segundos)',
          'codigo': 'QR_EXPIRADO',
        };
      } else if (response.statusCode == 402) {
        return {
          'exito': false,
          'mensaje': 'Saldo insuficiente',
          'codigo': 'SALDO_INSUFICIENTE',
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error validando QR',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  // ============ OBTENER HISTORIAL DE VIAJES ============
  Future<List<dynamic>> obtenerHistorialViajes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/usuario/viajes'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['viajes'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      print('Error obteniendo viajes: $e');
      return [];
    }
  }

  // ============ LOGIN CONDUCTOR ============
  /// Login específico para conductores (tabla conductores)
  Future<Map<String, dynamic>> loginConductor({
    required String ci,
    required String pin,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/conductores/login'),
        headers: _headers,
        body: jsonEncode({
          'ci': ci,
          'pin': pin,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Los conductores también reciben token (JWT)
        _token = data['token'];
        await storageService.guardarToken(_token!);
        // Guardar datos de conductor en clave separada
        await storageService.guardarObjeto('conductor_data', data['conductor']);
        await storageService.guardar('tipo_usuario', 'conductor');
        return {
          'exito': true,
          'conductor': data['conductor'],
          'token': _token,
        };
      } else if (response.statusCode == 401) {
        return {
          'exito': false,
          'mensaje': 'CI o PIN incorrecto',
          'codigo': 'CREDENCIALES_INVALIDAS',
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error en login conductor',
          'codigo': 'ERROR_LOGIN_CONDUCTOR',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error de conexión: $e',
        'codigo': 'ERROR_CONEXION',
      };
    }
  }

  // ============ LOGOUT ============
  Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: _headers,
      );
    } catch (e) {
      print('Error en logout: $e');
    }
    _token = null;
    await storageService.limpiarSesion();
  }

  // ============ ENDPOINTS PARA CONDUCTORES ============

  /// Registrar nuevo conductor (con solicitud de contrato)
  Future<Map<String, dynamic>> registrarConductor({
    required String ci,
    required String nombre,
    required String apellido,
    required String email,
    required String telefono,
    required String direccion,
    required String numeroLicencia,
    required DateTime vigenciaLicencia,
    required String empresa,
    required int zonaId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/conductores/registro'),
        headers: _headers,
        body: jsonEncode({
          'ci': ci,
          'nombre': nombre,
          'apellido': apellido,
          'email': email,
          'telefono': telefono,
          'direccion': direccion,
          'numero_licencia': numeroLicencia,
          'vigencia_licencia': vigenciaLicencia.toIso8601String().split('T')[0],
          'empresa': empresa,
          'zona_id': zonaId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'exito': true,
          'mensaje': 'Solicitud enviada. Esperando aprobación del admin.',
          'conductorId': data['conductor_id'],
        };
      } else if (response.statusCode == 409) {
        return {
          'exito': false,
          'mensaje': 'Este CI ya está registrado como conductor',
          'codigo': 'CI_DUPLICADO',
        };
      } else {
        return {
          'exito': false,
          'mensaje': data['mensaje'] ?? 'Error registrando conductor',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  /// Obtener datos del conductor (requiere autenticación)
  Future<Map<String, dynamic>> obtenerConductor() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conductores/perfil'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'exito': true,
          'conductor': data['conductor'],
        };
      }
      return {
        'exito': false,
        'mensaje': 'No se encontró perfil de conductor',
      };
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  /// Obtener contrato del conductor (estado pendiente/aceptado/rechazado)
  Future<Map<String, dynamic>> obtenerContratoConductor() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conductores/contrato'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'exito': true,
          'contrato': data['contrato'],
        };
      }
      return {
        'exito': false,
        'mensaje': 'No hay contrato',
      };
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  /// Aceptar contrato (por parte del conductor)
  Future<Map<String, dynamic>> aceptarContratoAsIConductor() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/conductores/aceptar-contrato'),
        headers: _headers,
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'exito': true,
          'mensaje': 'Contrato aceptado correctamente',
        };
      } else {
        return {
          'exito': false,
          'mensaje': data['mensaje'] ?? 'Error aceptando contrato',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  /// Obtener pagos/ganancias del conductor
  Future<List<dynamic>> obtenerPagosConductor({String? filtroEstado}) async {
    try {
      String url = '$baseUrl/conductores/pagos';
      if (filtroEstado != null) {
        url += '?estado=$filtroEstado';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['pagos'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      print('Error obteniendo pagos: $e');
      return [];
    }
  }

  /// Obtener resumen de ganancias del conductor
  Future<Map<String, dynamic>> obtenerResumenGanancias() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conductores/resumen-ganancias'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }
      return {
        'total_ganancias': 0.0,
        'pagos_pendientes': 0.0,
        'pagos_abonados': 0.0,
        'viajes_hoy': 0,
      };
    } catch (e) {
      print('Error obteniendo resumen: $e');
      return {};
    }
  }

  /// Obtener contratos pendientes (para admin)
  Future<List<dynamic>> obtenerContratosPendientes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/contratos-pendientes'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['contratos'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      print('Error obteniendo contratos: $e');
      return [];
    }
  }

  /// Aprobar contrato de conductor (admin)
  Future<Map<String, dynamic>> aprobarContratoConductor({
    required String contratoId,
    String? comentario,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/aprobar-contrato/$contratoId'),
        headers: _headers,
        body: jsonEncode({
          'comentario': comentario,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'exito': true,
          'mensaje': 'Contrato aprobado',
        };
      } else {
        return {
          'exito': false,
          'mensaje': data['mensaje'] ?? 'Error aprobando contrato',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  /// Rechazar contrato de conductor (admin)
  Future<Map<String, dynamic>> rechazarContratoConductor({
    required String contratoId,
    required String razonRechazo,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/rechazar-contrato/$contratoId'),
        headers: _headers,
        body: jsonEncode({
          'razon_rechazo': razonRechazo,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'exito': true,
          'mensaje': 'Contrato rechazado',
        };
      } else {
        return {
          'exito': false,
          'mensaje': data['mensaje'] ?? 'Error rechazando contrato',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }
}

