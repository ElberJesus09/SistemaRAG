# Sistema RAG

API FastAPI, transformador de PDF y cliente web en español. La web utiliza HTML,
CSS y módulos JavaScript nativos: no descarga frameworks ni requiere Node.js para funcionar.
Supabase gestiona usuarios y datos; Gemini genera embeddings y respuestas.

## Iniciar en Windows

Desde `D:\Proyectos\SistemaRAG`:

```powershell
.\instalar.bat
# Completa plataforma_rag/.env con tus credenciales si es una instalación nueva.
.\iniciar.bat
```

- Web de usuarios: <http://127.0.0.1:8000/web/>
- Panel administrativo: <http://127.0.0.1:8000/admin> (también conserva `/`).
- Documentación de la API: <http://127.0.0.1:8000/docs>
- Salud: <http://127.0.0.1:8000/health>. Añade `?full=true` para comprobar embeddings de Gemini; consume una solicitud.

`plataforma_rag\run.bat` inicia el mismo sistema. Para desarrollo:

```powershell
.\iniciar.bat --reload
# Otro puerto:
.\iniciar.bat --port 8010
# Desde cualquier directorio, incluyendo rutas con espacios:
& 'D:\Proyectos\SistemaRAG\plataforma_rag\.venv\Scripts\python.exe' 'D:\Proyectos\SistemaRAG\iniciar.py'
```

El servidor escucha sólo en tu equipo por defecto. `.env`, los estáticos y los
scripts se resuelven desde su ubicación, sin depender del directorio de trabajo.
El nombre correcto de la carpeta es `plataforma_rag`, sin barra antes del guion bajo.

## Transformar documentos

Ejecuta `transformacion\iniciar.bat`; utiliza el mismo entorno virtual que la API.
Selecciona un PDF con texto y una carpeta de salida. Carga su archivo
`*.chunks.jsonl` en **Documentos** del panel administrativo. No cargues el manifiesto.
Los archivos de entrada y salida existentes se conservan.

## Uso de la web

Regístrate o inicia sesión con una cuenta de Supabase. Si el proyecto exige
confirmación de correo, confirma el mensaje antes de entrar. Puedes preguntar,
retomar hasta 200 conversaciones recientes, renombrarlas o eliminarlas, consultar
fuentes, valorar respuestas y editar tu perfil o contraseña.

Los tokens se mantienen exclusivamente en memoria. Al recargar o cerrar la página
debes iniciar sesión otra vez; el historial permanece en Supabase. Un token vencido
se renueva automáticamente mientras la página está abierta. Cerrar sesión elimina
los tokens de esta página; no revoca las sesiones de otros dispositivos.

Las respuestas se muestran con el Markdown limitado de la API, sin ejecutar HTML.
Ante una espera agotada, se conserva el borrador: actualiza la conversación antes de
reenviar para comprobar si el servidor ya guardó la respuesta.

## Pruebas

```powershell
.\plataforma_rag\.venv\Scripts\python.exe -m pytest -q
cd web
npm ci
npm test
npm run build
```

La suite Python usa credenciales ficticias y dobles de servicios; no escribe en la
base real. Incluye una conversión del PDF existente a un directorio temporal y
valida el JSONL con el lector de la API. Las pruebas web verifican el cliente HTTP
y los formularios/chat en un DOM simulado, incluyendo errores, expiración de sesión
y contenido malicioso. No sustituyen una prueba visual en navegadores reales.

Node.js 22.22.2 o 24.15.0 (o posteriores dentro de esas ramas; también 26+) sólo se necesita para pruebas y distribución; las dependencias
de desarrollo no se envían al navegador. `npm run build` genera `web/dist`.

## Preparación para producción

La opción sencilla es servir API y web bajo el mismo dominio HTTPS, conservando
`/web/`, `/api/v1` y `/admin`. No hace falta habilitar CORS entre ellas.
El Dockerfile de la raíz incluye ambas; el antiguo `plataforma_rag/Dockerfile`
sigue siendo sólo para la API y el panel.

```powershell
docker compose up --build -d
```

El contenedor ejecuta el proceso sin privilegios de administrador y recibe las
credenciales mediante variables de entorno; no las copia a la imagen. El puerto
se publica en `127.0.0.1:8000` para colocar un proxy HTTPS delante. En tu alojamiento
configura el dominio, certificado TLS, secretos y reinicio del servicio. No actives
`--reload` en producción. Aplica en orden las cinco migraciones de
`plataforma_rag/supabase/migrations/` antes de usar todas las funciones.

Para alojar la web por separado, publica únicamente `web/dist` y cambia su
`configuracion.json` a `{"url_api":"https://api.tudominio.com/api/v1"}`. Configura
`CORS_ORIGINS` en la API con el origen HTTPS exacto de la web. Nunca uses una ruta
de disco como URL de la API ni pongas claves de Supabase/Gemini en la web.

La ruta `/web/configuracion.json`, cuando sirve FastAPI, anuncia automáticamente
`API_PREFIX`. `WEB_DIRECTORY` permite indicar un directorio público alternativo
(usa una ruta absoluta). El panel existente conserva `/api/v1` como prefijo.

Esta entrega es local. Docker y la publicación en Internet requieren validación
en el entorno de despliegue elegido. Antes de escalar a varios procesos, revisa la
consistencia de cuotas y los trabajos de ingesta que actualmente corren en memoria.
