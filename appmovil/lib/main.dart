import 'package:flutter/material.dart';

import 'datos/almacenamiento.dart';
import 'datos/cliente_api.dart';
import 'estado/sesion.dart';
import 'nucleo/configuracion.dart';
import 'nucleo/tema.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/pantalla_principal.dart';
import 'widgets/marca.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final almacenamiento = await Almacenamiento.abrir();

  // Un --dart-define=API_URL manda siempre sobre lo guardado en el dispositivo.
  final url = ConfiguracionApi.tieneUrlFija
      ? ConfiguracionApi.urlPorDefecto()
      : (almacenamiento.urlGuardada ?? ConfiguracionApi.urlPorDefecto());

  final estado = EstadoSesion(
    cliente: ClienteApi(urlBase: url),
    almacenamiento: almacenamiento,
  );
  runApp(AplicacionDonTramite(estado: estado));
}

class AplicacionDonTramite extends StatefulWidget {
  const AplicacionDonTramite({super.key, required this.estado});

  final EstadoSesion estado;

  @override
  State<AplicacionDonTramite> createState() => _EstadoAplicacion();
}

class _EstadoAplicacion extends State<AplicacionDonTramite> {
  @override
  void initState() {
    super.initState();
    widget.estado.restaurar();
  }

  @override
  void dispose() {
    widget.estado.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DonTramite',
      debugShowCheckedModeBanner: false,
      theme: construirTema(),
      home: ListenableBuilder(
        listenable: widget.estado,
        builder: (context, _) {
          if (widget.estado.restaurando) return const PantallaArranque();
          if (widget.estado.iniciada) {
            return PantallaPrincipal(
              key: ValueKey(widget.estado.perfil?.id),
              estado: widget.estado,
            );
          }
          return PantallaAcceso(estado: widget.estado);
        },
      ),
    );
  }
}
