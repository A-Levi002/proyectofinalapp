// Colores de la aplicación
class AppColors {
  static const int primary = 0xFF6B46C1; // Morado
  static const int primaryDark = 0xFF5A3CA5;
  static const int accent = 0xFF10B981; // Verde
  static const int warning = 0xFFF59E0B; // Amarillo
  static const int error = 0xFFEF4444; // Rojo
  static const int success = 0xFF10B981;
  static const int background = 0xFFF9FAFB;
  static const int textPrimary = 0xFF1F2937;
  static const int textSecondary = 0xFF6B7280;
  static const int border = 0xFFE5E7EB;
}

// Textos fijos
class AppTexts {
  // Títulos
  static const appTitle = 'TransitApp';
  static const appSubtitle = 'Sistema de Transporte Inteligente';

  // Autenticación
  static const loginTitle = 'Acceso con Carnet de Identidad';
  static const loginCIHint = 'Ej: 12345678';
  static const loginPINHint = '****';

  // Registro
  static const registroTitle = 'Crear Nueva Cuenta';
  static const registroSubtitle = 'Una sola cuenta por Carnet de Identidad';

  // Errores
  static const errorCIDuplicate =
      'Este CI ya tiene una cuenta registrada. No se pueden crear múltiples cuentas por usuario.';
  static const errorCIInvalido = 'CI inválido (7-10 dígitos)';
  static const errorPINInvalido = 'PIN debe tener 4 dígitos';
  static const errorSaldoInsuficiente = 'Saldo insuficiente para este viaje';
  static const errorQRExpirado = 'QR expirado (máximo 30 segundos)';
  static const errorConexion = 'Error de conexión con el servidor';

  // Mensajes de éxito
  static const successRegistro = '¡Cuenta creada exitosamente!';
  static const successLogin = '¡Bienvenido!';
  static const successRecarga = '¡Recarga completada!';

  // Advertencias
  static const warningUnicuencia =
      '⚠️ IMPORTANTE: Solo puedes tener UNA cuenta por Carnet de Identidad.';
}

// Configuración API
class ApiConfig {
  // IMPORTANTE: Actualiza esto con tu IP/servidor
  static const String baseUrl = 'http://192.168.1.100:8000/api';

  // Endpoints
  static const String verifyCI = '/verificar-ci/';
  static const String register = '/auth/registro';
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String getUserProfile = '/usuario/perfil';
  static const String getUserTrips = '/usuario/viajes';
  static const String createPayPalOrder = '/paypal/crear-orden';
  static const String capturePayPalOrder = '/paypal/capturar-orden';
  static const String generateQR = '/viaje/generar-qr';
  static const String validateQR = '/viaje/validar-qr';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

// Configuración de tarifas
class TariffConfig {
  static const double baseTicketPrice = 2.50; // Bs 2.50

  static const Map<String, double> discountsByUserType = {
    'estudiante': 0.50, // 50%
    'adultomayor': 0.30, // 30%
    'discapacidad': 1.00, // 100% (gratuito)
    'general': 0.00, // 0%
  };

  static const Map<String, String> userTypeDescriptions = {
    'estudiante': 'Estudiante (50% descuento)',
    'adultomayor': 'Adulto Mayor (30% descuento)',
    'discapacidad': 'Persona con Discapacidad (Gratuito)',
    'general': 'Usuario General (Sin descuento)',
  };
}

// Configuración de validación
class ValidationConfig {
  // CI: 7-10 dígitos
  static const int minCILength = 7;
  static const int maxCILength = 10;

  // PIN: exactamente 4 dígitos
  static const int pinLength = 4;

  // Teléfono: 8 dígitos en Bolivia
  static const int phoneLength = 8;

  // Email universitario - dominios válidos
  static const List<String> validUniversityDomains = [
    '@estudiante.univ.edu.bo',
    '@umsa.bo',
    '@upds.edu.bo',
    '@ucb.edu.bo',
    '@umsm.edu.pe',
    '@uni.edu.pe',
    '@pucp.edu.pe',
    '@usil.edu.pe',
  ];

  // Edad mínima
  static const int minAge = 18;

  // Edad para adulto mayor
  static const int seniorAge = 60;
}

// Configuración QR
class QRConfig {
  // Validez del QR en segundos
  static const int qrValiditySeconds = 30;

  // Tamaño del QR generado
  static const double qrSize = 200;

  // Versión QR
  static const String qrVersion = 'auto';
}

// Configuración PayPal
class PayPalConfig {
  // Sandbox o Live
  static const String environment = 'sandbox'; // Cambiar a 'live' en producción

  // URLs
  static const String sandboxUrl = 'https://sandbox.paypal.com';
  static const String liveUrl = 'https://www.paypal.com';

  // Client ID (obtener de PayPal Developer)
  static const String clientId = 'TU_CLIENT_ID_AQUI';

  // Moneda
  static const String currency = 'BOB';

  // Montos permitidos para recarga
  static const List<double> rechargeAmounts = [
    10.0, // Bs 10
    20.0, // Bs 20
    50.0, // Bs 50
    100.0, // Bs 100
  ];
}

// Configuración de almacenamiento
class StorageConfig {
  static const String tokenKey = 'auth_token';
  static const String userDataKey = 'user_data';
  static const String ciKey = 'user_ci';
  static const String lastLoginKey = 'last_login';
  static const String themeKey = 'app_theme';
  static const String languageKey = 'app_language';
}

// Rutas de navegación
class Routes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String registerScan = '/registro-escanear';
  static const String registerComplete = '/registro-completar';
  static const String home = '/home';
  static const String recharge = '/recarga';
  static const String profile = '/perfil';
  static const String trips = '/viajes';
  static const String generateQR = '/generar-qr';
  static const String validator = '/validador'; // Para chofer
  static const String settings = '/configuracion';
}

// Duración de animaciones
class AnimationDurations {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 500);
}

// Límites de la aplicación
class AppLimits {
  // Máximo de intentos de login fallidos
  static const int maxLoginAttempts = 3;

  // Tiempo de bloqueo después de intentos fallidos (minutos)
  static const int lockoutDuration = 15;

  // Máximo de caracteres para campos
  static const int maxNameLength = 100;
  static const int maxEmailLength = 255;
  static const int maxPhoneLength = 20;
  static const int maxObservationLength = 500;

  // Mínimo de saldo para alertar
  static const double minBalanceAlert = 5.0;

  // Máximo de transacciones por día
  static const int maxDailyTransactions = 100;
}

// Patrones regex
class RegexPatterns {
  // CI: solo números
  static const String ciPattern = r'^[0-9]{7,10}$';

  // PIN: 4 dígitos
  static const String pinPattern = r'^[0-9]{4}$';

  // Email
  static const String emailPattern =
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';

  // Teléfono (Bolivia)
  static const String phonePattern = r'^[0-9]{8,12}$';

  // Nombre: sin números
  static const String namePattern = r'^[a-zA-Z\s\u00E1\u00E9\u00ED\u00F3\u00FA\u00F1]+$';
}
