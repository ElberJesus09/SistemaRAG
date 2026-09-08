import 'package:shared_preferences/shared_preferences.dart';

/// Guarda la sesión y la URL del servidor entre aperturas de la app.
///
/// Funciona igual en Android y en Web (allí usa localStorage por debajo).
class Almacenamiento {
  Almacenamiento(this._preferencias);

  static const _claveAcceso = 'dontramite_token_acceso';
  static const _claveRenovacion = 'dontramite_token_renovacion';
  static const _claveUrl = 'dontramite_url_api';

  final SharedPreferences _preferencias;

  static Future<Almacenamiento> abrir() async =>
      Almacenamiento(await SharedPreferences.getInstance());

  String? get tokenAcceso => _preferencias.getString(_claveAcceso);
  String? get tokenRenovacion => _preferencias.getString(_claveRenovacion);
  String? get urlGuardada => _preferencias.getString(_claveUrl);

  Future<void> guardarSesion(String? acceso, String? renovacion) async {
    if (acceso == null || acceso.isEmpty) {
      await _preferencias.remove(_claveAcceso);
    } else {
      await _preferencias.setString(_claveAcceso, acceso);
    }
    if (renovacion == null || renovacion.isEmpty) {
      await _preferencias.remove(_claveRenovacion);
    } else {
      await _preferencias.setString(_claveRenovacion, renovacion);
    }
  }

  Future<void> borrarSesion() async {
    await _preferencias.remove(_claveAcceso);
    await _preferencias.remove(_claveRenovacion);
  }

  Future<void> guardarUrl(String? url) async {
    if (url == null || url.isEmpty) {
      await _preferencias.remove(_claveUrl);
    } else {
      await _preferencias.setString(_claveUrl, url);
    }
  }
}
