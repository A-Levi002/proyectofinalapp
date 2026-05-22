import 'package:intl/intl.dart';

class ConductorModel {
  final String id;
  final String ci;
  final String nombre;
  final String apellido;
  final String email;
  final String telefono;
  final String? fotoCIUrl;
  final DateTime fechaNacimiento;
  final String direccion;
  final String numeroLicencia;
  final String? categoriaLicencia;
  final DateTime vigenciaLicencia;
  final int zonaId;
  final String? numeroBus;
  final String? empresa;
  final double saldoComisiones;
  final String estado; // inactivo, activo, suspendido
  final bool contratoAceptado;
  final DateTime? fechaAceptacionContrato;
  final DateTime createdAt;

  ConductorModel({
    required this.id,
    required this.ci,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.telefono,
    this.fotoCIUrl,
    required this.fechaNacimiento,
    required this.direccion,
    required this.numeroLicencia,
    this.categoriaLicencia,
    required this.vigenciaLicencia,
    required this.zonaId,
    this.numeroBus,
    this.empresa,
    required this.saldoComisiones,
    required this.estado,
    required this.contratoAceptado,
    this.fechaAceptacionContrato,
    required this.createdAt,
  });

  // Getters útiles
  String get nombreCompleto => '$nombre $apellido';
  
  bool get licenciaVigente {
    return vigenciaLicencia.isAfter(DateTime.now());
  }

  int get edad {
    final today = DateTime.now();
    int age = today.year - fechaNacimiento.year;
    if (today.month < fechaNacimiento.month ||
        (today.month == fechaNacimiento.month &&
            today.day < fechaNacimiento.day)) {
      age--;
    }
    return age;
  }

  String get estadoBadge {
    switch (estado) {
      case 'activo':
        return '✓ Activo';
      case 'inactivo':
        return '○ Inactivo';
      case 'suspendido':
        return '✗ Suspendido';
      default:
        return estado;
    }
  }

  // Serialización
  factory ConductorModel.fromJson(Map<String, dynamic> json) {
    return ConductorModel(
      id: json['id'] ?? '',
      ci: json['ci'] ?? '',
      nombre: json['nombre'] ?? '',
      apellido: json['apellido'] ?? '',
      email: json['email'] ?? '',
      telefono: json['telefono'] ?? '',
      fotoCIUrl: json['foto_carnet'],
      fechaNacimiento: DateTime.parse(json['fecha_nacimiento'] ?? DateTime.now().toIso8601String()),
      direccion: json['direccion'] ?? '',
      numeroLicencia: json['numero_licencia'] ?? '',
      categoriaLicencia: json['categoria_licencia'],
      vigenciaLicencia: DateTime.parse(json['vigencia_licencia'] ?? DateTime.now().add(Duration(days: 365)).toIso8601String()),
      zonaId: json['zona_id'] ?? 1,
      numeroBus: json['numero_bus'],
      empresa: json['empresa'],
      saldoComisiones: double.tryParse(json['saldo_comisiones'].toString()) ?? 0.0,
      estado: json['estado'] ?? 'inactivo',
      contratoAceptado: json['contrato_aceptado'] == 1 || json['contrato_aceptado'] == true,
      fechaAceptacionContrato: json['fecha_aceptacion_contrato'] != null 
          ? DateTime.parse(json['fecha_aceptacion_contrato']) 
          : null,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ci': ci,
      'nombre': nombre,
      'apellido': apellido,
      'email': email,
      'telefono': telefono,
      'foto_carnet': fotoCIUrl,
      'fecha_nacimiento': DateFormat('yyyy-MM-dd').format(fechaNacimiento),
      'direccion': direccion,
      'numero_licencia': numeroLicencia,
      'categoria_licencia': categoriaLicencia,
      'vigencia_licencia': DateFormat('yyyy-MM-dd').format(vigenciaLicencia),
      'zona_id': zonaId,
      'numero_bus': numeroBus,
      'empresa': empresa,
      'saldo_comisiones': saldoComisiones,
      'estado': estado,
      'contrato_aceptado': contratoAceptado,
      'fecha_aceptacion_contrato': fechaAceptacionContrato?.toIso8601String(),
    };
  }

  ConductorModel copyWith({
    String? id,
    String? ci,
    String? nombre,
    String? apellido,
    String? email,
    String? telefono,
    String? fotoCIUrl,
    DateTime? fechaNacimiento,
    String? direccion,
    String? numeroLicencia,
    String? categoriaLicencia,
    DateTime? vigenciaLicencia,
    int? zonaId,
    String? numeroBus,
    String? empresa,
    double? saldoComisiones,
    String? estado,
    bool? contratoAceptado,
    DateTime? fechaAceptacionContrato,
    DateTime? createdAt,
  }) {
    return ConductorModel(
      id: id ?? this.id,
      ci: ci ?? this.ci,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      fotoCIUrl: fotoCIUrl ?? this.fotoCIUrl,
      fechaNacimiento: fechaNacimiento ?? this.fechaNacimiento,
      direccion: direccion ?? this.direccion,
      numeroLicencia: numeroLicencia ?? this.numeroLicencia,
      categoriaLicencia: categoriaLicencia ?? this.categoriaLicencia,
      vigenciaLicencia: vigenciaLicencia ?? this.vigenciaLicencia,
      zonaId: zonaId ?? this.zonaId,
      numeroBus: numeroBus ?? this.numeroBus,
      empresa: empresa ?? this.empresa,
      saldoComisiones: saldoComisiones ?? this.saldoComisiones,
      estado: estado ?? this.estado,
      contratoAceptado: contratoAceptado ?? this.contratoAceptado,
      fechaAceptacionContrato: fechaAceptacionContrato ?? this.fechaAceptacionContrato,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
