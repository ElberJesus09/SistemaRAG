import 'package:flutter/material.dart';

import '../nucleo/colores.dart';

/// Logo de DonTramite. Si el asset falta, cae en un monograma para no
/// romper la pantalla completa.
class LogoDonTramite extends StatelessWidget {
  const LogoDonTramite({super.key, this.tamano = 96, this.conBorde = true});

  final double tamano;
  final bool conBorde;

  @override
  Widget build(BuildContext context) {
    final radio = tamano * 0.24;
    // Decodificar la imagen a su tamano real y no al del archivo: el logo se
    // dibuja entre 42 y 164 px logicos, asi que decodificar el PNG completo
    // reservaba varios MB de mapa de bits y costaba fotogramas al arrancar.
    final medida = (tamano * MediaQuery.devicePixelRatioOf(context)).round();
    final ladoFisico = medida < 1 ? 1 : (medida > 2048 ? 2048 : medida);
    return Container(
      width: tamano,
      height: tamano,
      padding: EdgeInsets.all(tamano * 0.06),
      decoration: BoxDecoration(
        color: ColoresDonTramite.blanco,
        borderRadius: BorderRadius.circular(radio),
        border: conBorde
            ? Border.all(color: ColoresDonTramite.amarillo, width: tamano * 0.035)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radio * 0.72),
        child: Image.asset(
          'assets/dontramite_logo.png',
          fit: BoxFit.cover,
          cacheWidth: ladoFisico,
          cacheHeight: ladoFisico,
          errorBuilder: (context, error, pila) => Container(
            color: ColoresDonTramite.azul,
            alignment: Alignment.center,
            child: Text(
              'DT',
              style: TextStyle(
                color: ColoresDonTramite.blanco,
                fontWeight: FontWeight.w900,
                fontSize: tamano * 0.34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PantallaArranque extends StatelessWidget {
  const PantallaArranque({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoDonTramite(tamano: 108),
            SizedBox(height: 26),
            Text(
              'DonTramite',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: ColoresDonTramite.negro,
              ),
            ),
            SizedBox(height: 22),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Franja con los colores institucionales.
class BarraColores extends StatelessWidget {
  const BarraColores({super.key, this.ancho = 440});

  final double ancho;

  @override
  Widget build(BuildContext context) {
    const colores = [
      ColoresDonTramite.azul,
      ColoresDonTramite.celeste,
      ColoresDonTramite.amarillo,
      ColoresDonTramite.gris,
      ColoresDonTramite.negro,
    ];
    return Container(
      height: 10,
      constraints: BoxConstraints(maxWidth: ancho),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: ColoresDonTramite.linea),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final color in colores) Expanded(child: ColoredBox(color: color)),
        ],
      ),
    );
  }
}
