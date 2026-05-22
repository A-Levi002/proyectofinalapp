# Diagnóstico de Conexión Supabase

## Credenciales Configuradas
- **URL**: `https://qfbdaxhyomljghshvjnn.supabase.co`
- **Anon Key**: `sb_publishable_eJWHVV57NNaqJcfuUNy8_g_zc2sr6q6`
- **Base de Datos**: PostgreSQL en `aws-1-us-east-2.pooler.supabase.com:6543`

## Si Supabase No Responde:

### 1. **Verificar Conexión de Internet**
```bash
ping 8.8.8.8
```

### 2. **Ver Logs en Flutter**
Abre la consola de Flutter y busca mensajes:
```
[APP] Inicializando Supabase...
[SPLASH] Verificando conexión a Supabase...
[SUPABASE] Verificando conexión...
[SUPABASE] ✓ Conexión exitosa
```

### 3. **Probar Conexión Manual**
Desde la terminal:
```bash
# Probar ping al host
ping aws-1-us-east-2.pooler.supabase.com

# O con curl (probar URL REST)
curl -i https://qfbdaxhyomljghshvjnn.supabase.co/rest/v1/usuarios
```

### 4. **Posibles Problemas**
- ❌ Credenciales expiradas o incorrectas → Regenerar en Supabase Dashboard
- ❌ Base de datos no activa → Revisar en Supabase Dashboard
- ❌ Firewall/VPN bloqueando → Verificar conexión de red
- ❌ RLS (Row Level Security) muy restrictivo → Ajustar políticas en DB

### 5. **Si Sigues Sin Poder Conectar**
1. Ve a https://app.supabase.com
2. Selecciona tu proyecto
3. Abre **Settings** → **API**
4. Verifica que los valores coincidan con `main.dart`
5. Si han cambiado, actualiza en el código y ejecuta `flutter clean` + `flutter pub get`

## URLs de Referencia
- **Dashboard**: https://app.supabase.com
- **API REST**: https://qfbdaxhyomljghshvjnn.supabase.co/rest/v1
- **WebSocket**: wss://qfbdaxhyomljghshvjnn.supabase.co/realtime/v1

## Siguiente Paso
Ejecuta la app y revisa los logs en la consola de Flutter para identificar el error específico.
