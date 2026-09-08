import 'package:flutter/material.dart';

import '../nucleo/colores.dart';

/// Pinta el Markdown acotado que garantiza la API.
///
/// La API (`app/services/gemini_service.py`) normaliza toda respuesta a solo
/// cuatro construcciones, así que no hace falta un paquete externo:
///   - párrafos separados por una línea en blanco
///   - listas con viñetas que empiezan por "- "
///   - listas numeradas que empiezan por "1. "
///   - negrita entre dobles asteriscos
class TextoMarkdown extends StatelessWidget {
  const TextoMarkdown(
    this.contenido, {
    super.key,
    this.color = ColoresDonTramite.negro,
    this.tamano = 15.5,
    this.seleccionable = true,
    this.mostrarFuente = true,
  });

  final String contenido;
  final Color color;
  final double tamano;
  final bool seleccionable;

  /// La API cierra cada respuesta con una linea "Fuente: documento, pagina N".
  /// El panel administrativo la muestra; la app del estudiante no.
  final bool mostrarFuente;

  @override
  Widget build(BuildContext context) {
    final todos = analizarMarkdown(contenido);
    final bloques = mostrarFuente
        ? todos
        : todos.where((b) => b.tipo != TipoBloque.fuente).toList();

    if (bloques.isEmpty) {
      // Si el analizador no reconocio nada, se pinta el texto tal cual; si lo
      // unico que habia era la linea de fuente y esta oculta, no se pinta nada.
      return todos.isEmpty
          ? _texto(TextSpan(text: contenido, style: _estiloBase))
          : const SizedBox.shrink();
    }

    final hijos = <Widget>[];
    for (var i = 0; i < bloques.length; i++) {
      final bloque = bloques[i];
      if (i > 0) hijos.add(SizedBox(height: bloque.tipo == TipoBloque.fuente ? 12 : 10));
      hijos.add(_construirBloque(bloque));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos);
  }

  TextStyle get _estiloBase =>
      TextStyle(color: color, fontSize: tamano, height: 1.42);

  Widget _texto(TextSpan span) => seleccionable
      ? SelectableText.rich(span)
      : RichText(text: span);

  Widget _construirBloque(BloqueMarkdown bloque) {
    final esLista =
        bloque.tipo == TipoBloque.vinetas || bloque.tipo == TipoBloque.numerada;

    if (esLista) {
      final numerada = bloque.tipo == TipoBloque.numerada;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < bloque.lineas.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == bloque.lineas.length - 1 ? 0 : 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: numerada ? 26 : 18,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        numerada ? '${i + 1}.' : '\u2022',
                        style: _estiloBase.copyWith(
                          color: ColoresDonTramite.azul,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _texto(
                      TextSpan(children: _spans(bloque.lineas[i]), style: _estiloBase),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    if (bloque.tipo == TipoBloque.fuente) {
      return Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ColoresDonTramite.linea)),
        ),
        child: _texto(
          TextSpan(
            children: _spans(bloque.lineas.first),
            style: _estiloBase.copyWith(
              fontSize: tamano - 2,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    return _texto(TextSpan(children: _spans(bloque.lineas.first), style: _estiloBase));
  }

  List<TextSpan> _spans(List<TrozoMarkdown> trozos) => [
    for (final trozo in trozos)
      TextSpan(
        text: trozo.texto,
        style: trozo.negrita ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
  ];
}

// ------------------------------- Analizador --------------------------------

enum TipoBloque { parrafo, fuente, vinetas, numerada }

class TrozoMarkdown {
  const TrozoMarkdown(this.texto, this.negrita);

  final String texto;
  final bool negrita;
}

class BloqueMarkdown {
  const BloqueMarkdown(this.tipo, this.lineas);

  final TipoBloque tipo;
  final List<List<TrozoMarkdown>> lineas;
}

final RegExp _reVineta = RegExp(r'^-\s+(.*)$');
final RegExp _reNumerada = RegExp(r'^(\d{1,2})\.\s+(.*)$');
final RegExp _reFuente = RegExp(r'^\*{0,2}fuente\s*:?\*{0,2}', caseSensitive: false);

/// Parte una línea en trozos normales y en negrita.
List<TrozoMarkdown> dividirNegritas(String linea) {
  final trozos = <TrozoMarkdown>[];
  var resto = linea;
  while (true) {
    final inicio = resto.indexOf('**');
    if (inicio < 0) break;
    final fin = resto.indexOf('**', inicio + 2);
    if (fin < 0) break;
    if (inicio > 0) trozos.add(TrozoMarkdown(resto.substring(0, inicio), false));
    final contenido = resto.substring(inicio + 2, fin);
    if (contenido.isNotEmpty) trozos.add(TrozoMarkdown(contenido, true));
    resto = resto.substring(fin + 2);
  }
  if (resto.isNotEmpty) trozos.add(TrozoMarkdown(resto, false));
  if (trozos.isEmpty) trozos.add(const TrozoMarkdown('', false));
  return trozos;
}

List<BloqueMarkdown> analizarMarkdown(String fuente) {
  final bloques = <BloqueMarkdown>[];
  final parrafo = <String>[];
  TipoBloque? tipoLista;
  var itemsLista = <List<TrozoMarkdown>>[];

  void cerrarParrafo() {
    if (parrafo.isEmpty) return;
    final unido = parrafo.join(' ').trim();
    parrafo.clear();
    if (unido.isEmpty) return;
    final tipo = _reFuente.hasMatch(unido) ? TipoBloque.fuente : TipoBloque.parrafo;
    bloques.add(BloqueMarkdown(tipo, [dividirNegritas(unido)]));
  }

  void cerrarLista() {
    if (tipoLista == null || itemsLista.isEmpty) {
      tipoLista = null;
      itemsLista = <List<TrozoMarkdown>>[];
      return;
    }
    bloques.add(BloqueMarkdown(tipoLista!, itemsLista));
    tipoLista = null;
    itemsLista = <List<TrozoMarkdown>>[];
  }

  for (final cruda in fuente.split('\n')) {
    final linea = cruda.trim();
    if (linea.isEmpty) {
      cerrarParrafo();
      cerrarLista();
      continue;
    }

    final vineta = _reVineta.firstMatch(linea);
    final numerada = vineta == null ? _reNumerada.firstMatch(linea) : null;

    if (vineta != null || numerada != null) {
      cerrarParrafo();
      final tipo = vineta != null ? TipoBloque.vinetas : TipoBloque.numerada;
      if (tipoLista != tipo) cerrarLista();
      tipoLista = tipo;
      final texto = (vineta != null ? vineta.group(1) : numerada!.group(2)) ?? '';
      itemsLista.add(dividirNegritas(texto.trim()));
      continue;
    }

    cerrarLista();
    parrafo.add(linea);
  }

  cerrarParrafo();
  cerrarLista();
  return bloques;
}
