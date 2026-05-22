class UsuarioModel {
  final String ci;
  final String nombre;
  final String apellido;
  final String email;
  final String telefono;
  final String tipoUsuario;
  final double saldo;
  final DateTime? fechaNacimiento;
  final DateTime fechaRegistro;
  final bool emailVerificado;
  final String? fotoCIUrl;
  final String? fotoPerfil;      // ← NUEVA: foto elegida por el usuario
  final String? certificadoUrl;
  final bool activo;

  UsuarioModel({
    required this.ci,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.telefono,
    required this.tipoUsuario,
    required this.saldo,
    this.fechaNacimiento,
    required this.fechaRegistro,
    required this.emailVerificado,
    this.fotoCIUrl,
    this.fotoPerfil,
    this.certificadoUrl,
    required this.activo,
  });

  int get edad {
    if (fechaNacimiento == null) return 0;
    final hoy = DateTime.now();
    int edad = hoy.year - fechaNacimiento!.year;
    if (hoy.month < fechaNacimiento!.month ||
        (hoy.month == fechaNacimiento!.month && hoy.day < fechaNacimiento!.day)) {
      edad--;
    }
    return edad;
  }

  double get descuento {
    switch (tipoUsuario.toLowerCase()) {
      case 'estudiante':   return 0.50;
      case 'adultomayor':  return edad >= 60 ? 0.30 : 0.0;
      case 'discapacidad': return 1.00;
      default:             return 0.0;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'ci': ci,
      'nombre': nombre,
      'apellido': apellido,
      'email': email,
      'telefono': telefono,
      'tipoUsuario': tipoUsuario,
      'saldo': saldo,
      'fechaNacimiento': fechaNacimiento?.toIso8601String(),
      'emailVerificado': emailVerificado,
      'fotoCIUrl': fotoCIUrl,
      'fotoPerfil': fotoPerfil,
      'certificadoUrl': certificadoUrl,
      'activo': activo,
    };
  }

  factory UsuarioModel.fromJson(Map<String, dynamic> json) {
    String? str(String snake, [String? camel]) =>
        json[snake] as String? ?? (camel != null ? json[camel] as String? : null);
    bool? boo(String snake, [String? camel]) =>
        json[snake] as bool? ?? (camel != null ? json[camel] as bool? : null);

    DateTime? fechaNac;
    final fnRaw = str('fecha_nacimiento', 'fechaNacimiento');
    if (fnRaw != null && fnRaw.isNotEmpty) {
      try { fechaNac = DateTime.parse(fnRaw); } catch (_) {}
    }

    DateTime fechaReg = DateTime.now();
    final frRaw = str('created_at', 'fechaRegistro') ?? str('updated_at');
    if (frRaw != null && frRaw.isNotEmpty) {
      try { fechaReg = DateTime.parse(frRaw); } catch (_) {}
    }

    return UsuarioModel(
      ci: str('ci') ?? '',
      nombre: str('nombre') ?? '',
      apellido: str('apellido') ?? '',
      email: str('email') ?? '',
      telefono: str('telefono') ?? '',
      tipoUsuario: str('tipo_usuario', 'tipoUsuario') ?? 'general',
      saldo: (json['saldo'] as num?)?.toDouble() ?? 0.0,
      fechaNacimiento: fechaNac,
      fechaRegistro: fechaReg,
      emailVerificado: boo('email_verificado', 'emailVerificado') ?? false,
      fotoCIUrl: str('foto_ci_url', 'fotoCIUrl'),
      fotoPerfil: str('foto_perfil_url', 'fotoPerfil'),
      certificadoUrl: str('certificado_url', 'certificadoUrl'),
      activo: boo('activo') ?? true,
    );
  }

  UsuarioModel copyWith({
    String? ci,
    String? nombre,
    String? apellido,
    String? email,
    String? telefono,
    String? tipoUsuario,
    double? saldo,
    DateTime? fechaNacimiento,
    DateTime? fechaRegistro,
    bool? emailVerificado,
    String? fotoCIUrl,
    String? fotoPerfil,
    String? certificadoUrl,
    bool? activo,
  }) {
    return UsuarioModel(
      ci: ci ?? this.ci,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      tipoUsuario: tipoUsuario ?? this.tipoUsuario,
      saldo: saldo ?? this.saldo,
      fechaNacimiento: fechaNacimiento ?? this.fechaNacimiento,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      emailVerificado: emailVerificado ?? this.emailVerificado,
      fotoCIUrl: fotoCIUrl ?? this.fotoCIUrl,
      fotoPerfil: fotoPerfil ?? this.fotoPerfil,
      certificadoUrl: certificadoUrl ?? this.certificadoUrl,
      activo: activo ?? this.activo,
    );
  }

  @override
  String toString() =>
      'Usuario(ci: $ci, nombre: $nombre, tipoUsuario: $tipoUsuario, saldo: $saldo)';
}
