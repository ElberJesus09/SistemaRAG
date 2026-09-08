import 'package:flutter/foundation.dart';

import '../datos/almacenamiento.dart';
import '../datos/cliente_api.dart';
import '../datos/excepciones.dart';
import '../datos/modelos.dart';
import '../nucleo/configuracion.dart';

/// Estado de sesión compartido por toda la app.
class EstadoSesion extends ChangeNotifier {
  EstadoSesion({required this.cliente, required this.almacenamiento}) {
    cliente.alGuardarSesion = almacenamiento.guardarSesion;
    cliente.alPerderSesion = _sesionPerdida;
  }

  final ClienteApi cliente;
  final Almacenamiento almacenamiento;

  Perfil? _perfil;
  bool _restaurando = true;

  Perfil? get perfil => _perfil;
  bool get restaurando => _restaurando;
  bool get iniciada => _perfil != null && cliente.tieneSesion;
  String get urlServidor => cliente.urlBase;

  /// Intenta recuperar la sesión guardada al abrir la app.
  Future<void> restaurar() async {
    _restaurando = true;
    notifyListeners();
    final acceso = almacenamiento.tokenAcceso;
    final renovacion = almacenamiento.tokenRenovacion;
    if (acceso != null && acceso.isNotEmpty) {
      cliente.tokenAcceso = acceso;
      cliente.tokenRenovacion = renovacion;
      try {
        _perfil = await cliente.miPerfil();
      } catch (_) {
        // Token vencido o servidor caído: se empieza con la pantalla de acceso.
        cliente.limpiarSesion();
        await almacenamiento.borrarSesion();
        _perfil = null;
      }
    }
    _restaurando = false;
    notifyListeners();
  }

  Future<Sesion> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final sesion = await cliente.iniciarSesion(correo: correo, contrasena: contrasena);
    if (sesion.iniciada) _perfil = await cliente.miPerfil();
    notifyListeners();
    return sesion;
  }

  Future<Sesion> registrar({
    required String correo,
    required String contrasena,
    required String nombreCompleto,
  }) async {
    final sesion = await cliente.registrar(
      correo: correo,
      contrasena: contrasena,
      nombreCompleto: nombreCompleto,
    );
    if (sesion.iniciada) _perfil = await cliente.miPerfil();
    notifyListeners();
    return sesion;
  }

  Future<void> cerrarSesion() async {
    cliente.limpiarSesion();
    await almacenamiento.borrarSesion();
    _perfil = null;
    notifyListeners();
  }

  Future<void> actualizarNombre(String nombreCompleto) async {
    _perfil = await cliente.actualizarNombre(nombreCompleto);
    notifyListeners();
  }

  Future<void> cambiarContrasena({required String actual, required String nueva}) =>
      cliente.cambiarContrasena(actual: actual, nueva: nueva);

  /// Cambia el servidor destino. Solo se usa desde el ajuste avanzado.
  Future<void> cambiarServidor(String? url) async {
    final destino = url == null || url.isEmpty
        ? ConfiguracionApi.urlPorDefecto()
        : ConfiguracionApi.normalizar(url);
    cliente.urlBase = destino;
    await almacenamiento.guardarUrl(url == null || url.isEmpty ? null : destino);
    notifyListeners();
  }

  void _sesionPerdida() {
    if (_perfil == null) return;
    _perfil = null;
    almacenamiento.borrarSesion();
    notifyListeners();
  }
}

/// Traduce cualquier excepción a un mensaje presentable.
String mensajeDeError(Object error) {
  if (error is ErrorApi) return error.mensaje;
  if (error is SesionExpirada) return 'Tu sesion expiro. Vuelve a ingresar.';
  return 'Ocurrio un error inesperado. Intenta otra vez.';
}
