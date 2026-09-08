import 'package:flutter/material.dart';

import '../estado/sesion.dart';
import '../nucleo/colores.dart';

/// Gestión de la cuenta: nombre, contraseña y cierre de sesión.
class PantallaCuenta extends StatefulWidget {
  const PantallaCuenta({super.key, required this.estado});

  final EstadoSesion estado;

  @override
  State<PantallaCuenta> createState() => _EstadoPantallaCuenta();
}

class _EstadoPantallaCuenta extends State<PantallaCuenta> {
  final _llaveNombre = GlobalKey<FormState>();
  final _llaveContrasena = GlobalKey<FormState>();
  late final TextEditingController _nombre = TextEditingController(
    text: widget.estado.perfil?.nombreCompleto ?? '',
  );
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetida = TextEditingController();

  bool _guardandoNombre = false;
  bool _guardandoContrasena = false;
  bool _ocultar = true;

  @override
  void dispose() {
    _nombre.dispose();
    _actual.dispose();
    _nueva.dispose();
    _repetida.dispose();
    super.dispose();
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

  Future<void> _guardarNombre() async {
    FocusScope.of(context).unfocus();
    if (!_llaveNombre.currentState!.validate()) return;
    setState(() => _guardandoNombre = true);
    try {
      await widget.estado.actualizarNombre(_nombre.text.trim());
      _avisar('Nombre actualizado.');
    } catch (error) {
      _avisar(mensajeDeError(error), error: true);
    } finally {
      if (mounted) setState(() => _guardandoNombre = false);
    }
  }

  Future<void> _guardarContrasena() async {
    FocusScope.of(context).unfocus();
    if (!_llaveContrasena.currentState!.validate()) return;
    setState(() => _guardandoContrasena = true);
    try {
      await widget.estado.cambiarContrasena(
        actual: _actual.text,
        nueva: _nueva.text,
      );
      _actual.clear();
      _nueva.clear();
      _repetida.clear();
      _avisar('Contrasena actualizada.');
    } catch (error) {
      _avisar(mensajeDeError(error), error: true);
    } finally {
      if (mounted) setState(() => _guardandoContrasena = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Tendras que ingresar tu correo y contrasena otra vez.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            child: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    // Al cerrar esta pantalla, el widget raiz detecta la sesion vacia y
    // vuelve solo al acceso.
    Navigator.of(context).pop();
    await widget.estado.cerrarSesion();
  }

  @override
  Widget build(BuildContext context) {
    final perfil = widget.estado.perfil;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi cuenta'),
        backgroundColor: ColoresDonTramite.blanco,
        surfaceTintColor: ColoresDonTramite.blanco,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: ColoresDonTramite.linea)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cabecera(perfil?.nombreVisible ?? '', perfil?.correo ?? '',
                      perfil?.inicial ?? '?', perfil?.rol ?? 'user'),
                  const SizedBox(height: 20),
                  _tarjetaNombre(),
                  const SizedBox(height: 16),
                  _tarjetaContrasena(),
                  const SizedBox(height: 16),
                  _tarjetaSesion(),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecera(String nombre, String correo, String inicial, String rol) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ColoresDonTramite.azul, ColoresDonTramite.celeste],
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: ColoresDonTramite.amarillo,
            child: Text(
              inicial,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ColoresDonTramite.negro,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ColoresDonTramite.blanco,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  correo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFE6F4FA), fontSize: 13),
                ),
                if (rol == 'admin') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ColoresDonTramite.negro.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Administrador',
                      style: TextStyle(
                        color: ColoresDonTramite.blanco,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta({required String titulo, required String apoyo, required Widget hijo}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ColoresDonTramite.blanco,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ColoresDonTramite.linea),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ColoresDonTramite.negro,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            apoyo,
            style: const TextStyle(fontSize: 13, color: ColoresDonTramite.textoTenue),
          ),
          const SizedBox(height: 16),
          hijo,
        ],
      ),
    );
  }

  Widget _tarjetaNombre() {
    return _tarjeta(
      titulo: 'Nombre completo',
      apoyo: 'Es el nombre que ve el personal administrativo en tus consultas.',
      hijo: Form(
        key: _llaveNombre,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nombre,
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
            FilledButton(
              onPressed: _guardandoNombre ? null : _guardarNombre,
              child: _guardandoNombre
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ColoresDonTramite.blanco,
                      ),
                    )
                  : const Text('Guardar nombre'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaContrasena() {
    return _tarjeta(
      titulo: 'Contrasena',
      apoyo: 'Debe tener al menos 8 caracteres y ser distinta de la actual.',
      hijo: Form(
        key: _llaveContrasena,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _actual,
              obscureText: _ocultar,
              decoration: InputDecoration(
                labelText: 'Contrasena actual',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                  icon: Icon(
                    _ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (valor) =>
                  (valor == null || valor.length < 8) ? 'Minimo 8 caracteres' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nueva,
              obscureText: _ocultar,
              decoration: const InputDecoration(
                labelText: 'Contrasena nueva',
                prefixIcon: Icon(Icons.lock_reset_outlined),
              ),
              validator: (valor) {
                if (valor == null || valor.length < 8) return 'Minimo 8 caracteres';
                if (valor == _actual.text) return 'Debe ser distinta de la actual';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _repetida,
              obscureText: _ocultar,
              decoration: const InputDecoration(
                labelText: 'Repite la contrasena nueva',
                prefixIcon: Icon(Icons.done_all_outlined),
              ),
              validator: (valor) =>
                  valor != _nueva.text ? 'Las contrasenas no coinciden' : null,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _guardandoContrasena ? null : _guardarContrasena,
              child: _guardandoContrasena
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ColoresDonTramite.blanco,
                      ),
                    )
                  : const Text('Cambiar contrasena'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaSesion() {
    return _tarjeta(
      titulo: 'Sesion',
      apoyo: 'Cierra sesion para entrar con otra cuenta en este dispositivo.',
      hijo: OutlinedButton.icon(
        onPressed: _cerrarSesion,
        icon: const Icon(Icons.logout, size: 20),
        label: const Text('Cerrar sesion'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB3261E),
          side: const BorderSide(color: Color(0xFFF0BDB9)),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
