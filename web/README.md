# Cliente web

- `public/index.html`: estructura accesible de acceso, chat y diálogos.
- `public/estilos.css`: diseño adaptable y preferencias de movimiento reducido.
- `public/js/cliente_api.js`: contrato HTTP, tiempos de espera y renovación de tokens.
- `public/js/aplicacion.js`: sesión y acciones de la interfaz.
- `public/js/vistas.js`: representación segura de texto, Markdown y fuentes.
- `public/js/herramientas.js`: integración opcional con navegadores que exponen WebMCP.
- `tests/`: pruebas del cliente y de los flujos de interfaz con servicios simulados.

Los identificadores y comentarios nuevos están en español; los nombres del
contrato HTTP (`access_token`, `conversation_id`, etc.) respetan la API existente.
No se utiliza almacenamiento persistente del navegador para credenciales.

Para iniciar, ejecuta `iniciar.bat` en la raíz y abre `/web/`. No abras el HTML con
`file://`: los módulos y las peticiones requieren HTTP. No se necesita `npm install`
para utilizar la web a través de FastAPI.

Para desarrollar y comprobar: `npm ci`, `npm test` y `npm run build`.
La distribución contiene sólo archivos públicos. En alojamiento independiente,
edita `dist/configuracion.json` con la URL HTTPS completa de la API después de
compilar; una compilación nueva vuelve a copiar la configuración de `public/`.

Las herramientas WebMCP se registran sólo cuando el navegador las admite. Comparten
la sesión y las validaciones del chat. Su funcionamiento necesita comprobarse en un
navegador compatible; la ausencia de esta API no afecta al uso normal de la web.
