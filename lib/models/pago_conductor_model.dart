class PagoConductorModel {
  final String id;
  final String conductorId;
  final String usuarioPasajeroCI;
  final String viajeId;
  final double montoBruto;
  final double comisionConductor;
  final double comisionEmpresa;
  final DateTime fechaPago;
  final String estado; // pendiente, abonado, retirado

  PagoConductorModel({
    required this.id,
    required this.conductorId,
    required this.usuarioPasajeroCI,
    required this.viajeId,
    required this.montoBruto,
    required this.comisionConductor,
    required this.comisionEmpresa,
    required this.fechaPago,
    required this.estado,
  });

  // Getters útiles
  double get totalCobrado => comisionConductor + comisionEmpresa;

  String get estadoBadge {
    switch (estado) {
      case 'pendiente':
        return '⏳ Pendiente';
      case 'abonado':
        return '✓ Abonado';
      case 'retirado':
        return '💸 Retirado';
      default:
        return estado;
    }
  }

  String get detalleComisiones {
    return 'Conductor: Bs ${comisionConductor.toStringAsFixed(2)} | Empresa: Bs ${comisionEmpresa.toStringAsFixed(2)}';
  }

  // Serialización
  factory PagoConductorModel.fromJson(Map<String, dynamic> json) {
    return PagoConductorModel(
      id: json['id'] ?? '',
      conductorId: json['conductor_id'] ?? '',
      usuarioPasajeroCI: json['usuario_pasajero_ci'] ?? '',
      viajeId: json['viaje_id'] ?? '',
      montoBruto: double.tryParse(json['monto_bruto'].toString()) ?? 0.0,
      comisionConductor: double.tryParse(json['comision_conductor'].toString()) ?? 0.0,
      comisionEmpresa: double.tryParse(json['comision_empresa'].toString()) ?? 0.0,
      fechaPago: DateTime.parse(json['fecha_pago'] ?? DateTime.now().toIso8601String()),
      estado: json['estado'] ?? 'pendiente',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conductor_id': conductorId,
      'usuario_pasajero_ci': usuarioPasajeroCI,
      'viaje_id': viajeId,
      'monto_bruto': montoBruto,
      'comision_conductor': comisionConductor,
      'comision_empresa': comisionEmpresa,
      'fecha_pago': fechaPago.toIso8601String(),
      'estado': estado,
    };
  }

  PagoConductorModel copyWith({
    String? id,
    String? conductorId,
    String? usuarioPasajeroCI,
    String? viajeId,
    double? montoBruto,
    double? comisionConductor,
    double? comisionEmpresa,
    DateTime? fechaPago,
    String? estado,
  }) {
    return PagoConductorModel(
      id: id ?? this.id,
      conductorId: conductorId ?? this.conductorId,
      usuarioPasajeroCI: usuarioPasajeroCI ?? this.usuarioPasajeroCI,
      viajeId: viajeId ?? this.viajeId,
      montoBruto: montoBruto ?? this.montoBruto,
      comisionConductor: comisionConductor ?? this.comisionConductor,
      comisionEmpresa: comisionEmpresa ?? this.comisionEmpresa,
      fechaPago: fechaPago ?? this.fechaPago,
      estado: estado ?? this.estado,
    );
  }
}
