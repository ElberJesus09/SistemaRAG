/// Error con un mensaje ya listo para mostrar al estudiante.
class ErrorApi implements Exception {
  const ErrorApi(this.mensaje, {this.codigo});

  final String mensaje;
  final int? codigo;

  @override
  String toString() => mensaje;
}

/// La sesión no se pudo renovar: hay que volver a iniciar sesión.
class SesionExpirada implements Exception {
  const SesionExpirada();

  @override
  String toString() => 'La sesion expiro';
}
