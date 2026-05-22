# TransitApp - Sistema de Transporte Inteligente

## 📱 Descripción General

TransitApp es una aplicación multiplataforma (iOS/Android) que implementa un sistema integral de transporte con:

- ✅ **Una cuenta por usuario** (validación mediante CI único)
- ✅ **Descuentos dinámicos** según perfil del usuario
- ✅ **Escaneo de QR** del Carnet de Identidad
- ✅ **Generación de QR dinámico** para viajes
- ✅ **Integración con PayPal** para recargas de saldo
- ✅ **Validación en tiempo real** en vehículos

---

## 🔐 SOLUCIÓN: Una Sola Cuenta por CI

### Estrategia Principal

El **Carnet de Identidad (CI)** es el identificador único e inmutable en el sistema. 

**Flujo de validación:**

```
┌─────────────────────────────────────┐
│  Usuario intenta crear cuenta       │
│  Escanea QR del CI o lo ingresa     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  App consulta al backend:           │
│  "¿Existe un usuario con CI XXX?"   │
└──────────────┬──────────────────────┘
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
    ✅ NO EXISTE   ❌ YA EXISTE
    Proceder con   Mostrar error:
    registro       "Este CI ya tiene cuenta"
```

### Implementación en Frontend (Flutter)

#### 1. **Validación antes de Registro** [`api_service.dart`]

```dart
Future<bool> ciYaExiste(String ci) async {
  final response = await http.get(
    Uri.parse('$baseUrl/verificar-ci/$ci'),
    headers: _headers,
  );
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data['existe'] == true;
  }
  return false;
}
```

#### 2. **En la Pantalla de Registro** [`registro_completar_screen.dart`]

```dart
Future<void> registrar() async {
  // Primero verifica si el CI ya existe
  final existe = await _apiService.ciYaExiste(_ci);
  
  if (existe) {
    mostrarError(
      '❌ Este CI ya tiene una cuenta registrada.\n'
      'No se pueden crear múltiples cuentas por usuario.'
    );
    return;
  }
  
  // Si no existe, procede con el registro
  await _apiService.registrarUsuario(...);
}
```

### Implementación en Backend (Laravel/Node.js)

#### 1. **Endpoint de Verificación**

```php
// Laravel Route
Route::get('/api/verificar-ci/{ci}', 'AuthController@verificarCI');

// Controlador
public function verificarCI($ci)
{
    $usuario = Usuario::where('ci', $ci)->first();
    return response()->json([
        'existe' => $usuario !== null,
    ]);
}
```

#### 2. **Validación en Registro**

```php
public function registrar(Request $request)
{
    // Verificar que el CI sea único
    $request->validate([
        'ci' => 'required|unique:usuarios,ci',
        'email' => 'required|unique:usuarios,email',
        'nombre' => 'required|string',
    ]);
    
    // Si llega aquí, el CI es único
    $usuario = Usuario::create($request->all());
    
    return response()->json([
        'usuario' => $usuario,
        'token' => $usuario->generateToken(),
    ], 201);
}
```

#### 3. **Base de Datos - Restricción SQL**

```sql
CREATE TABLE usuarios (
    id INT PRIMARY KEY AUTO_INCREMENT,
    ci VARCHAR(20) UNIQUE NOT NULL,  -- ⭐ UNIQUE CONSTRAINT
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    tipoUsuario ENUM('estudiante', 'adultomayor', 'discapacidad', 'general'),
    saldo DECIMAL(10, 2) DEFAULT 0,
    fechaNacimiento DATE,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_ci UNIQUE (ci)  -- Duplicada por claridad
);
```

---

## 📋 Flujo Completo de Registro con Validación de CI

### Pantalla 1: Escanear QR del CI

```
┌──────────────────────────────────┐
│  📱 ESCANEAR CARNET              │
├──────────────────────────────────┤
│                                  │
│      [📷 Escanear QR]            │
│      [O INGRESAR MANUALMENTE]    │
│                                  │
│  CI: 12345678                    │
│  Nombre: Juan Pérez              │
│  Fecha Nac: 15/03/1995           │
│                                  │
│     [CONTINUAR] → (a pantalla 2) │
└──────────────────────────────────┘
```

### Pantalla 2: Completar Registro

```
┌──────────────────────────────────┐
│  ✏️ COMPLETAR REGISTRO            │
├──────────────────────────────────┤
│                                  │
│  CI: 12345678 (verificado)       │
│                                  │
│  Email: juan@estudiante.univ...  │
│  (Verificar dominio universitario│
│                                  │
│  Tipo de Usuario:                │
│  ☑️ Estudiante                    │
│  ☐ Adulto Mayor                  │
│  ☐ Discapacidad                  │
│  ☐ General                       │
│                                  │
│  PIN (4 dígitos): ****           │
│  Confirmar PIN: ****             │
│                                  │
│     [REGISTRAR]                  │
│                                  │
│  ⚠️ NOTA:                        │
│  Si este CI ya existe, el        │
│  registro será rechazado         │
└──────────────────────────────────┘
```

### Respuesta de Éxito

