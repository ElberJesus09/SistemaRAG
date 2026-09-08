import 'package:appmovil/widgets/texto_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// La API garantiza un subconjunto fijo de Markdown. Estas pruebas fijan ese
/// contrato del lado del cliente: si la API dejara de normalizar, fallarian.
void main() {
  group('dividirNegritas', () {
    test('separa el termino en negrita del resto de la frase', () {
      final trozos = dividirNegritas('Paga **S/ 450.00** hoy');
      expect(trozos.length, 3);
      expect(trozos[0].texto, 'Paga ');
      expect(trozos[0].negrita, isFalse);
      expect(trozos[1].texto, 'S/ 450.00');
      expect(trozos[1].negrita, isTrue);
      expect(trozos[2].texto, ' hoy');
      expect(trozos[2].negrita, isFalse);
    });

    test('admite una linea que es solo negrita', () {
      final trozos = dividirNegritas('**Requisitos**');
      expect(trozos.length, 1);
      expect(trozos.single.texto, 'Requisitos');
      expect(trozos.single.negrita, isTrue);
    });

    test('no rompe con un par de asteriscos suelto', () {
      final trozos = dividirNegritas('2 ** 3 es una potencia');
      expect(trozos.length, 1);
      expect(trozos.single.negrita, isFalse);
      expect(trozos.single.texto, '2 ** 3 es una potencia');
    });

    test('descarta una negrita vacia', () {
      final trozos = dividirNegritas('a **** b');
      expect(trozos.map((t) => t.texto).toList(), ['a ', ' b']);
      expect(trozos.every((t) => !t.negrita), isTrue);
    });

    test('devuelve un trozo aunque la linea este vacia', () {
      expect(dividirNegritas('').length, 1);
    });
  });

  group('analizarMarkdown', () {
    const respuesta = '''
**Requisitos para el grado de bachiller**

Para iniciar el tramite necesitas:

- Constancia de egresado
- Recibo de pago de **S/ 450.00**

Luego sigue estos pasos:

1. Entrega el expediente
2. Espera la revision

**Fuente:** INFORMACION-CHATBOT.pdf, pagina 4''';

    test('reconoce parrafos, listas y la linea de fuente', () {
      final bloques = analizarMarkdown(respuesta);
      expect(bloques.map((b) => b.tipo).toList(), [
        TipoBloque.parrafo,
        TipoBloque.parrafo,
        TipoBloque.vinetas,
        TipoBloque.parrafo,
        TipoBloque.numerada,
        TipoBloque.fuente,
      ]);
      expect(bloques[2].lineas.length, 2);
      expect(bloques[4].lineas.length, 2);
    });

    test('conserva la negrita dentro de un elemento de lista', () {
      final bloques = analizarMarkdown(respuesta);
      final segundoItem = bloques[2].lineas[1];
      expect(segundoItem.any((t) => t.negrita && t.texto == 'S/ 450.00'), isTrue);
    });

    test('separa listas de distinto tipo aunque esten pegadas', () {
      final bloques = analizarMarkdown('- uno\n1. dos\n- tres');
      expect(bloques.map((b) => b.tipo).toList(), [
        TipoBloque.vinetas,
        TipoBloque.numerada,
        TipoBloque.vinetas,
      ]);
    });

    test('une las lineas de un mismo parrafo con un espacio', () {
      final bloques = analizarMarkdown('primera linea\nsegunda linea');
      expect(bloques.single.lineas.single.single.texto, 'primera linea segunda linea');
    });

    test('no produce bloques con texto vacio', () {
      expect(analizarMarkdown(''), isEmpty);
      expect(analizarMarkdown('   \n\n  '), isEmpty);
    });
  });
}
