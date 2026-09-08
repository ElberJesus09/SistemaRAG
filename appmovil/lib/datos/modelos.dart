int? _entero(Object? valor) => valor is num ? valor.toInt() : null;

double _decimal(Object? valor) => valor is num ? valor.toDouble() : 0;

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toLocal() : null;

class Perfil {
  const Perfil({
    required this.id,
    required this.correo,
    required this.rol,
    this.nombreCompleto,
  });

  final String id;
  final String correo;
  final String rol;
  final String? nombreCompleto;

  String get nombreVisible {
    final nombre = nombreCompleto?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    return correo.split('@').first;
  }

  String get inicial {
    final texto = nombreVisible.trim();
    return texto.isEmpty ? '?' : texto.substring(0, 1).toUpperCase();
  }

  factory Perfil.desdeJson(Map<String, dynamic> json) => Perfil(
    id: json['id'] as String? ?? '',
    correo: json['email'] as String? ?? '',
    rol: json['role'] as String? ?? 'user',
    nombreCompleto: json['full_name'] as String?,
  );
}

class Conversacion {
  const Conversacion({
    required this.id,
    required this.cantidadMensajes,
    required this.limiteMensajes,
    required this.estado,
    this.titulo,
    this.actualizado,
  });

  final String id;
  final String? titulo;
  final int cantidadMensajes;
  final int limiteMensajes;
  final String estado;
  final DateTime? actualizado;

  bool get estaActiva => estado == 'active';
  bool get alcanzoLimite => cantidadMensajes >= limiteMensajes;
  int get mensajesRestantes {
    final restantes = limiteMensajes - cantidadMensajes;
    return restantes < 0 ? 0 : restantes;
  }

  String get tituloVisible {
    final valor = titulo?.trim();
    return valor == null || valor.isEmpty ? 'Conversacion sin titulo' : valor;
  }

  factory Conversacion.desdeJson(Map<String, dynamic> json) => Conversacion(
    id: json['id'] as String? ?? '',
    titulo: json['title'] as String?,
    cantidadMensajes: _entero(json['message_count']) ?? 0,
    limiteMensajes: _entero(json['max_messages']) ?? 20,
    estado: json['status'] as String? ?? 'active',
    actualizado: _fecha(json['updated_at']) ?? _fecha(json['created_at']),
  );

  Conversacion copiarCon({
    String? titulo,
    int? cantidadMensajes,
    String? estado,
    DateTime? actualizado,
  }) => Conversacion(
    id: id,
    titulo: titulo ?? this.titulo,
    cantidadMensajes: cantidadMensajes ?? this.cantidadMensajes,
    limiteMensajes: limiteMensajes,
    estado: estado ?? this.estado,
    actualizado: actualizado ?? this.actualizado,
  );
}

class Fuente {
  const Fuente({
    required this.documento,
    required this.titulo,
    required this.similitud,
    this.paginaInicio,
    this.paginaFin,
  });

  final String documento;
  final String titulo;
  final double similitud;
  final int? paginaInicio;
  final int? paginaFin;

  String get etiqueta {
    if (paginaInicio == null) return titulo;
    final fin = paginaFin ?? paginaInicio;
    if (fin == paginaInicio) return '$titulo · p. $paginaInicio';
    return '$titulo · p. $paginaInicio-$fin';
  }

  factory Fuente.desdeJson(Map<String, dynamic> json) => Fuente(
    documento: json['document'] as String? ?? 'Documento',
    titulo: json['title'] as String? ?? 'Fuente',
    similitud: _decimal(json['similarity']),
    paginaInicio: _entero(json['page_start']),
    paginaFin: _entero(json['page_end']),
  );
}

/// Un intercambio completo tal como lo guarda la API.
class Intercambio {
  const Intercambio({
    required this.id,
    required this.pregunta,
    required this.estado,
    this.respuesta,
    this.fuentes = const [],
    this.creado,
  });

  final String id;
  final String pregunta;
  final String? respuesta;
  final String estado;
  final List<Fuente> fuentes;
  final DateTime? creado;

  factory Intercambio.desdeJson(Map<String, dynamic> json) {
    final crudas = json['sources'];
    return Intercambio(
      id: json['id'] as String? ?? '',
      pregunta: json['question'] as String? ?? '',
      respuesta: json['answer'] as String?,
      estado: json['status'] as String? ?? 'answered',
      fuentes: crudas is List
          ? crudas
                .whereType<Map<String, dynamic>>()
                .map(Fuente.desdeJson)
                .toList()
          : const [],
      creado: _fecha(json['created_at']),
    );
  }
}

class RespuestaChat {
  const RespuestaChat({
    required this.respuesta,
    required this.fuentes,
    required this.latenciaMs,
    this.preguntaId,
    this.conversacionId,
  });

  final String? preguntaId;
  final String? conversacionId;
  final String respuesta;
  final int latenciaMs;
  final List<Fuente> fuentes;

  factory RespuestaChat.desdeJson(Map<String, dynamic> json) {
    final crudas = json['sources'];
    return RespuestaChat(
      preguntaId: json['question_id'] as String?,
      conversacionId: json['conversation_id'] as String?,
      respuesta: json['answer'] as String? ?? '',
      latenciaMs: _entero(json['latency_ms']) ?? 0,
      fuentes: crudas is List
          ? crudas
                .whereType<Map<String, dynamic>>()
                .map(Fuente.desdeJson)
                .toList()
          : const [],
    );
  }
}

class Sesion {
  const Sesion({this.tokenAcceso, this.tokenRenovacion, this.requiereConfirmarCorreo = false});

  final String? tokenAcceso;
  final String? tokenRenovacion;
  final bool requiereConfirmarCorreo;

  bool get iniciada => tokenAcceso != null && tokenAcceso!.isNotEmpty;

  factory Sesion.desdeJson(Map<String, dynamic> json) => Sesion(
    tokenAcceso: json['access_token'] as String?,
    tokenRenovacion: json['refresh_token'] as String?,
    requiereConfirmarCorreo: json['requires_email_confirmation'] == true,
  );
}

/// Una burbuja en la pantalla de chat.
class Burbuja {
  const Burbuja({
    required this.texto,
    required this.esEstudiante,
    this.fuentes = const [],
    this.pensando = false,
    this.esError = false,
    this.preguntaId,
    this.valoracion,
  });

  final String texto;
  final bool esEstudiante;
  final List<Fuente> fuentes;
  final bool pensando;
  final bool esError;

  /// Identificador de la pregunta en la API; habilita valorar la respuesta.
  final String? preguntaId;

  /// 1 = util, -1 = no util, null = sin valorar.
  final int? valoracion;

  bool get sePuedeValorar =>
      !esEstudiante && !pensando && !esError && preguntaId != null;

  Burbuja copiarCon({int? valoracion}) => Burbuja(
    texto: texto,
    esEstudiante: esEstudiante,
    fuentes: fuentes,
    pensando: pensando,
    esError: esError,
    preguntaId: preguntaId,
    valoracion: valoracion ?? this.valoracion,
  );
}