```json
{
  "exito": true,
  "usuario": {
    "ci": "12345678",
    "nombre": "Juan Pérez",
    "apellido": "López",
    "email": "juan@estudiante.univ.edu.bo",
    "tipoUsuario": "estudiante",
    "saldo": 0.0,
    "descuento": 0.50
  },
  "token": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

### Respuesta de Error (CI Duplicado)

```json
{
  "exito": false,
  "codigo": "CI_DUPLICADO",
  "mensaje": "Este CI ya tiene una cuenta registrada. No se pueden crear múltiples cuentas por usuario.",
  "sugerencia": "Si olvidaste tu contraseña, usa 'Recuperar contraseña' en el login"
}
```

---

## 🎯 Descuentos Dinámicos por Perfil

| Tipo | Condición | Descuento | Tarifa Base | Final |
|------|-----------|-----------|------------|-------|
| **Estudiante** | Correo U válido | 50% | Bs 2.50 | **Bs 1.25** |
| **Adulto Mayor** | Edad ≥ 60 años | 30% | Bs 2.50 | **Bs 1.75** |
| **Discapacidad** | Certificado + carnet | 100% | Bs 2.50 | **Bs 0.00** (Gratis) |
| **General** | Ninguna | 0% | Bs 2.50 | **Bs 2.50** |

**Implementación:**

```dart
// En helpers.dart
static double calcularTarifa({
  required String tipoUsuario,
  double tarifaBase = 2.50,
}) {
  const descuentos = {
    'estudiante': 0.50,
    'adultomayor': 0.30,
    'discapacidad': 1.00,
    'general': 0.00,
  };
  
  final descuento = descuentos[tipoUsuario.toLowerCase()] ?? 0.0;
  return tarifaBase * (1 - descuento);
}
```

---

## 📲 Generación de QR Dinámico para Viajes

Cuando el usuario genera un QR para viajar:

```
Datos codificados en el QR:
"usuarioCi|tipoUsuario|tarifaAplicada|saldoRestante|timestamp|sessionId"

Ejemplo:
"12345678|estudiante|1.25|98.75|1715721600000|abc-123-def"
```

**Validación en vehículo (máximo 30 segundos):**

```dart
static Map<String, dynamic>? parsearQRViaje(String qrString) {
  final partes = qrString.split('|');
  final timestamp = int.parse(partes[4]);
  final ahora = DateTime.now().millisecondsSinceEpoch;
  final diferencia = (ahora - timestamp) ~/ 1000;
  
  if (diferencia > 30) {
    return {'valido': false, 'razon': 'QR expirado'};
  }
  
  return {
    'valido': true,
    'usuarioCi': partes[0],
    'tarifaAplicada': double.parse(partes[2]),
    'saldoRestante': double.parse(partes[3]),
    'segundosRestantes': 30 - diferencia,
  };
}
```

---

## 🔧 Archivos Clave del Proyecto

```
lib/
├── models/
│   ├── usuario_model.dart          ⭐ Con cálculo de descuentos
│   ├── viaje_model.dart
│   ├── recarga_model.dart
│   └── qr_viaje_model.dart
├── services/
│   ├── api_service.dart            ⭐ Verificación de CI
│   ├── storage_service.dart        ⭐ Almacenamiento local
│   ├── qr_service.dart             ⭐ Generación y lectura
│   └── ci_extractor_service.dart   ⭐ Extracción de datos CI
├── screens/
│   ├── login_screen.dart
│   ├── registro_escanear_screen.dart
│   ├── registro_completar_screen.dart
│   ├── home_screen.dart
│   ├── recarga_screen.dart
│   └── perfil_screen.dart
├── utils/
│   └── helpers.dart                ⭐ Cálculos y validaciones
└── main.dart                       ⭐ Punto de entrada
```

---

## 🚀 Cómo Ejecutar

### 1. Instalar dependencias

```bash
flutter pub get
```

### 2. Configurar el servidor backend

Actualiza la URL en [api_service.dart](lib/services/api_service.dart):

```dart
static const String baseUrl = 'http://TU_IP:8000/api';
// Para pruebas locales: 'http://localhost:8000/api'
// Para producción: 'http://tu-servidor-produccion.com/api'
```

### 3. Ejecutar la aplicación

```bash
flutter run
```

---

## ✅ Checklist de Validación

- [x] CI es identificador único (constraint UNIQUE en BD)
- [x] Verificación de CI antes de crear cuenta
- [x] Descuentos dinámicos según tipo de usuario
- [x] Escaneo de QR del Carnet de Identidad
- [x] Generación de QR dinámico con validez de 30s
- [x] Integración con PayPal (Sandbox)
- [x] Almacenamiento local de token
- [x] Historial de viajes
- [x] Validación de saldo suficiente

---

## 📞 Soporte Técnico

**Problemas comunes:**

| Problema | Solución |
|----------|----------|
| "CI ya registrado" | Es el comportamiento esperado. El usuario debe usar credenciales existentes. |
| QR expira rápido | Genera uno nuevo. Tiene máximo 30 segundos de validez. |
| PayPal no funciona | Verifica estar en Sandbox y usar credenciales de prueba. |
| No recuerdo PIN | En v2, implementar "Recuperar PIN" enviando código a email. |

---

**Desarrollado con Flutter 3.x + Dart 3.x**  
**Backend: Laravel 10+ o Node.js + Express**  
**Base de Datos: MySQL 8.0+**
