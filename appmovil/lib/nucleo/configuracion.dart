import 'package:flutter/foundation.dart';

/// Resuelve a qué servidor se conecta la app sin pedírselo al estudiante.
///
/// Prioridad:
///   1. `--dart-define=API_URL=https://mi-servidor` al compilar.
///   2. Un valor guardado desde el ajuste avanzado (solo para pruebas).
///   3. Un valor por defecto según la plataforma.
class ConfiguracionApi {
  const ConfiguracionApi._();

  static const String urlCompilada = String.fromEnvironment('API_URL');

  static bool get tieneUrlFija => urlCompilada.isNotEmpty;

  static String urlPorDefecto() {
    if (urlCompilada.isNotEmpty) return normalizar(urlCompilada);
    if (kIsWeb) return _urlWeb();
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 es el host anfitrión visto desde el emulador de Android.
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  /// En web hay dos escenarios distintos y se distinguen por el puerto:
  /// si la página se sirve desde un dominio real (80/443) la API vive en el
  /// mismo origen; si viene del servidor de desarrollo de Flutter (8080, 5000...)
  /// la API está aparte, en el 8000 del mismo host.
  static String _urlWeb() {
    final base = Uri.base;
    final esPuertoEstandar =
        (base.scheme == 'https' && base.port == 443) ||
        (base.scheme == 'http' && base.port == 80);
    if (esPuertoEstandar) return normalizar(base.origin);
    return '${base.scheme}://${base.host}:8000';
  }

  static String normalizar(String url) {
    final limpia = url.trim();
    return limpia.replaceAll(RegExp(r'/+$'), '');
  }

  static bool esValida(String url) {
    final destino = Uri.tryParse(normalizar(url));
    return destino != null &&
        destino.hasScheme &&
        (destino.scheme == 'http' || destino.scheme == 'https') &&
        destino.host.isNotEmpty;
  }
}
