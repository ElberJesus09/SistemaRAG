import 'dart:async';

import 'package:flutter/material.dart';

import '../estado/sesion.dart';
import '../nucleo/colores.dart';
import '../nucleo/configuracion.dart';
import '../widgets/dialogo_texto.dart';
import '../widgets/marca.dart';

/// Acceso del estudiante: solo correo y contraseña.
///
/// La URL del servidor no se pide nunca; se resuelve sola (ver
/// `ConfiguracionApi`). Para probar contra un celular físico hay un ajuste
/// avanzado que aparece al mantener pulsado el logo tres segundos.
class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({super.key, required this.estado});

  final EstadoSesion estado;

  @override
  State<PantallaAcceso> createState() => _EstadoPantallaAcceso();
}

class _EstadoPantallaAcceso extends State<PantallaAcceso> {
  final _llaveFormulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();

  bool _modoRegistro = false;
  bool _cargando = false;
  bool _ocultarContrasena = true;
  String? _aviso;
  bool _avisoEsExito = false;
  Timer? _temporizadorAjustes;

  @override
  void dispose() {
    _temporizadorAjustes?.cancel();
    _nombre.dispose();
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (!_llaveFormulario.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _aviso = null;
    });

    try {
      final sesion = _modoRegistro
          ? await widget.estado.registrar(
              correo: _correo.text.trim(),
              contrasena: _contrasena.text,
              nombreCompleto: _nombre.text.trim(),
            )
          : await widget.estado.iniciarSesion(
              correo: _correo.text.trim(),
              contrasena: _contrasena.text,
            );

      if (!mounted) return;
      if (!sesion.iniciada) {
        setState(() {
          _avisoEsExito = true;
          _aviso = 'Cuenta creada. Revisa tu correo para confirmarla y luego ingresa.';
          _modoRegistro = false;
        });
      }
      // Si la sesión quedó iniciada, el widget raíz cambia de pantalla solo.
    } catch (error) {
      if (mounted) {
        setState(() {
          _avisoEsExito = false;
          _aviso = mensajeDeError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------------------- Ajuste avanzado (oculto) ----------------------

  void _iniciarPulsacionLarga() {
    _temporizadorAjustes?.cancel();
    _temporizadorAjustes = Timer(const Duration(seconds: 3), _abrirAjustes);
  }

  void _cancelarPulsacionLarga() {
    _temporizadorAjustes?.cancel();
    _temporizadorAjustes = null;
  }

  Future<void> _abrirAjustes() async {
    if (!mounted) return;
    if (ConfiguracionApi.tieneUrlFija) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta version se compilo con un servidor fijo.'),
        ),
      );
      return;
    }
    final nueva = await pedirTexto(
      context,
      titulo: 'Servidor de pruebas',
      etiqueta: 'URL del servidor',
      valorInicial: widget.estado.urlServidor,
      ayuda: 'Solo para desarrollo. En un celular fisico usa la IP de tu PC, '
          'por ejemplo http://192.168.1.20:8000',
      textoAlterno: 'Restablecer',
      teclado: TextInputType.url,
    );
    if (nueva == null || !mounted) return;

    if (nueva.isNotEmpty && !ConfiguracionApi.esValida(nueva)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La direccion no es valida.')),
      );
      return;
    }
    await widget.estado.cambiarServidor(nueva.isEmpty ? null : nueva);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Servidor: ${widget.estado.urlServidor}')),
    );
  }

  // ------------------------------- Interfaz -------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) {
            final anchoGrande = restricciones.maxWidth >= 900;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: anchoGrande
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _bienvenida(false)),
                            const SizedBox(width: 40),
                            SizedBox(width: 420, child: _formulario()),
                          ],
                        )
                      : Column(
                          children: [
                            _bienvenida(true),
                            const SizedBox(height: 26),
                            _formulario(),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bienvenida(bool compacta) {
    return Column(
      crossAxisAlignment:
          compacta ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _iniciarPulsacionLarga(),
          onTapUp: (_) => _cancelarPulsacionLarga(),
          onTapCancel: _cancelarPulsacionLarga,
          child: LogoDonTramite(tamano: compacta ? 124 : 164),
        ),
        const SizedBox(height: 24),
        Text(
          'DonTramite',
          textAlign: compacta ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 40,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: ColoresDonTramite.negro,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tu asistente para resolver dudas de tramites estudiantiles.',
          textAlign: compacta ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 17,
            height: 1.35,
            color: ColoresDonTramite.gris,
          ),
        ),
        const SizedBox(height: 24),
        BarraColores(ancho: compacta ? 260 : 420),
      ],
    );
  }

  Widget _formulario() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: ColoresDonTramite.blanco,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ColoresDonTramite.linea),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 26, offset: Offset(0, 12)),
        ],
      ),
      child: Form(
        key: _llaveFormulario,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.login),
                  label: Text('Ingresar'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.person_add_alt_1),
                  label: Text('Crear cuenta'),
                ),
              ],
              selected: {_modoRegistro},
              onSelectionChanged: _cargando
                  ? null
                  : (valor) => setState(() {
                      _modoRegistro = valor.first;
                      _aviso = null;
                    }),
            ),
            const SizedBox(height: 22),
            if (_modoRegistro) ...[
              TextFormField(
                controller: _nombre,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (valor) => (valor == null || valor.trim().length < 2)
                    ? 'Escribe tu nombre'
                    : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _correo,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Correo institucional',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (valor) {
                final texto = valor?.trim() ?? '';
                if (texto.isEmpty) return 'Escribe tu correo';
                if (!texto.contains('@') || !texto.contains('.')) {
                  return 'Escribe un correo valido';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _contrasena,
              obscureText: _ocultarContrasena,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _cargando ? null : _enviar(),
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Contrasena',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _ocultarContrasena ? 'Mostrar' : 'Ocultar',
                  onPressed: () =>
                      setState(() => _ocultarContrasena = !_ocultarContrasena),
                  icon: Icon(
                    _ocultarContrasena
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (valor) => (valor == null || valor.length < 8)
                  ? 'Minimo 8 caracteres'
                  : null,
            ),
            if (_aviso != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _avisoEsExito
                      ? ColoresDonTramite.celeste.withValues(alpha: 0.16)
                      : const Color(0xFFFDECEB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _avisoEsExito ? Icons.mark_email_read_outlined : Icons.error_outline,
                      size: 20,
                      color: _avisoEsExito
                          ? ColoresDonTramite.azulFuerte
                          : const Color(0xFFB3261E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _aviso!,
                        style: TextStyle(
                          color: _avisoEsExito
                              ? ColoresDonTramite.azulFuerte
                              : const Color(0xFFB3261E),
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _cargando ? null : _enviar,
              icon: _cargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ColoresDonTramite.blanco,
                      ),
                    )
                  : Icon(_modoRegistro ? Icons.person_add_alt_1 : Icons.arrow_forward),
              label: Text(_modoRegistro ? 'Crear cuenta' : 'Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}
