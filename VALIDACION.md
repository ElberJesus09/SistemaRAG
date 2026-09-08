# Validación del traslado y del cliente web

Realizada el 8 de septiembre de 2026 en `D:\Proyectos\SistemaRAG`.

## Resultados

| Comprobación | Resultado |
| --- | --- |
| Suite Python (API, rutas y transformación) | 36 pruebas aprobadas |
| Cliente HTTP y flujos web en DOM simulado | 18 pruebas aprobadas |
| Distribución estática con `npm run build` | Generada correctamente; 8 archivos públicos, aproximadamente 54 KB sin comprimir |
| API iniciada con la nueva ruta | Correcto |
| `/web/`, módulos JS, configuración, `/admin` y `/docs` | HTTP 200 |
| `/health?full=true` con servicios reales | HTTP 200; Supabase y embeddings de Gemini correctos |
| Búsqueda vectorial real mediante `match_chunks` | Correcta, sin modificar registros |
| Generación breve de Gemini con contexto de prueba | Correcta en la segunda comprobación; la primera recibió un 503 temporal por alta demanda |
| Conversión del PDF existente a JSONL | Correcta; el lector de ingesta de la API acepta sus fragmentos |
| Activadores y lanzadores del entorno virtual | Regenerados con la nueva ubicación; `pip`, `uvicorn` y `pytest` ejecutan correctamente |

## Cobertura y límites

Se reproduce un traslado a una carpeta con espacios y se verifica la carga de
`.env` desde otro directorio. Se comprueba que sólo se publiquen los archivos de
`web/public` y que las rutas privadas exijan autenticación y rol administrativo.

La interfaz se prueba con HTTP simulado: acceso, creación de conversaciones,
preguntas, fuentes y Markdown, texto HTML malicioso, valoración, renombrado,
perfil, cambio entre diálogos, eliminación confirmada, errores y respuestas tardías
tras cerrar sesión. También se verifica la renovación concurrente de tokens.

Las pruebas automatizadas no crean usuarios ni escriben en la base de producción.
Las comprobaciones reales consultan Supabase y utilizan solicitudes breves de
Gemini. No se ha validado un inicio de sesión con una cuenta real del usuario,
una carga documental real, ni la entrega del correo de confirmación.

No se realizaron pruebas visuales en un navegador real. La integración opcional
WebMCP necesita validación en un navegador que la implemente; no afecta al chat normal.
Docker no está instalado en este equipo: los archivos de despliegue están preparados,
pero no se ha ejecutado su imagen ni publicado el sistema en Internet.

La suite Python emite una advertencia de obsolescencia de Starlette sobre el uso
de httpx en TestClient; las pruebas finalizan correctamente.
