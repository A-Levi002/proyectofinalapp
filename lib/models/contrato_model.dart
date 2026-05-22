class ContratoModel {
  final String id;
  final String conductorId;
  final String empresa;
  final int zonaId;
  final DateTime fechaInicio;
  final DateTime? fechaFinPropuesta;
  final String documentoURL;
  final String terminosCondiciones;
  final double comisionPorcentaje;
  final String? horarioTrabajo;
  final String? rutasPermitidas;
  final String estado; // pendiente, aceptado, rechazado, suspendido
  final String? razonRechazo;
  final DateTime fechaSolicitud;
  final DateTime? fechaRespuesta;
  final int? adminId;

  ContratoModel({
    required this.id,
    required this.conductorId,
    required this.empresa,
    required this.zonaId,
    required this.fechaInicio,
    this.fechaFinPropuesta,
    required this.documentoURL,
    required this.terminosCondiciones,
    required this.comisionPorcentaje,
    this.horarioTrabajo,
    this.rutasPermitidas,
    required this.estado,
    this.razonRechazo,
    required this.fechaSolicitud,
    this.fechaRespuesta,
    this.adminId,
  });

  // Getters útiles
  String get estadoBadge {
    switch (estado) {
      case 'pendiente':
        return '⏳ Pendiente';
      case 'aceptado':
        return '✓ Aceptado';
      case 'rechazado':
        return '✗ Rechazado';
      case 'suspendido':
        return '⚠ Suspendido';
      default:
        return estado;
    }
  }

  bool get estaPendiente => estado == 'pendiente';
  bool get estaAceptado => estado == 'aceptado';
  bool get fueRechazado => estado == 'rechazado';

  // Serialización
  factory ContratoModel.fromJson(Map<String, dynamic> json) {
    return ContratoModel(
      id: json['id'] ?? '',
      conductorId: json['conductor_id'] ?? '',
      empresa: json['empresa'] ?? '',
      zonaId: json['zona_id'] ?? 1,
      fechaInicio: DateTime.parse(json['fecha_inicio'] ?? DateTime.now().toIso8601String()),
      fechaFinPropuesta: json['fecha_fin_propuesta'] != null 
          ? DateTime.parse(json['fecha_fin_propuesta']) 
          : null,
      documentoURL: json['documento_contrato'] ?? '',
      terminosCondiciones: json['terminos_condiciones'] ?? '',
      comisionPorcentaje: double.tryParse(json['comision_porcentaje'].toString()) ?? 10.0,
      horarioTrabajo: json['horario_trabajo'],
      rutasPermitidas: json['rutas_permitidas'],
      estado: json['estado'] ?? 'pendiente',
      razonRechazo: json['razon_rechazo'],
      fechaSolicitud: DateTime.parse(json['fecha_solicitud'] ?? DateTime.now().toIso8601String()),
      fechaRespuesta: json['fecha_respuesta'] != null 
          ? DateTime.parse(json['fecha_respuesta']) 
          : null,
      adminId: json['admin_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conductor_id': conductorId,
      'empresa': empresa,
      'zona_id': zonaId,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin_propuesta': fechaFinPropuesta?.toIso8601String(),
      'documento_contrato': documentoURL,
      'terminos_condiciones': terminosCondiciones,
      'comision_porcentaje': comisionPorcentaje,
      'horario_trabajo': horarioTrabajo,
      'rutas_permitidas': rutasPermitidas,
      'estado': estado,
      'razon_rechazo': razonRechazo,
      'fecha_solicitud': fechaSolicitud.toIso8601String(),
      'fecha_respuesta': fechaRespuesta?.toIso8601String(),
      'admin_id': adminId,
    };
  }

  ContratoModel copyWith({
    String? id,
    String? conductorId,
    String? empresa,
    int? zonaId,
    DateTime? fechaInicio,
    DateTime? fechaFinPropuesta,
    String? documentoURL,
    String? terminosCondiciones,
    double? comisionPorcentaje,
    String? horarioTrabajo,
    String? rutasPermitidas,
    String? estado,
    String? razonRechazo,
    DateTime? fechaSolicitud,
    DateTime? fechaRespuesta,
    int? adminId,
  }) {
    return ContratoModel(
      id: id ?? this.id,
      conductorId: conductorId ?? this.conductorId,
      empresa: empresa ?? this.empresa,
      zonaId: zonaId ?? this.zonaId,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFinPropuesta: fechaFinPropuesta ?? this.fechaFinPropuesta,
      documentoURL: documentoURL ?? this.documentoURL,
      terminosCondiciones: terminosCondiciones ?? this.terminosCondiciones,
      comisionPorcentaje: comisionPorcentaje ?? this.comisionPorcentaje,
      horarioTrabajo: horarioTrabajo ?? this.horarioTrabajo,
      rutasPermitidas: rutasPermitidas ?? this.rutasPermitidas,
      estado: estado ?? this.estado,
      razonRechazo: razonRechazo ?? this.razonRechazo,
      fechaSolicitud: fechaSolicitud ?? this.fechaSolicitud,
      fechaRespuesta: fechaRespuesta ?? this.fechaRespuesta,
      adminId: adminId ?? this.adminId,
    );
  }
}
