import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/usuario_model.dart';

class StorageService {
  static const String _tokenKey    = 'auth_token';
  static const String _usuarioKey  = 'usuario_data';
  static const String _ciKey       = 'usuario_ci';
  static const String _kCIBio      = 'bio_ci';
  static const String _kPINBio     = 'bio_pin';
  static const String _kPrimerLanz = 'primer_lanzamiento';
  static const String _kBloqueado  = 'app_bloqueada';
  static const String _kTipoSesion = 'tipo_sesion'; // 'usuario' | 'conductor'

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Token ──
  Future<bool> guardarToken(String token) async =>
      _prefs.setString(_tokenKey, token);
  String? obtenerToken() => _prefs.getString(_tokenKey);
  Future<bool> eliminarToken() async => _prefs.remove(_tokenKey);
  bool tieneToken() {
    final t = _prefs.getString(_tokenKey);
    return t != null && t.isNotEmpty;
  }

  // ── Usuario ──
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
      return UsuarioModel.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  String? obtenerCiGuardado() => _prefs.getString(_ciKey);

  Future<bool> eliminarUsuario() async {
    await _prefs.remove(_usuarioKey);
    await _prefs.remove(_ciKey);
    return true;
  }

  Future<void> limpiarSesion() async {
    await eliminarToken();
    await eliminarUsuario();
    await _prefs.remove(_kTipoSesion);
  }

  // ── Genérico ──
  Future<bool> guardar(String key, String value) async =>
      _prefs.setString(key, value);
  String? obtener(String key) => _prefs.getString(key);

  Future<bool> guardarObjeto(String key, Map<String, dynamic> obj) async =>
      _prefs.setString(key, jsonEncode(obj));

  Map<String, dynamic>? obtenerObjeto(String key) {
    final s = _prefs.getString(key);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, dynamic>; } catch (_) { return null; }
  }

  Future<bool> eliminar(String key) async => _prefs.remove(key);

  // ── Biometría ──
  Future<void> guardarCIBio(String ci)   async => _prefs.setString(_kCIBio, ci);
  Future<void> guardarPINBio(String pin) async => _prefs.setString(_kPINBio, pin);
  String? obtenerCIBio()  => _prefs.getString(_kCIBio);
  String? obtenerPINBio() => _prefs.getString(_kPINBio);
  Future<void> limpiarBio() async {
    await _prefs.remove(_kCIBio);
    await _prefs.remove(_kPINBio);
  }

  // ── Primer lanzamiento (onboarding) ──
  bool esPrimerLanzamiento() => _prefs.getBool(_kPrimerLanz) ?? true;
  Future<void> marcarLanzamiento() async =>
      _prefs.setBool(_kPrimerLanz, false);

  // ── Bloqueo de app (requiere auth al volver) ──
  Future<void> bloquearApp()    async => _prefs.setBool(_kBloqueado, true);
  Future<void> desbloquearApp() async => _prefs.setBool(_kBloqueado, false);
  bool estaAppBloqueada() => _prefs.getBool(_kBloqueado) ?? false;

  // ── Tipo de sesión activa ──
  Future<void> guardarTipoSesion(String tipo) async =>
      _prefs.setString(_kTipoSesion, tipo);
  String? obtenerTipoSesion() => _prefs.getString(_kTipoSesion);

  // ── Cuentas registradas en este dispositivo ──
  static const String _kCuentasRegistradas = 'cuentas_registradas';

  Future<void> marcarCuentaRegistrada(String tipo) async {
    final lista = obtenerCuentasRegistradas();
    if (!lista.contains(tipo)) {
      lista.add(tipo);
      await _prefs.setStringList(_kCuentasRegistradas, lista);
    }
  }

  List<String> obtenerCuentasRegistradas() =>
      _prefs.getStringList(_kCuentasRegistradas) ?? [];

  bool tieneCuenta(String tipo) => obtenerCuentasRegistradas().contains(tipo);

  Future<void> limpiarCuentasRegistradas() async =>
      _prefs.remove(_kCuentasRegistradas);
}