import 'package:flutter/material.dart';

import '../datos/modelos.dart';
import '../nucleo/colores.dart';
import 'marca.dart';

/// Lista lateral de chats del estudiante.
class PanelConversaciones extends StatelessWidget {
  const PanelConversaciones({
    super.key,
    required this.conversaciones,
    required this.activa,
    required this.perfil,
    required this.cargando,
    required this.alCrear,
    required this.alSeleccionar,
    required this.alRenombrar,
    required this.alEliminar,
    required this.alAbrirCuenta,
  });

  final List<Conversacion> conversaciones;
  final Conversacion? activa;
  final Perfil? perfil;
  final bool cargando;
  final VoidCallback alCrear;
  final void Function(Conversacion) alSeleccionar;
  final void Function(Conversacion) alRenombrar;
  final void Function(Conversacion) alEliminar;
  final VoidCallback alAbrirCuenta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: ColoresDonTramite.lateral,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  const LogoDonTramite(tamano: 42, conBorde: false),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'DonTramite',
                      style: TextStyle(
                        color: ColoresDonTramite.blanco,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FilledButton.icon(
                onPressed: alCrear,
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                label: const Text('Nueva conversacion'),
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresDonTramite.amarillo,
                  foregroundColor: ColoresDonTramite.negro,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _cuerpo()),
            const Divider(color: Color(0x22FFFFFF), height: 1),
            _pieCuenta(),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (cargando && conversaciones.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: ColoresDonTramite.celeste),
        ),
      );
    }
    if (conversaciones.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, color: Color(0xFF52697C), size: 34),
            SizedBox(height: 12),
            Text(
              'Aun no tienes conversaciones',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ColoresDonTramite.blanco,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Escribe tu primera pregunta y se creara una sola.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8CA3B5), fontSize: 12.5, height: 1.35),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: conversaciones.length,
      separatorBuilder: (context, indice) => const SizedBox(height: 6),
      itemBuilder: (context, indice) {
        final conversacion = conversaciones[indice];
        final seleccionada = conversacion.id == activa?.id;
        return Material(
          color: seleccionada
              ? ColoresDonTramite.azul
              : ColoresDonTramite.lateralItem,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => alSeleccionar(conversacion),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Icon(
                    conversacion.estaActiva
                        ? Icons.chat_bubble_outline
                        : Icons.lock_outline,
                    size: 18,
                    color: seleccionada
                        ? ColoresDonTramite.amarillo
                        : ColoresDonTramite.celeste,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conversacion.tituloVisible,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ColoresDonTramite.blanco,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${conversacion.cantidadMensajes}/${conversacion.limiteMensajes} mensajes',
                          style: TextStyle(
                            color: seleccionada
                                ? const Color(0xFFDCEBF7)
                                : const Color(0xFF8CA3B5),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones',
                    icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF9FB4C4)),
                    onSelected: (opcion) {
                      if (opcion == 'renombrar') alRenombrar(conversacion);
                      if (opcion == 'eliminar') alEliminar(conversacion);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'renombrar',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Renombrar'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'eliminar',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Color(0xFFB3261E)),
                            SizedBox(width: 10),
                            Text('Eliminar', style: TextStyle(color: Color(0xFFB3261E))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pieCuenta() {
    final nombre = perfil?.nombreVisible ?? 'Mi cuenta';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: alAbrirCuenta,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: ColoresDonTramite.amarillo,
                child: Text(
                  perfil?.inicial ?? '?',
                  style: const TextStyle(
                    color: ColoresDonTramite.negro,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      perfil?.correo ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF8CA3B5), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8CA3B5)),
            ],
          ),
        ),
      ),
    );
  }
}
