import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/usuario_model.dart';

class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _usuarioKey = 'usuario_data';
  static const String _ciKey = 'usuario_ci';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ============ Token ============
  Future<bool> guardarToken(String token) async {
    return await _prefs.setString(_tokenKey, token);
  }

  String? obtenerToken() {
    return _prefs.getString(_tokenKey);
  }

  Future<bool> eliminarToken() async {
    return await _prefs.remove(_tokenKey);
  }

  bool tieneToken() {
    return _prefs.containsKey(_tokenKey);
  }

  // ============ Usuario ============
  Future<bool> guardarUsuario(UsuarioModel usuario) async {
    final jsonString = jsonEncode(usuario.toJson());
    await _prefs.setString(_usuarioKey, jsonString);
    await _prefs.setString(_ciKey, usuario.ci);
    return true;
  }

  UsuarioModel? obtenerUsuario() {
    final jsonString = _prefs.getString(_usuarioKey);
    if (jsonString == null) return null;
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
       return UsuarioModel.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  String? obtenerCiGuardado() {
    return _prefs.getString(_ciKey);
  }

  Future<bool> eliminarUsuario() async {
    await _prefs.remove(_usuarioKey);
    await _prefs.remove(_ciKey);
    return true;
  }

   // ============ Cerrar sesión (limpia todo) ============
   Future<void> limpiarSesion() async {
     await eliminarToken();
     await eliminarUsuario();
   }

   // ============ Datos genéricos (para conductor, etc.) ============
   Future<bool> guardar(String key, String value) async {
     return await _prefs.setString(key, value);
   }

   String? obtener(String key) {
     return _prefs.getString(key);
   }

   Future<bool> guardarObjeto(String key, Map<String, dynamic> obj) async {
     final jsonString = jsonEncode(obj);
     return await _prefs.setString(key, jsonString);
   }

   Map<String, dynamic>? obtenerObjeto(String key) {
     final jsonString = _prefs.getString(key);
     if (jsonString == null) return null;
     try {
       return jsonDecode(jsonString) as Map<String, dynamic>;
     } catch (e) {
       return null;
     }
   }

   Future<bool> eliminar(String key) async {
     return await _prefs.remove(key);
   }

   // ── Biometría ──
   // Guardamos CI y PIN (para re-login automático tras autenticación biométrica).
   // En producción usa flutter_secure_storage en lugar de SharedPreferences.
   static const _kCIBio  = 'bio_ci';
   static const _kPINBio = 'bio_pin';

   Future<void> guardarCIBio(String ci) async =>
       _prefs.setString(_kCIBio, ci);

   Future<void> guardarPINBio(String pin) async =>
       _prefs.setString(_kPINBio, pin);

   String? obtenerCIBio()  => _prefs.getString(_kCIBio);
   String? obtenerPINBio() => _prefs.getString(_kPINBio);

   Future<void> limpiarBio() async {
     await _prefs.remove(_kCIBio);
     await _prefs.remove(_kPINBio);
   }
 }
