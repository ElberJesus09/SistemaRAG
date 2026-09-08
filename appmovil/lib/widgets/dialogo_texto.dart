import 'package:flutter/material.dart';

import '../nucleo/colores.dart';

/// Pide un texto en un dialogo.
///
/// El `TextEditingController` lo posee el propio dialogo y se libera en su
/// `dispose`. Crearlo fuera y liberarlo justo despues de `await showDialog`
/// rompia la app: `showDialog` regresa en cuanto la ruta se cierra, pero el
/// campo sigue montado durante la animacion de salida y sigue escuchando al
/// controlador, asi que liberarlo ahi disparaba
/// `'_dependents.isEmpty': is not true`.
///
/// Devuelve `null` si se cancela, el texto escrito al aceptar, y una cadena
/// vacia si se pulsa la accion alterna (por ejemplo "Restablecer").
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  String valorInicial = '',
  String? ayuda,
  int? maxCaracteres,
  String textoAceptar = 'Guardar',
  String? textoAlterno,
  TextInputType? teclado,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _DialogoTexto(
      titulo: titulo,
      etiqueta: etiqueta,
      valorInicial: valorInicial,
      ayuda: ayuda,
      maxCaracteres: maxCaracteres,
      textoAceptar: textoAceptar,
      textoAlterno: textoAlterno,
      teclado: teclado,
    ),
  );
}

class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.etiqueta,
    required this.valorInicial,
    required this.ayuda,
    required this.maxCaracteres,
    required this.textoAceptar,
    required this.textoAlterno,
    required this.teclado,
  });

  final String titulo;
  final String etiqueta;
  final String valorInicial;
  final String? ayuda;
  final int? maxCaracteres;
  final String textoAceptar;
  final String? textoAlterno;
  final TextInputType? teclado;

  @override
  State<_DialogoTexto> createState() => _EstadoDialogoTexto();
}

class _EstadoDialogoTexto extends State<_DialogoTexto> {
  late final TextEditingController _controlador =
      TextEditingController(text: widget.valorInicial);

  @override
  void dispose() {
    // Aqui si es seguro: el campo ya no existe cuando el dialogo se desmonta.
    _controlador.dispose();
    super.dispose();
  }

  void _aceptar() => Navigator.of(context).pop(_controlador.text.trim());

  @override
  Widget build(BuildContext context) {
    final ayuda = widget.ayuda;
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ayuda != null) ...[
            Text(
              ayuda,
              style: const TextStyle(
                fontSize: 13,
                color: ColoresDonTramite.textoTenue,
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _controlador,
            autofocus: true,
            autocorrect: false,
            keyboardType: widget.teclado,
            maxLength: widget.maxCaracteres,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _aceptar(),
            decoration: InputDecoration(labelText: widget.etiqueta),
          ),
        ],
      ),
      actions: [
        if (widget.textoAlterno != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(widget.textoAlterno!),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _aceptar, child: Text(widget.textoAceptar)),
      ],
    );
  }
}
