import 'package:flutter/material.dart';

import '../datos/cliente_api.dart';
import '../datos/modelos.dart';
import '../estado/sesion.dart';
import '../nucleo/colores.dart';
import '../widgets/burbuja_mensaje.dart';
import '../widgets/dialogo_texto.dart';
import '../widgets/panel_conversaciones.dart';
import 'pantalla_cuenta.dart';

/// Pantalla de chat con la lista de conversaciones del estudiante.
class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key, required this.estado});

  final EstadoSesion estado;

  @override
  State<PantallaPrincipal> createState() => _EstadoPantallaPrincipal();
}

class _EstadoPantallaPrincipal extends State<PantallaPrincipal> {
  static const _anchoEscritorio = 940.0;

  final _llaveScaffold = GlobalKey<ScaffoldState>();
  final _mensaje = TextEditingController();
  final _scroll = ScrollController();
  final _focoMensaje = FocusNode();

  List<Conversacion> _conversaciones = const [];
  List<Burbuja> _burbujas = const [];
  Conversacion? _activa;

  bool _cargandoLista = true;
  bool _cargandoMensajes = false;
  bool _enviando = false;

  ClienteApi get _cliente => widget.estado.cliente;

  @override
  void initState() {
    super.initState();
    _cargarConversaciones();
  }

  @override
  void dispose() {
    _mensaje.dispose();
    _scroll.dispose();
    _focoMensaje.dispose();
    super.dispose();
  }

  // ------------------------------- Datos --------------------------------

  Future<void> _cargarConversaciones() async {
    setState(() => _cargandoLista = true);
    try {
      final lista = await _cliente.listarConversaciones();
      if (!mounted) return;
      setState(() {
        _conversaciones = lista;
        _cargandoLista = false;
      });
      if (lista.isEmpty) {
        setState(() {
          _activa = null;
          _burbujas = [_saludoInicial()];
        });
      } else {
        await _abrirConversacion(lista.first, cerrarPanel: false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoLista = false;
        _burbujas = [
          Burbuja(texto: mensajeDeError(error), esEstudiante: false, esError: true),
        ];
      });
    }
  }

