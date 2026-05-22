import 'package:flutter/material.dart';
import '../models/usuario_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class UsuarioProvider extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;

  UsuarioModel? _usuario;
  bool _cargando = false;
  String? _errorMessage;

  UsuarioProvider({
    required ApiService apiService,
    required StorageService storageService,
  })  : _apiService = apiService,
        _storageService = storageService;

  // Getters
  UsuarioModel? get usuario => _usuario;
  bool get cargando => _cargando;
  String? get errorMessage => _errorMessage;
  bool get estaAutenticado => _usuario != null;

  // Métodos públicos
  Future<bool> cargarUsuario() async {
    try {
      _cargando = true;
      _errorMessage = null;
      notifyListeners();

      _usuario = _storageService.obtenerUsuario();
      
      if (_usuario != null) {
        _cargando = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'No hay usuario cargado';
        _cargando = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error al cargar usuario: $e';
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> actualizarSaldo() async {
    try {
      if (_usuario == null) return false;

      final usuarioActualizado = await _apiService.obtenerPerfil();
      if (usuarioActualizado != null) {
        _usuario = _usuario!.copyWith(saldo: usuarioActualizado.saldo);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = 'Error al actualizar saldo: $e';
      return false;
    }
  }

  Future<void> cerrarSesion() async {
    await _storageService.limpiarSesion();
    _usuario = null;
    _errorMessage = null;
    notifyListeners();
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
