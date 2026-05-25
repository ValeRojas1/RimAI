class ApiConstants {
  // Configuración de la URL del servidor backend
  // - Emulador Android: usa 'http://10.0.2.2:8000'
  // - Dispositivo físico con USB y ADB Reverse ('adb reverse tcp:8000 tcp:8000'): usa 'http://localhost:8000'
  // - Dispositivo físico en la misma red Wi-Fi: usa la IP de tu PC, ej. 'http://192.168.1.4:8000'
  //
  // MODO ACTUAL: USB + ADB Reverse (más confiable, no depende de Wi-Fi ni firewall)
  static const String baseUrl = 'https://fastapi-production-4c60.up.railway.app';
}