  Future<void> _abrirConversacion(Conversacion conversacion, {bool cerrarPanel = true}) async {
    if (cerrarPanel) _cerrarPanelSiHaceFalta();
    setState(() {
      _activa = conversacion;
      _cargandoMensajes = true;
      _burbujas = const [];
    });
    try {
      final intercambios = await _cliente.mensajesDe(conversacion.id);
      if (!mounted) return;
      final burbujas = <Burbuja>[];
      for (final intercambio in intercambios) {
        burbujas.add(Burbuja(texto: intercambio.pregunta, esEstudiante: true));
        final respuesta = intercambio.respuesta;
        if (respuesta != null && respuesta.trim().isNotEmpty) {
          burbujas.add(Burbuja(
            texto: respuesta,
            esEstudiante: false,
            fuentes: intercambio.fuentes,
            preguntaId: intercambio.id,
          ));
        } else {
          burbujas.add(const Burbuja(
            texto: 'No se pudo responder esta pregunta.',
            esEstudiante: false,
            esError: true,
          ));
        }
      }
      if (burbujas.isEmpty) burbujas.add(_saludoConversacion(conversacion));
      setState(() {
        _burbujas = burbujas;
        _cargandoMensajes = false;
      });
      _bajarAlFinal();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoMensajes = false;
        _burbujas = [
          Burbuja(texto: mensajeDeError(error), esEstudiante: false, esError: true),
        ];
      });
    }
  }

  Future<void> _crearConversacion() async {
    _cerrarPanelSiHaceFalta();
    try {
      final conversacion = await _cliente.crearConversacion(
        titulo: 'Chat ${_conversaciones.length + 1}',
      );
      if (!mounted) return;
      setState(() {
        _conversaciones = [conversacion, ..._conversaciones];
        _activa = conversacion;
        _burbujas = [_saludoConversacion(conversacion)];
      });
      _focoMensaje.requestFocus();
    } catch (error) {
      _avisar(mensajeDeError(error), error: true);
    }
  }

  Future<void> _enviarMensaje() async {
    final texto = _mensaje.text.trim();
    if (texto.isEmpty || _enviando) return;

    setState(() {
      _enviando = true;
      _mensaje.clear();
      _burbujas = [
        ..._burbujas.where((b) => !b.pensando),
        Burbuja(texto: texto, esEstudiante: true),
        const Burbuja(texto: '', esEstudiante: false, pensando: true),
      ];
    });
    _bajarAlFinal();

    try {
      final destino = _activa ?? await _crearParaPrimeraPregunta(texto);
      final respuesta = await _cliente.preguntar(
        pregunta: texto,
        conversacionId: destino.id,
      );
      if (!mounted) return;

      final actualizada = destino.copiarCon(
        cantidadMensajes: destino.cantidadMensajes + 1,
        actualizado: DateTime.now(),
      );
      setState(() {
        _burbujas = [
          ..._burbujas.where((b) => !b.pensando),
          Burbuja(
            texto: respuesta.respuesta,
            esEstudiante: false,
            fuentes: respuesta.fuentes,
            preguntaId: respuesta.preguntaId,
          ),
        ];
        _activa = actualizada;
        _conversaciones = [
          for (final conversacion in _conversaciones)
            conversacion.id == actualizada.id ? actualizada : conversacion,
        ];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _burbujas = [
          ..._burbujas.where((b) => !b.pensando),
          Burbuja(texto: mensajeDeError(error), esEstudiante: false, esError: true),
        ];
      });
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
        _bajarAlFinal();
      }
    }
  }

  /// Sin conversación activa se crea una y se titula con la propia pregunta.
  Future<Conversacion> _crearParaPrimeraPregunta(String pregunta) async {
    final titulo = pregunta.length <= 48 ? pregunta : '${pregunta.substring(0, 45)}...';
    final conversacion = await _cliente.crearConversacion(titulo: titulo);
    if (mounted) {
      setState(() {
        _conversaciones = [conversacion, ..._conversaciones];
        _activa = conversacion;
      });
    }
    return conversacion;
  }

  Future<void> _renombrar(Conversacion conversacion) async {
    _cerrarPanelSiHaceFalta();
    final nuevo = await pedirTexto(
      context,
      titulo: 'Renombrar conversacion',
      etiqueta: 'Titulo',
      valorInicial: conversacion.tituloVisible,
      maxCaracteres: 120,
    );
    if (nuevo == null || nuevo.isEmpty || !mounted) return;

    try {
      final actualizada = await _cliente.renombrarConversacion(conversacion.id, nuevo);
      if (!mounted) return;
      setState(() {
        _conversaciones = [
          for (final item in _conversaciones)
            item.id == actualizada.id ? actualizada : item,
        ];
        if (_activa?.id == actualizada.id) _activa = actualizada;
      });
    } catch (error) {
      _avisar(mensajeDeError(error), error: true);
    }
  }

  Future<void> _eliminar(Conversacion conversacion) async {
    _cerrarPanelSiHaceFalta();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar conversacion'),
        content: Text(
          'Se borrara "${conversacion.tituloVisible}". Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      await _cliente.eliminarConversacion(conversacion.id);
      if (!mounted) return;
      final restantes = [
        for (final item in _conversaciones)
          if (item.id != conversacion.id) item,
      ];
      setState(() => _conversaciones = restantes);
      if (_activa?.id == conversacion.id) {
        if (restantes.isEmpty) {
          setState(() {
            _activa = null;
            _burbujas = [_saludoInicial()];
          });
        } else {
          await _abrirConversacion(restantes.first, cerrarPanel: false);
        }
      }
    } catch (error) {
      _avisar(mensajeDeError(error), error: true);
    }
  }

  /// Envia el pulgar arriba/abajo. Se pinta al instante y se revierte si falla.
  Future<void> _valorar(int indice, int valoracion) async {
    if (indice < 0 || indice >= _burbujas.length) return;
    final burbuja = _burbujas[indice];
    final preguntaId = burbuja.preguntaId;
    if (preguntaId == null) return;

    final anterior = burbuja.valoracion;
    if (anterior == valoracion) return;

    void pintar(int? valor) {
      setState(() {
        _burbujas = [
          for (var i = 0; i < _burbujas.length; i++)
            i == indice
                ? Burbuja(
                    texto: _burbujas[i].texto,
                    esEstudiante: _burbujas[i].esEstudiante,
                    fuentes: _burbujas[i].fuentes,
                    preguntaId: _burbujas[i].preguntaId,
                    valoracion: valor,
                  )
                : _burbujas[i],
        ];
      });
    }

    pintar(valoracion);
    try {
      await _cliente.valorar(preguntaId: preguntaId, valoracion: valoracion);
    } catch (error) {
      if (!mounted) return;
      pintar(anterior);
      _avisar(mensajeDeError(error), error: true);
    }
  }

  Future<void> _abrirCuenta() async {
    _cerrarPanelSiHaceFalta();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PantallaCuenta(estado: widget.estado)),
    );
    if (mounted) setState(() {});
  }

  // ------------------------------ Utilidades ------------------------------

  Burbuja _saludoInicial() => const Burbuja(
    texto:
        'Hola, soy **DonTramite**. Preguntame sobre matricula, certificados, '
        'grados, pagos y otros tramites.\n\n'
        'Escribe tu pregunta abajo y creo la conversacion automaticamente.',
    esEstudiante: false,
  );

  Burbuja _saludoConversacion(Conversacion conversacion) => Burbuja(
    texto:
        'Empezamos **${conversacion.tituloVisible}**. '
        'Tienes hasta ${conversacion.limiteMensajes} mensajes en este chat.',
    esEstudiante: false,
  );

  void _bajarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _cerrarPanelSiHaceFalta() {
    final estado = _llaveScaffold.currentState;
    if (estado != null && estado.isDrawerOpen) Navigator.of(context).pop();
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? const Color(0xFFB3261E) : ColoresDonTramite.azulFuerte,
      ),
    );
  }

  // ------------------------------- Interfaz -------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final escritorio = restricciones.maxWidth >= _anchoEscritorio;
        if (escritorio) {
          return Scaffold(
            body: Row(
              children: [
                _panel(),
                Expanded(child: _superficieChat(conBotonMenu: false)),
              ],
            ),
          );
        }
        return Scaffold(
          key: _llaveScaffold,
          drawer: Drawer(
            width: 300,
            backgroundColor: ColoresDonTramite.lateral,
            child: _panel(),
          ),
          body: _superficieChat(conBotonMenu: true),
        );
      },
    );
  }

  Widget _panel() => PanelConversaciones(
    conversaciones: _conversaciones,
    activa: _activa,
    perfil: widget.estado.perfil,
    cargando: _cargandoLista,
    alCrear: _crearConversacion,
    alSeleccionar: _abrirConversacion,
    alRenombrar: _renombrar,
    alEliminar: _eliminar,
    alAbrirCuenta: _abrirCuenta,
  );

  Widget _superficieChat({required bool conBotonMenu}) {
    final conversacion = _activa;
    final bloqueada = conversacion != null &&
        (conversacion.alcanzoLimite || !conversacion.estaActiva);

    return SafeArea(
      child: Column(
        children: [
          _encabezado(conBotonMenu: conBotonMenu, conversacion: conversacion),
          if (bloqueada) _avisoLimite(),
          Expanded(
            child: _cargandoMensajes
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                    itemCount: _burbujas.length,
                    itemBuilder: (context, indice) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: BurbujaMensaje(
                          burbuja: _burbujas[indice],
                          alValorar: (valoracion) => _valorar(indice, valoracion),
                        ),
                      ),
                    ),
                  ),
          ),
          _compositor(bloqueada: bloqueada),
        ],
      ),
    );
  }

  Widget _encabezado({required bool conBotonMenu, required Conversacion? conversacion}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
      decoration: const BoxDecoration(
        color: ColoresDonTramite.blanco,
        border: Border(bottom: BorderSide(color: ColoresDonTramite.linea)),
      ),
      child: Row(
        children: [
          if (conBotonMenu)
            IconButton(
              tooltip: 'Mis conversaciones',
              onPressed: () => _llaveScaffold.currentState?.openDrawer(),
              icon: const Icon(Icons.menu),
            )
          else
            const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversacion?.tituloVisible ?? 'Chat de tramites',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: ColoresDonTramite.negro,
                  ),
                ),
                Text(
                  conversacion == null
                      ? 'Escribe tu pregunta para empezar'
                      : '${conversacion.mensajesRestantes} mensajes disponibles',
                  style: const TextStyle(
                    color: ColoresDonTramite.textoTenue,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Nueva conversacion',
            onPressed: _crearConversacion,
            icon: const Icon(Icons.add_comment_outlined),
            color: ColoresDonTramite.azul,
          ),
        ],
      ),
    );
  }

  Widget _avisoLimite() {
    return Container(
      width: double.infinity,
      color: ColoresDonTramite.amarillo.withValues(alpha: 0.22),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 19, color: Color(0xFF8A6100)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Esta conversacion llego a su limite de mensajes.',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          TextButton(
            onPressed: _crearConversacion,
            child: const Text('Crear otra'),
          ),
        ],
      ),
    );
  }

  Widget _compositor({required bool bloqueada}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: ColoresDonTramite.blanco,
        border: Border(top: BorderSide(color: ColoresDonTramite.linea)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _mensaje,
                  focusNode: _focoMensaje,
                  enabled: !bloqueada,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviarMensaje(),
                  decoration: InputDecoration(
                    hintText: bloqueada
                        ? 'Crea una conversacion nueva para seguir'
                        : 'Pregunta sobre matricula, certificados, pagos...',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                height: 54,
                child: FilledButton(
                  onPressed: (_enviando || bloqueada) ? null : _enviarMensaje,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ColoresDonTramite.blanco,
                          ),
                        )
                      : const Icon(Icons.arrow_upward),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
