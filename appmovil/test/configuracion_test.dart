import 'package:appmovil/nucleo/configuracion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfiguracionApi.normalizar', () {
    test('quita espacios y barras finales', () {
      expect(ConfiguracionApi.normalizar('  http://localhost:8000/  '),
          'http://localhost:8000');
      expect(ConfiguracionApi.normalizar('https://api.edu.pe///'), 'https://api.edu.pe');
    });

    test('deja intacta una URL ya limpia', () {
      expect(ConfiguracionApi.normalizar('http://10.0.2.2:8000'), 'http://10.0.2.2:8000');
    });
  });

  group('ConfiguracionApi.esValida', () {
    test('acepta http y https con host', () {
      expect(ConfiguracionApi.esValida('http://192.168.1.20:8000'), isTrue);
      expect(ConfiguracionApi.esValida('https://dontramite.edu.pe'), isTrue);
    });

    test('rechaza lo que no es una direccion utilizable', () {
      expect(ConfiguracionApi.esValida('192.168.1.20:8000'), isFalse);
      expect(ConfiguracionApi.esValida('ftp://servidor'), isFalse);
      expect(ConfiguracionApi.esValida(''), isFalse);
      expect(ConfiguracionApi.esValida('http://'), isFalse);
    });
  });
}
