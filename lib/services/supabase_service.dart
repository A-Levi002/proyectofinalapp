import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/usuario_model.dart';
import 'storage_service.dart';
import '../utils/helpers.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final StorageService _storageService;

  SupabaseService(this._storageService);

  // ============ VERIFICAR CI ============
  Future<bool> ciYaExiste(String ci) async {
    try {
      final response = await _supabase
          .from('usuarios')
          .select('ci')
          .eq('ci', ci)
          .maybeSingle();
      return response != null;
    } catch (e) {
      print('Error verificando CI: $e');
      return false;
    }
  }

  // ============ REGISTRO USUARIO ============
  Future<Map<String, dynamic>> registrarUsuario({
    required String ci,
    required String nombre,
    required String apellido,
    required String email,
    required String telefono,
    required String tipoUsuario,
    required DateTime? fechaNacimiento,
    required String pin,
  }) async {
    try {
      final existe = await ciYaExiste(ci);
      if (existe) {
        return {
          'exito': false,
          'mensaje': 'Este CI ya tiene una cuenta registrada',
          'codigo': 'CI_DUPLICADO',
        };
      }

      // Registrar en Supabase Auth
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: pin,
      );

      if (authResponse.user == null) {
        return {
          'exito': false,
          'mensaje': 'Error en el registro de autenticación',
        };
      }

      // Insertar en tabla usuarios
      final response = await _supabase.from('usuarios').insert({
        'ci': ci,
        'nombre': nombre,
        'apellido': apellido,
        'email': email,
        'telefono': telefono,
        'tipo_usuario': tipoUsuario,
        'pin_hash': pin,
        'fecha_nacimiento': fechaNacimiento?.toIso8601String(),
        'saldo': 0.0,
        'activo': true,
      }).select();

      if (response.isNotEmpty) {
        await _storageService.guardarToken(authResponse.session?.accessToken ?? '');
        await _storageService.guardarUsuario(UsuarioModel.fromJson(response.first));
        
        return {
          'exito': true,
          'usuario': UsuarioModel.fromJson(response.first),
          'token': authResponse.session?.accessToken,
        };
      }

      return {
        'exito': false,
        'mensaje': 'Error en el registro',
      };
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  // ============ LOGIN USUARIO ============
  Future<Map<String, dynamic>> login({
    required String ci,
    required String pin,
  }) async {
    try {
      print('========== LOGIN DEBUG ==========');
      print('CI ingresado: $ci');
      print('PIN ingresado: $pin');
      
      // Buscar usuario por CI
      final userResponse = await _supabase
          .from('usuarios')
          .select()
          .eq('ci', ci)
          .maybeSingle();

      print('Respuesta de Supabase: $userResponse');

      if (userResponse == null) {
        print('❌ Usuario NO encontrado con CI: $ci');
        await registrarAuditLog(accion: 'LOGIN_FALLIDO', descripcion: 'CI no encontrado: $ci', status: 'error');
        return {
          'exito': false,
          'mensaje': 'CI no encontrado. Verifica que esté registrado.',
        };
      }

      // Verificar si está bloqueado
      final bloqueado = await estaUsuarioBloqueado(ci);
      if (bloqueado) {
        await registrarAuditLog(accion: 'LOGIN_BLOQUEADO', usuarioCi: ci, descripcion: 'Usuario bloqueado por intentos fallidos', status: 'advertencia');
        return {
          'exito': false,
          'mensaje': 'Cuenta bloqueada por demasiados intentos. Contacta al administrador.',
        };
      }

      print('✅ Usuario encontrado: ${userResponse['nombre']}');
      
      final email = userResponse['email'] as String?;
      print('Email asociado: $email');
      
      if (email == null) {
        return {
          'exito': false,
          'mensaje': 'Email no encontrado en el perfil',
        };
      }
      
      // Autenticar con Supabase Auth
      print('Intentando autenticar en Auth con email: $email');
      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: pin,
      );

      print('Auth response session: ${authResponse.session != null ? "OK" : "NULL"}');

      if (authResponse.session == null) {
        await registrarIntentoFallido(ci);
        await registrarAuditLog(accion: 'LOGIN_FALLIDO', usuarioCi: ci, descripcion: 'PIN incorrecto', status: 'error');
        return {
          'exito': false,
          'mensaje': 'CI o PIN incorrectos.',
        };
      }

      print('🎉 LOGIN EXITOSO!');
      await limpiarIntentosFallidos(ci);
      await registrarAuditLog(accion: 'LOGIN_EXITOSO', usuarioCi: ci, descripcion: 'Login correcto');
      
      await _storageService.guardarToken(authResponse.session!.accessToken);
      await _storageService.guardarUsuario(UsuarioModel.fromJson(userResponse));

      return {
        'exito': true,
        'usuario': UsuarioModel.fromJson(userResponse),
        'token': authResponse.session!.accessToken,
      };
    } catch (e) {
      print('❌ Error en login: $e');
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  // ============ OBTENER PERFIL ============
  Future<UsuarioModel?> obtenerPerfil() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('usuarios')
          .select()
          .eq('email', user.email!)
          .maybeSingle();

      if (response != null) {
        return UsuarioModel.fromJson(response);
      }
      return null;
    } catch (e) {
      print('Error obteniendo perfil: $e');
      return null;
    }
  }

  // ============ ACTUALIZAR SALDO ============
  Future<bool> actualizarSaldo(String ci, double nuevoSaldo) async {
    try {
      await _supabase
          .from('usuarios')
          .update({'saldo': nuevoSaldo})
          .eq('ci', ci);
      return true;
    } catch (e) {
      print('Error actualizando saldo: $e');
      return false;
    }
  }

  // ============ HISTORIAL VIAJES ============
  Future<List<dynamic>> obtenerHistorialViajes() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final usuario = await _supabase
          .from('usuarios')
          .select('ci')
          .eq('email', user.email!)
          .maybeSingle();

      if (usuario == null) return [];

      final response = await _supabase
          .from('viajes')
          .select()
          .eq('usuario_ci', usuario['ci'])
          .order('fecha', ascending: false);

      return response;
    } catch (e) {
      print('Error obteniendo viajes: $e');
      return [];
    }
  }

  // ============ GENERAR QR VIAJE ============
  // [montoExtra] = tarifa de acompañantes (Bs 2.50 × cantidad)
  // [cantidadPersonas] = total de personas incluyendo el titular
  Future<Map<String, dynamic>> generarQRViaje({
    double montoExtra = 0.0,
    int cantidadPersonas = 1,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return {'exito': false, 'mensaje': 'Usuario no autenticado'};
      }

      final usuario = await _supabase
          .from('usuarios')
          .select()
          .eq('email', user.email!)
          .maybeSingle();

      if (usuario == null) {
        return {'exito': false, 'mensaje': 'Usuario no encontrado'};
      }

      final ci         = usuario['ci'] as String;
      final saldoStr   = usuario['saldo']?.toString() ?? '0';
      final saldo      = double.tryParse(saldoStr) ?? 0.0;
      final tipoUsuario = usuario['tipo_usuario'] as String? ?? 'general';

      // Tarifa propia con descuento + tarifa de acompañantes a precio general
      final tarifaPropia = TarifasHelper.calcularTarifa(tipoUsuario: tipoUsuario);
      final tarifaTotal  = tarifaPropia + montoExtra;

      if (saldo < tarifaTotal) {
        return {'exito': false, 'mensaje': 'Saldo insuficiente'};
      }

      final tokenQR   = '${ci}_${DateTime.now().millisecondsSinceEpoch}';
      final expiracion = DateTime.now().add(const Duration(seconds: 30));

      await _supabase.from('qr_viaje_dinamico').insert({
        'usuario_ci':        ci,
        'token_qr':          tokenQR,
        'monto_a_descontar': tarifaTotal,
        'perfil_aplicado':   tipoUsuario,
        'cantidad_personas': cantidadPersonas,
        'expira_en':         expiracion.toIso8601String(),
        'usado':             false,
      });

      return {
        'exito':          true,
        'qrData':         tokenQR,
        'tarifaAplicada': tarifaTotal,
        'saldoRestante':  saldo - tarifaTotal,
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ VALIDAR QR VIAJE ============
  Future<Map<String, dynamic>> validarQRViaje(String qrData) async {
    try {
      final qr = await _supabase
          .from('qr_viaje_dinamico')
          .select()
          .eq('token_qr', qrData)
          .maybeSingle();

      if (qr == null) {
        return {'exito': false, 'mensaje': 'QR inválido'};
      }

      final expiracionStr = qr['expira_en'] as String?;
      if (expiracionStr != null) {
        final expiracion = DateTime.parse(expiracionStr);
        if (expiracion.isBefore(DateTime.now())) {
          return {'exito': false, 'mensaje': 'QR expirado'};
        }
      }

      if (qr['usado'] == true) {
        return {'exito': false, 'mensaje': 'QR ya usado'};
      }

      await _supabase
          .from('qr_viaje_dinamico')
          .update({'usado': true, 'escaneado_en': DateTime.now().toIso8601String()})
          .eq('token_qr', qrData);

      final ci = qr['usuario_ci'] as String;
      final montoStr = qr['monto_a_descontar']?.toString() ?? '0';
      final monto = double.tryParse(montoStr) ?? 0.0;
      
      final usuario = await _supabase
          .from('usuarios')
          .select()
          .eq('ci', ci)
          .maybeSingle();
      
      if (usuario == null) {
        return {'exito': false, 'mensaje': 'Usuario no encontrado'};
      }

      final saldoActualStr = usuario['saldo']?.toString() ?? '0';
      final saldoActual = double.tryParse(saldoActualStr) ?? 0.0;
      final nuevoSaldo = saldoActual - monto;
      
      await actualizarSaldo(ci, nuevoSaldo);

      final cantPersonas = (qr['cantidad_personas'] as int?) ?? 1;

      await _supabase.from('viajes').insert({
        'usuario_ci':        ci,
        'qr_generado':       qrData,
        'monto_original':    2.50 * cantPersonas,
        'monto_descuento':   (2.50 * cantPersonas) - monto,
        'monto_final':       monto,
        'tipo_usuario':      qr['perfil_aplicado'],
        'cantidad_personas': cantPersonas,
        'estado':            'validado',
        'qr_escaneado':      true,
      });

      final nombreUsuario = usuario['nombre'] as String? ?? 'Usuario';
      final tipoUsuario = qr['perfil_aplicado'] as String? ?? 'general';

      // Registrar pago al conductor (si hay conductor activo en la zona)
      // Se hace en background — no bloquea la validación
      _registrarPagoConductor(ci, monto).catchError((_) {});

      await registrarAuditLog(
        accion: 'VIAJE_VALIDADO',
        usuarioCi: ci,
        descripcion: 'Monto: Bs $monto | Personas: $cantPersonas',
      );

      return {
        'exito': true,
        'usuarioNombre': nombreUsuario,
        'tipoUsuario': tipoUsuario,
        'tarifaAplicada': monto,
        'saldoRestante': nuevoSaldo,
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ REGISTRAR PAGO CONDUCTOR ============
  // Se llama automáticamente al validar un QR.
  // Busca el conductor activo y crea el registro en pagos_conductores.
  Future<void> _registrarPagoConductor(String usuarioCi, double montoTotal) async {
    try {
      // Buscar conductor activo con contrato aceptado (cualquiera disponible)
      final conductorActivo = await _supabase
          .from('conductores')
          .select('id, saldo_comisiones')
          .eq('estado', 'activo')
          .eq('contrato_aceptado', true)
          .limit(1)
          .maybeSingle();
      if (conductorActivo == null) return;

      // Porcentaje de comisión del contrato (default 10%)
      final contrato = await _supabase
          .from('contratos_conductores')
          .select('comision_porcentaje')
          .eq('conductor_id', conductorActivo['id'])
          .eq('estado', 'aceptado')
          .maybeSingle();

      final pct = (contrato?['comision_porcentaje'] as num?)?.toDouble() ?? 10.0;
      final comisionConductor = montoTotal * (pct / 100);
      final comisionEmpresa   = montoTotal - comisionConductor;

      // Obtener viaje recién creado
      final viaje = await _supabase
          .from('viajes')
          .select('id')
          .eq('usuario_ci', usuarioCi)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (viaje == null) return;

      await _supabase.from('pagos_conductores').insert({
        'conductor_id':       conductorActivo['id'],
        'usuario_pasajero_ci': usuarioCi,
        'viaje_id':           viaje['id'],
        'monto_bruto':        montoTotal,
        'comision_conductor': comisionConductor,
        'comision_empresa':   comisionEmpresa,
        'estado':             'pendiente',
      });

      // Acumular en saldo_comisiones del conductor
      final saldoActual = (conductorActivo['saldo_comisiones'] as num?)?.toDouble() ?? 0.0;
      await _supabase
          .from('conductores')
          .update({'saldo_comisiones': saldoActual + comisionConductor})
          .eq('id', conductorActivo['id']);
    } catch (_) {}
  }

  // ============ RECARGA PAYPAL ============
  Future<Map<String, dynamic>> crearRecargaPayPal({required double monto}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return {'exito': false, 'mensaje': 'Usuario no autenticado'};
      }

      final usuario = await _supabase
          .from('usuarios')
          .select('ci')
          .eq('email', user.email!)
          .maybeSingle();

      if (usuario == null) {
        return {'exito': false, 'mensaje': 'Usuario no encontrado'};
      }

      final transaccionId = 'PAYPAL_${DateTime.now().millisecondsSinceEpoch}';
      
      await _supabase.from('recargas').insert({
        'usuario_ci': usuario['ci'],
        'monto': monto,
        'metodo': 'paypal',
        'transaccion_id': transaccionId,
        'estado': 'completada',
      });

      // Actualizar saldo
      final usuarioActual = await _supabase
          .from('usuarios')
          .select('saldo')
          .eq('ci', usuario['ci'])
          .maybeSingle();
      
      final saldoActualStr = usuarioActual?['saldo']?.toString() ?? '0';
      final saldoActual = double.tryParse(saldoActualStr) ?? 0.0;
      final nuevoSaldo = saldoActual + monto;
      
      await actualizarSaldo(usuario['ci'], nuevoSaldo);

      return {
        'exito': true,
        'mensaje': 'Recarga exitosa',
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ TARIFAS DESDE BD ============
  Future<Map<String, double>> obtenerTarifas() async {
    try {
      final rows = await _supabase
          .from('tarifas')
          .select()
          .eq('activo', true);
      final Map<String, double> tarifas = {};
      for (final row in rows) {
        tarifas[row['tipo_usuario'] as String] =
            (row['tarifa_final'] as num).toDouble();
      }
      return tarifas;
    } catch (_) {
      // Fallback a hardcoded si falla la BD
      return {
        'general':      2.50,
        'estudiante':   1.25,
        'adultomayor':  1.75,
        'discapacidad': 0.00,
      };
    }
  }

  // ============ REGISTRAR INTENTO LOGIN FALLIDO ============
  Future<void> registrarIntentoFallido(String ci) async {
    try {
      final existe = await _supabase
          .from('intentos_login_fallidos')
          .select()
          .eq('usuario_ci', ci)
          .maybeSingle();
      if (existe == null) {
        await _supabase.from('intentos_login_fallidos').insert({
          'usuario_ci':    ci,
          'cantidad':      1,
          'ultimo_intento': DateTime.now().toIso8601String(),
        });
      } else {
        final cantidad = (existe['cantidad'] as int) + 1;
        await _supabase.from('intentos_login_fallidos').update({
          'cantidad':      cantidad,
          'ultimo_intento': DateTime.now().toIso8601String(),
          'bloqueado':     cantidad >= 5,
          'razon':         cantidad >= 5 ? 'Demasiados intentos fallidos' : null,
        }).eq('usuario_ci', ci);
      }
    } catch (_) {}
  }

  Future<bool> estaUsuarioBloqueado(String ci) async {
    try {
      final row = await _supabase
          .from('intentos_login_fallidos')
          .select()
          .eq('usuario_ci', ci)
          .eq('bloqueado', true)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> limpiarIntentosFallidos(String ci) async {
    try {
      await _supabase
          .from('intentos_login_fallidos')
          .delete()
          .eq('usuario_ci', ci);
    } catch (_) {}
  }

  // ============ AUDIT LOG ============
  Future<void> registrarAuditLog({
    required String accion,
    String? usuarioCi,
    String? descripcion,
    String status = 'exito',
  }) async {
    try {
      await _supabase.from('audit_logs').insert({
        'usuario_ci':  usuarioCi,
        'accion':      accion,
        'descripcion': descripcion,
        'status':      status,
      });
    } catch (_) {}
  }

  // ============ ZONAS ============
  Future<List<Map<String, dynamic>>> obtenerZonas() async {
    try {
      final rows = await _supabase
          .from('zonas')
          .select()
          .eq('activo', true)
          .order('nombre');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  // ============ LOGOUT ============
  Future<void> logout() async {
    await _supabase.auth.signOut();
    await _storageService.limpiarSesion();
  }

  // ============ REGISTRO CONDUCTOR ============
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
      final existe = await _supabase
          .from('conductores')
          .select('ci')
          .eq('ci', ci)
          .maybeSingle();

      if (existe != null) {
        return {
          'exito': false,
          'mensaje': 'Este CI ya está registrado como conductor',
          'codigo': 'CI_DUPLICADO',
        };
      }

      // Insertar conductor — NO enviamos 'id', Supabase lo genera como UUID
      final conductorInsert = await _supabase.from('conductores').insert({
        'ci':               ci,
        'nombre':           nombre,
        'apellido':         apellido,
        'email':            email,
        'telefono':         telefono,
        'direccion':        direccion,
        'numero_licencia':  numeroLicencia,
        'vigencia_licencia': vigenciaLicencia.toIso8601String().split('T')[0],
        'empresa':          empresa,
        'zona_id':          zonaId,
        'estado':           'inactivo',
        'pin_hash':         '1234',
        'contrato_aceptado': false,
        'fecha_nacimiento': '1990-01-01', // placeholder, se actualiza en perfil
        'categoria_licencia': 'P',
      }).select('id').single();

      final conductorUUID = conductorInsert['id'] as String;

      await _supabase.from('contratos_conductores').insert({
        'conductor_id':        conductorUUID,
        'empresa':             empresa,
        'zona_id':             zonaId,
        'fecha_inicio':        DateTime.now().toIso8601String().split('T')[0],
        'documento_contrato':  'pendiente',
        'terminos_condiciones': 'Términos y condiciones estándar de TransitApp.',
        'estado':              'pendiente',
      });

      return {
        'exito': true,
        'mensaje': 'Solicitud enviada. Espera aprobación del administrador.',
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ LOGIN CONDUCTOR ============
  Future<Map<String, dynamic>> loginConductor({
    required String ci,
    required String pin,
  }) async {
    try {
      final conductor = await _supabase
          .from('conductores')
          .select()
          .eq('ci', ci)
          .maybeSingle();

      if (conductor == null) {
        return {
          'exito': false,
          'mensaje': 'CI no encontrado',
        };
      }

      final pinHash = conductor['pin_hash'] as String? ?? '';
      if (pinHash != pin) {
        return {
          'exito': false,
          'mensaje': 'PIN incorrecto',
        };
      }

      final estado = conductor['estado'] as String? ?? 'inactivo';
      if (estado != 'activo') {
        return {
          'exito': false,
          'mensaje': 'Tu cuenta no está activa. Espera aprobación del administrador.',
        };
      }

      return {
        'exito': true,
        'conductor': conductor,
        'token': 'conductor_${conductor['id']}',
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ OBTENER DATOS CONDUCTOR ============
  Future<Map<String, dynamic>> obtenerConductor() async {
    try {
      final conductorData = _storageService.obtenerObjeto('conductor_data');
      if (conductorData == null) {
        return {'exito': false, 'mensaje': 'No hay datos de conductor'};
      }

      final conductor = await _supabase
          .from('conductores')
          .select()
          .eq('ci', conductorData['ci'])
          .maybeSingle();

      if (conductor == null) {
        return {'exito': false, 'mensaje': 'Conductor no encontrado'};
      }

      return {
        'exito': true,
        'conductor': conductor,
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ OBTENER CONTRATO CONDUCTOR ============
  Future<Map<String, dynamic>> obtenerContratoConductor() async {
    try {
      final conductorData = _storageService.obtenerObjeto('conductor_data');
      if (conductorData == null) {
        return {'exito': false, 'mensaje': 'No hay datos de conductor'};
      }

      final conductor = await _supabase
          .from('conductores')
          .select('id')
          .eq('ci', conductorData['ci'])
          .maybeSingle();

      if (conductor == null) {
        return {'exito': false, 'mensaje': 'Conductor no encontrado'};
      }

      final contrato = await _supabase
          .from('contratos_conductores')
          .select()
          .eq('conductor_id', conductor['id'])
          .maybeSingle();

      if (contrato == null) {
        return {'exito': false, 'mensaje': 'No hay contrato'};
      }

      return {
        'exito': true,
        'contrato': contrato,
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ ACEPTAR CONTRATO ============
  Future<Map<String, dynamic>> aceptarContratoAsIConductor() async {
    try {
      final conductorData = _storageService.obtenerObjeto('conductor_data');
      if (conductorData == null) {
        return {'exito': false, 'mensaje': 'No hay datos de conductor'};
      }

      final conductor = await _supabase
          .from('conductores')
          .select('id')
          .eq('ci', conductorData['ci'])
          .maybeSingle();

      if (conductor == null) {
        return {'exito': false, 'mensaje': 'Conductor no encontrado'};
      }

      await _supabase
          .from('conductores')
          .update({'contrato_aceptado': true, 'fecha_aceptacion_contrato': DateTime.now().toIso8601String()})
          .eq('id', conductor['id']);

      return {
        'exito': true,
        'mensaje': 'Contrato aceptado',
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ OBTENER PAGOS CONDUCTOR ============
  Future<List<dynamic>> obtenerPagosConductor({String? filtroEstado}) async {
    try {
      final conductorData = _storageService.obtenerObjeto('conductor_data');
      if (conductorData == null) return [];

      final conductor = await _supabase
          .from('conductores')
          .select('id')
          .eq('ci', conductorData['ci'])
          .maybeSingle();

      if (conductor == null) return [];

      var query = _supabase
          .from('pagos_conductores')
          .select()
          .eq('conductor_id', conductor['id']);

      if (filtroEstado != null && filtroEstado != 'todos') {
        query = query.eq('estado', filtroEstado);
      }

      final response = await query.order('fecha_pago', ascending: false);
      return response;
    } catch (e) {
      print('Error obteniendo pagos: $e');
      return [];
    }
  }

  // ============ OBTENER RESUMEN GANANCIAS ============
  Future<Map<String, dynamic>> obtenerResumenGanancias() async {
    try {
      final conductorData = _storageService.obtenerObjeto('conductor_data');
      if (conductorData == null) {
        return {
          'total_ganancias': 0.0,
          'pagos_pendientes': 0.0,
          'pagos_abonados': 0.0,
          'viajes_hoy': 0,
        };
      }

      final conductor = await _supabase
          .from('conductores')
          .select('id')
          .eq('ci', conductorData['ci'])
          .maybeSingle();

      if (conductor == null) {
        return {
          'total_ganancias': 0.0,
          'pagos_pendientes': 0.0,
          'pagos_abonados': 0.0,
          'viajes_hoy': 0,
        };
      }

      final pagos = await _supabase
          .from('pagos_conductores')
          .select()
          .eq('conductor_id', conductor['id']);

      double totalGanancias = 0.0;
      double pagosPendientes = 0.0;
      double pagosAbonados = 0.0;
      int viajesHoy = 0;

      final hoy = DateTime.now().toIso8601String().split('T')[0];

      for (final pago in pagos) {
        final comisionStr = pago['comision_conductor']?.toString() ?? '0';
        final comision = double.tryParse(comisionStr) ?? 0.0;
        totalGanancias += comision;
        
        final estado = pago['estado'] as String? ?? '';
        if (estado == 'pendiente') {
          pagosPendientes += comision;
        } else if (estado == 'abonado') {
          pagosAbonados += comision;
        }
        
        final fechaPagoStr = pago['fecha_pago'] as String? ?? '';
        final fechaPago = fechaPagoStr.split('T')[0];
        if (fechaPago == hoy) {
          viajesHoy++;
        }
      }

      return {
        'total_ganancias': totalGanancias,
        'pagos_pendientes': pagosPendientes,
        'pagos_abonados': pagosAbonados,
        'viajes_hoy': viajesHoy,
      };
    } catch (e) {
      print('Error obteniendo resumen: $e');
      return {
        'total_ganancias': 0.0,
        'pagos_pendientes': 0.0,
        'pagos_abonados': 0.0,
        'viajes_hoy': 0,
      };
    }
  }

  // ============ CONTRATOS PENDIENTES (ADMIN) ============
  Future<List<dynamic>> obtenerContratosPendientes() async {
    try {
      final contratos = await _supabase
          .from('contratos_conductores')
          .select('*, conductores(*)')
          .eq('estado', 'pendiente')
          .order('fecha_solicitud', ascending: false);

      final List<dynamic> resultado = [];
      for (final contrato in contratos) {
        final conductor = await _supabase
            .from('conductores')
            .select()
            .eq('id', contrato['conductor_id'])
            .maybeSingle();
        
        resultado.add({
          'id': contrato['id'],
          'conductor': conductor,
          'empresa': contrato['empresa'],
          'comision_porcentaje': contrato['comision_porcentaje'],
          'terminos_condiciones': contrato['terminos_condiciones'],
          'fecha_solicitud': contrato['fecha_solicitud'],
        });
      }
      
      return resultado;
    } catch (e) {
      print('Error obteniendo contratos pendientes: $e');
      return [];
    }
  }

  // ============ APROBAR CONTRATO (ADMIN) ============
  Future<Map<String, dynamic>> aprobarContratoConductor({
    required String contratoId,
    String? comentario,
  }) async {
    try {
      await _supabase
          .from('contratos_conductores')
          .update({
            'estado': 'aceptado',
            'fecha_respuesta': DateTime.now().toIso8601String(),
          })
          .eq('id', contratoId);

      final contrato = await _supabase
          .from('contratos_conductores')
          .select('conductor_id')
          .eq('id', contratoId)
          .maybeSingle();

      if (contrato != null) {
        await _supabase
            .from('conductores')
            .update({'estado': 'activo'})
            .eq('id', contrato['conductor_id']);
      }

      return {
        'exito': true,
        'mensaje': 'Contrato aprobado',
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ RECHAZAR CONTRATO (ADMIN) ============
  Future<Map<String, dynamic>> rechazarContratoConductor({
    required String contratoId,
    required String razonRechazo,
  }) async {
    try {
      await _supabase
          .from('contratos_conductores')
          .update({
            'estado': 'rechazado',
            'razon_rechazo': razonRechazo,
            'fecha_respuesta': DateTime.now().toIso8601String(),
          })
          .eq('id', contratoId);

      return {
        'exito': true,
        'mensaje': 'Contrato rechazado',
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  // ============ CREAR USUARIO EN AUTH MANUALMENTE ============
  Future<Map<String, dynamic>> crearUsuarioEnAuth({
    required String email,
    required String password,
  }) async {
    try {
      print('🔐 Creando usuario en Auth: $email');
      
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null) {
        print('✅ Usuario creado en Auth: $email');
        return {
          'exito': true,
          'mensaje': 'Usuario creado exitosamente',
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error creando usuario en Auth',
        };
      }
    } catch (e) {
      print('❌ Error: $e');
      return {
        'exito': false,
        'mensaje': 'Error: $e',
      };
    }
  }

  // ============ SINCRONIZAR USUARIOS EXISTENTES CON AUTH ============
  Future<Map<String, dynamic>> sincronizarUsuariosConAuth() async {
    try {
      // Obtener todos los usuarios de la tabla
      final usuarios = await _supabase.from('usuarios').select();
      
      print('📦 Usuarios en tabla: ${usuarios.length}');
      
      int procesados = 0;
      int creados = 0;
      int yaExistentes = 0;
      int errores = 0;
      List<String> erroresList = [];
      
      for (final usuario in usuarios) {
        final email = usuario['email'] as String?;
        final pin = usuario['pin_hash'] as String?;
        
        if (email != null && pin != null) {
          procesados++;
          try {
            // Intentar crear usuario en Auth
            final response = await _supabase.auth.signUp(
              email: email,
              password: pin,
            );
            
            if (response.user != null) {
              print('✅ Usuario creado: $email');
              creados++;
            } else {
              print('⚠️ Usuario ya existía o error: $email');
              yaExistentes++;
            }
          } catch (e) {
            // Si el error es que ya existe, lo consideramos éxito
            if (e.toString().contains('already registered')) {
              print('⚠️ Usuario ya existía en Auth: $email');
              yaExistentes++;
            } else {
              print('❌ Error con $email: $e');
              errores++;
              erroresList.add('$email: $e');
            }
          }
        }
      }
      
      String mensaje = 'Sincronización completada: $procesados usuarios procesados. '
          'Creados: $creados, Ya existían: $yaExistentes, Errores: $errores';
      
      print('📊 $mensaje');
      
      return {
        'exito': true,
        'procesados': procesados,
        'creados': creados,
        'yaExistentes': yaExistentes,
        'errores': errores,
        'erroresList': erroresList,
        'mensaje': mensaje,
      };
    } catch (e) {
      print('❌ Error en sincronización: $e');
      return {
        'exito': false,
        'mensaje': 'Error en sincronización: $e',
      };
    }
  }
}