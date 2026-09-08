import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'excepciones.dart';
import 'modelos.dart';

typedef GuardarSesion = Future<void> Function(String? acceso, String? renovacion);

/// Único punto de contacto con la API. Renueva la sesión sola cuando el
/// token de acceso caduca, así el estudiante no ve un 401 a la hora de uso.
class ClienteApi {
  ClienteApi({required this.urlBase, this.alGuardarSesion, this.alPerderSesion});

  static const _rutaBase = '/api/v1';
  static const _esperaNormal = Duration(seconds: 30);
  static const _esperaLarga = Duration(seconds: 120);

  String urlBase;
  String? tokenAcceso;
  String? tokenRenovacion;
  GuardarSesion? alGuardarSesion;
  void Function()? alPerderSesion;

  Future<void>? _renovacionEnCurso;

  bool get tieneSesion => tokenAcceso != null && tokenAcceso!.isNotEmpty;

  void limpiarSesion() {
    tokenAcceso = null;
    tokenRenovacion = null;
  }

  // ----------------------------- Autenticación -----------------------------

  Future<Sesion> registrar({
    required String correo,
    required String contrasena,
    required String nombreCompleto,
  }) async {
    final datos = await _pedir('POST', '/auth/register', cuerpo: {
      'email': correo,
      'password': contrasena,
      'full_name': nombreCompleto,
    }, autenticado: false);
    return await _adoptar(Sesion.desdeJson(_mapa(datos)));
  }

