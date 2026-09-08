import 'package:flutter/material.dart';

// La app del estudiante no muestra de donde salio la respuesta: ni los chips de
// documento y pagina, ni la linea "Fuente: ..." con la que la API cierra el
// texto. El dato sigue viajando en `Burbuja.fuentes` y en la respuesta de la
// API, y el panel administrativo lo sigue mostrando para poder auditar.
import '../datos/modelos.dart';
import '../nucleo/colores.dart';
import 'texto_markdown.dart';

class BurbujaMensaje extends StatelessWidget {
  const BurbujaMensaje({super.key, required this.burbuja, this.alValorar});

  final Burbuja burbuja;

  /// Recibe 1 (util) o -1 (no util). Si es null no se muestran los botones.
  final void Function(int valoracion)? alValorar;

  @override
  Widget build(BuildContext context) {
    final esEstudiante = burbuja.esEstudiante;
    final colorFondo = esEstudiante
        ? ColoresDonTramite.azul
        : (burbuja.esError ? const Color(0xFFFDECEB) : ColoresDonTramite.blanco);
    final colorTexto = esEstudiante
        ? ColoresDonTramite.blanco
        : (burbuja.esError ? const Color(0xFF8C1D18) : ColoresDonTramite.negro);

    return Align(
      alignment: esEstudiante ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: colorFondo,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(esEstudiante ? 18 : 4),
              bottomRight: Radius.circular(esEstudiante ? 4 : 18),
            ),
            border: esEstudiante
                ? null
                : Border.all(
                    color: burbuja.esError
                        ? const Color(0xFFF3B9B5)
                        : ColoresDonTramite.linea,
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (burbuja.pensando)
                const _Pensando()
              else if (esEstudiante)
                SelectableText(
                  burbuja.texto,
                  style: TextStyle(color: colorTexto, fontSize: 15.5, height: 1.4),
                )
              else
                TextoMarkdown(burbuja.texto, color: colorTexto, mostrarFuente: false),
              if (alValorar != null && burbuja.sePuedeValorar) ...[
                const SizedBox(height: 10),
                _Valoracion(valor: burbuja.valoracion, alValorar: alValorar!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulgares para calificar la respuesta. Alimentan
/// POST /chat/questions/{id}/feedback, que ya existia en la API y que ninguna
/// pantalla usaba.
class _Valoracion extends StatelessWidget {
  const _Valoracion({required this.valor, required this.alValorar});

  final int? valor;
  final void Function(int valoracion) alValorar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valor == null ? 'Te sirvio esta respuesta?' : 'Gracias por avisar',
          style: const TextStyle(
            fontSize: 12,
            color: ColoresDonTramite.textoTenue,
          ),
        ),
        const SizedBox(width: 6),
        _boton(
          activo: valor == 1,
          icono: Icons.thumb_up_outlined,
          iconoActivo: Icons.thumb_up,
          etiqueta: 'Si, me sirvio',
          alPulsar: () => alValorar(1),
        ),
        _boton(
          activo: valor == -1,
          icono: Icons.thumb_down_outlined,
          iconoActivo: Icons.thumb_down,
          etiqueta: 'No me sirvio',
          alPulsar: () => alValorar(-1),
        ),
      ],
    );
  }

  Widget _boton({
    required bool activo,
    required IconData icono,
    required IconData iconoActivo,
    required String etiqueta,
    required VoidCallback alPulsar,
  }) {
    return IconButton(
      tooltip: etiqueta,
      onPressed: alPulsar,
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      icon: Icon(
        activo ? iconoActivo : icono,
        color: activo ? ColoresDonTramite.azul : ColoresDonTramite.textoTenue,
      ),
    );
  }
}

class _Pensando extends StatefulWidget {
  const _Pensando();

  @override
  State<_Pensando> createState() => _EstadoPensando();
}

class _EstadoPensando extends State<_Pensando> with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _control,
            builder: (context, _) {
              final avance = (_control.value + i * 0.22) % 1.0;
              final pico = (1 - (avance - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble();
              final opacidad = 0.32 + 0.68 * pico;
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: ColoresDonTramite.azul.withValues(alpha: opacidad),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
        const SizedBox(width: 4),
        const Text(
          'Buscando en los documentos...',
          style: TextStyle(color: ColoresDonTramite.textoTenue, fontSize: 14),
        ),
      ],
    );
  }
}
