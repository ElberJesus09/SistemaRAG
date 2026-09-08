import 'package:appmovil/datos/almacenamiento.dart';
import 'package:appmovil/datos/cliente_api.dart';
import 'package:appmovil/datos/modelos.dart';
import 'package:appmovil/estado/sesion.dart';
import 'package:appmovil/main.dart';
import 'package:appmovil/widgets/burbuja_mensaje.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sin sesion guardada se muestra el acceso, sin pedir servidor', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final almacenamiento = await Almacenamiento.abrir();
    final estado = EstadoSesion(
      cliente: ClienteApi(urlBase: 'http://localhost:8000'),
      almacenamiento: almacenamiento,
    );

    await tester.pumpWidget(AplicacionDonTramite(estado: estado));
    await tester.pumpAndSettle();

    expect(find.text('DonTramite'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.text('Correo institucional'), findsOneWidget);
    expect(find.text('Contrasena'), findsOneWidget);

    // El campo de servidor ya no existe: la app resuelve la URL sola.
    expect(find.text('Servidor API'), findsNothing);
  });

  testWidgets('la respuesta no muestra de donde salio', (WidgetTester tester) async {
    const respuesta =
        'Necesitas el **DNI** vigente.\n\n'
        '- Copia simple\n'
        '- Recibo de pago\n\n'
        '**Fuente:** INFORMACION-CHATBOT.pdf, pagina 4';

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BurbujaMensaje(
          burbuja: Burbuja(
            texto: respuesta,
            esEstudiante: false,
            fuentes: [
              Fuente(
                documento: 'INFORMACION-CHATBOT.pdf',
                titulo: 'Grado de bachiller',
                similitud: 0.84,
                paginaInicio: 4,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // El contenido util si se ve...
    expect(find.textContaining('Necesitas'), findsOneWidget);
    expect(find.textContaining('Copia simple'), findsOneWidget);

    // ...pero ninguna referencia al documento de origen.
    expect(find.textContaining('Fuente'), findsNothing);
    expect(find.textContaining('INFORMACION-CHATBOT.pdf'), findsNothing);
    expect(find.textContaining('FUENTES'), findsNothing);
    expect(find.textContaining('Grado de bachiller'), findsNothing);
  });
}