  Future<Sesion> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final datos = await _pedir('POST', '/auth/login', cuerpo: {
      'email': correo,
      'password': contrasena,
    }, autenticado: false);
    return await _adoptar(Sesion.desdeJson(_mapa(datos)));
  }

  Future<Perfil> miPerfil() async =>
      Perfil.desdeJson(_mapa(await _pedir('GET', '/auth/me')));

  Future<Perfil> actualizarNombre(String nombreCompleto) async => Perfil.desdeJson(
    _mapa(await _pedir('PATCH', '/auth/me', cuerpo: {'full_name': nombreCompleto})),
  );

  Future<void> cambiarContrasena({
    required String actual,
    required String nueva,
  }) async {
    await _pedir('POST', '/auth/password', cuerpo: {
      'current_password': actual,
      'new_password': nueva,
    });
  }

  // ----------------------------- Conversaciones ----------------------------

  Future<List<Conversacion>> listarConversaciones() async {
    final datos = await _pedir('GET', '/chat/conversations?limit=50');
    return _lista(datos).map(Conversacion.desdeJson).toList();
  }

  Future<Conversacion> crearConversacion({String? titulo}) async => Conversacion.desdeJson(
    _mapa(await _pedir('POST', '/chat/conversations', cuerpo: {'title': titulo})),
  );

  Future<List<Intercambio>> mensajesDe(String conversacionId) async {
    final datos = await _pedir('GET', '/chat/conversations/$conversacionId/messages');
    return _lista(datos).map(Intercambio.desdeJson).toList();
  }

  Future<Conversacion> renombrarConversacion(String id, String titulo) async =>
      Conversacion.desdeJson(
        _mapa(await _pedir('PATCH', '/chat/conversations/$id', cuerpo: {'title': titulo})),
      );

  Future<void> eliminarConversacion(String id) async {
    await _pedir('DELETE', '/chat/conversations/$id');
  }

  Future<RespuestaChat> preguntar({
    required String pregunta,
    required String conversacionId,
  }) async {
    final datos = await _pedir(
      'POST',
      '/chat/ask',
      cuerpo: {'question': pregunta, 'conversation_id': conversacionId},
      espera: _esperaLarga,
    );
    return RespuestaChat.desdeJson(_mapa(datos));
  }

  Future<void> valorar({required String preguntaId, required int valoracion}) async {
    await _pedir('POST', '/chat/questions/$preguntaId/feedback',
        cuerpo: {'rating': valoracion});
  }

  // ------------------------------- Internos --------------------------------

  Future<Sesion> _adoptar(Sesion sesion) async {
    if (sesion.iniciada) {
      tokenAcceso = sesion.tokenAcceso;
      tokenRenovacion = sesion.tokenRenovacion;
      await alGuardarSesion?.call(sesion.tokenAcceso, sesion.tokenRenovacion);
    }
    return sesion;
  }

  Uri _uri(String ruta) => Uri.parse('$urlBase$_rutaBase$ruta');

  Map<String, String> _cabeceras({required bool conCuerpo, required bool autenticado}) {
    final cabeceras = <String, String>{'Accept': 'application/json'};
    if (conCuerpo) cabeceras['Content-Type'] = 'application/json';
    if (autenticado && tieneSesion) cabeceras['Authorization'] = 'Bearer $tokenAcceso';
    return cabeceras;
  }

  Future<http.Response> _enviar(
    String metodo,
    String ruta, {
    Object? cuerpo,
    required bool autenticado,
    required Duration espera,
  }) async {
    final destino = _uri(ruta);
    final cabeceras = _cabeceras(conCuerpo: cuerpo != null, autenticado: autenticado);
    final codificado = cuerpo == null ? null : jsonEncode(cuerpo);
    try {
      switch (metodo) {
        case 'GET':
          return await http.get(destino, headers: cabeceras).timeout(espera);
        case 'POST':
          return await http
              .post(destino, headers: cabeceras, body: codificado)
              .timeout(espera);
        case 'PATCH':
          return await http
              .patch(destino, headers: cabeceras, body: codificado)
              .timeout(espera);
        case 'DELETE':
          return await http.delete(destino, headers: cabeceras).timeout(espera);
        default:
          throw ErrorApi('Metodo no soportado: $metodo');
      }
    } on TimeoutException {
      throw const ErrorApi('El servidor tardo demasiado en responder.');
    } on ErrorApi {
      rethrow;
    } catch (_) {
      throw const ErrorApi(
        'No se pudo conectar con el servidor. Revisa tu conexion e intenta otra vez.',
      );
    }
  }

  Future<dynamic> _pedir(
    String metodo,
    String ruta, {
    Object? cuerpo,
    bool autenticado = true,
    Duration espera = _esperaNormal,
  }) async {
    var respuesta =
        await _enviar(metodo, ruta, cuerpo: cuerpo, autenticado: autenticado, espera: espera);

    if (respuesta.statusCode == 401 && autenticado && tieneSesion) {
      final renovada = await _renovarSesion();
      if (!renovada) {
        alPerderSesion?.call();
        throw const SesionExpirada();
      }
      respuesta = await _enviar(metodo, ruta,
          cuerpo: cuerpo, autenticado: autenticado, espera: espera);
      if (respuesta.statusCode == 401) {
        limpiarSesion();
        alPerderSesion?.call();
        throw const SesionExpirada();
      }
    }
    return _interpretar(respuesta);
  }

  /// Varias peticiones pueden fallar a la vez; solo se renueva una sola vez.
  Future<bool> _renovarSesion() async {
    final renovacion = tokenRenovacion;
    if (renovacion == null || renovacion.isEmpty) return false;
    final pendiente = _renovacionEnCurso ??= _ejecutarRenovacion(renovacion);
    try {
      await pendiente;
      return tieneSesion;
    } on SesionExpirada {
      return false;
    } finally {
      if (identical(_renovacionEnCurso, pendiente)) _renovacionEnCurso = null;
    }
  }

  Future<void> _ejecutarRenovacion(String renovacion) async {
    final respuesta = await _enviar('POST', '/auth/refresh',
        cuerpo: {'refresh_token': renovacion}, autenticado: false, espera: _esperaNormal);
    if (respuesta.statusCode != 200) {
      limpiarSesion();
      await alGuardarSesion?.call(null, null);
      throw const SesionExpirada();
    }
    final sesion = Sesion.desdeJson(_mapa(_cuerpoJson(respuesta)));
    if (!sesion.iniciada) {
      limpiarSesion();
      await alGuardarSesion?.call(null, null);
      throw const SesionExpirada();
    }
    tokenAcceso = sesion.tokenAcceso;
    tokenRenovacion = sesion.tokenRenovacion ?? renovacion;
    await alGuardarSesion?.call(tokenAcceso, tokenRenovacion);
  }

  dynamic _cuerpoJson(http.Response respuesta) {
    if (respuesta.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(respuesta.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  dynamic _interpretar(http.Response respuesta) {
    final datos = _cuerpoJson(respuesta);
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) return datos;
    throw ErrorApi(_detalle(datos, respuesta.statusCode), codigo: respuesta.statusCode);
  }

  String _detalle(dynamic datos, int codigo) {
    if (datos is Map<String, dynamic>) {
      final detalle = datos['detail'];
      if (detalle is String && detalle.isNotEmpty) return detalle;
      // FastAPI devuelve una lista cuando falla la validacion de Pydantic.
      if (detalle is List && detalle.isNotEmpty) {
        final primero = detalle.first;
        if (primero is Map && primero['msg'] is String) {
          return (primero['msg'] as String).replaceFirst('Value error, ', '');
        }
      }
    }
    switch (codigo) {
      case 401:
        return 'Correo o contrasena incorrectos.';
      case 403:
        return 'No tienes permiso para hacer eso.';
      case 404:
        return 'No se encontro lo que buscabas.';
      case 409:
        return 'La conversacion alcanzo su limite de mensajes.';
      case 429:
        return 'Demasiados intentos. Espera unos minutos.';
      case 503:
        return 'El asistente no esta disponible en este momento.';
      default:
        return 'Ocurrio un error inesperado ($codigo).';
    }
  }

  Map<String, dynamic> _mapa(dynamic datos) =>
      datos is Map<String, dynamic> ? datos : <String, dynamic>{};

  List<Map<String, dynamic>> _lista(dynamic datos) =>
      datos is List ? datos.whereType<Map<String, dynamic>>().toList() : const [];
}
