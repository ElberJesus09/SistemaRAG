# Plataforma RAG con Supabase y Gemini

API preparada para clientes web y móviles. Incluye usuarios, recuperación semántica, respuestas con fuentes, carga de JSONL, panel administrativo, auditoría, métricas y alertas. La web de usuarios está en `/web/`; consulta el README de la raíz para iniciar todo con `iniciar.bat`.

## Tecnologías y modelos

- API: FastAPI y Python 3.12.
- Autenticación y base de datos: Supabase Auth + PostgreSQL.
- Vectores: `pgvector`, 768 dimensiones e índice HNSW.
- Embeddings: `gemini-embedding-2`.
- Respuestas: `gemini-3.6-flash` estable.
- Panel: HTML, CSS y JavaScript sin proceso de compilación.

## 1. Crear y preparar Supabase

1. Crea un proyecto en Supabase.
2. Abre **SQL Editor**.
3. Ejecuta en orden los archivos de `supabase/migrations/`:
   `001_esquema_inicial.sql`, `002_permisos_api.sql`, `003_conversaciones_memoria.sql`
   `004_metricas_y_limites.sql` y `005_usuarios_y_actividad.sql`. Si el esquema ya existía, basta con ejecutar los
   que falten; todos son idempotentes.
4. En Authentication configura si exigirás confirmación por correo.
5. Copia la URL, la clave `anon` y la clave `service_role` desde Project Settings > API.

La clave `service_role` omite RLS: debe existir únicamente en el servidor. No debe incluirse en Flutter, repositorios ni JavaScript público.

## 2. Obtener la clave de Gemini

1. Crea una API key desde Google AI Studio.
2. Restringe la clave cuando el entorno de despliegue lo permita.
3. No la incluyas en Flutter.

## 3. Configurar el proyecto

```powershell
cd D:\Proyectos\SistemaRAG\plataforma_rag
..\instalar.bat
```

Completa en `.env`:

```dotenv
SUPABASE_URL=https://TU_PROYECTO.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
GEMINI_API_KEY=...
```

## 4. Iniciar y crear el primer administrador

```powershell
.\run.bat --reload
```

1. Registra un usuario con `POST /api/v1/auth/register` desde `http://localhost:8000/docs`.
2. Si activaste confirmación de correo, confírmalo.
3. Busca su UUID en Supabase > Authentication > Users.
4. Ejecuta:

```sql
update public.profiles set role = 'admin' where id = 'UUID_DEL_USUARIO';
```

5. Abre `http://localhost:8000` e inicia sesión.

## 5. Cargar información

En el panel entra a **Documentos** y sube únicamente el archivo `*.chunks.jsonl` creado por `transformacion`. El archivo `manifest.json` no se carga.

La API valida el archivo, genera un embedding independiente por chunk y lo guarda en Supabase. Esta separación evita que Gemini Embedding 2 agregue varios chunks en un solo vector.

## Endpoints principales

| Método | Ruta | Acceso | Uso |
|---|---|---|---|
| POST | `/api/v1/auth/register` | Público | Crear usuario |
| POST | `/api/v1/auth/login` | Público | Iniciar sesión |
| POST | `/api/v1/auth/refresh` | Público | Renovar sesión |
| GET | `/api/v1/auth/me` | Usuario | Perfil actual |
| PATCH | `/api/v1/auth/me` | Usuario | Cambiar el nombre |
| POST | `/api/v1/auth/password` | Usuario | Cambiar la contraseña |
| GET | `/api/v1/chat/conversations` | Usuario | Listar sus conversaciones |
| POST | `/api/v1/chat/conversations` | Usuario | Crear conversación |
| GET | `/api/v1/chat/conversations/{id}/messages` | Usuario | Historial de una conversación |
| PATCH/DELETE | `/api/v1/chat/conversations/{id}` | Usuario | Renombrar o eliminar |
| POST | `/api/v1/chat/ask` | Usuario | Preguntar al RAG |
| POST | `/api/v1/chat/questions/{id}/feedback` | Usuario | Calificar respuesta |
| POST | `/api/v1/admin/documents/upload` | Administrador | Cargar JSONL (responde 202) |
| GET | `/api/v1/admin/jobs` y `/jobs/{id}` | Administrador | Progreso de las cargas |
| GET | `/api/v1/admin/overview` | Administrador | Indicadores |
| GET | `/api/v1/admin/questions` | Administrador | Auditoría de preguntas |
| GET/PATCH | `/api/v1/admin/alerts` | Administrador | Gestionar alertas |
| GET | `/api/v1/admin/audit` | Administrador | Registro de acciones |

La documentación OpenAPI está en `/docs`. `/health` comprueba de verdad la conexión
con Supabase y devuelve 503 si no responde; `/health?full=true` comprueba además Gemini
gastando una llamada de embedding.

## Formato de las respuestas

`answer` viaja en **Markdown acotado**: párrafos, listas con `- `, listas `1. ` y
`**negrita**`. Nada más. `gemini_service.normalizar_markdown()` fuerza ese subconjunto
antes de devolver la respuesta, de modo que el panel y la app Flutter pueden pintarla
con un renderizador mínimo. El campo `answer_format` lo declara explícitamente.

## Rendimiento y límites

- **Carga de documentos asíncrona.** `POST /admin/documents/upload` valida el archivo,
  responde `202` con un `job_id` y genera los embeddings en segundo plano. El panel
  consulta `GET /admin/jobs/{id}` y muestra el progreso real. Antes, un documento grande
  agotaba el tiempo del proxy y la carga se perdía a medias.
- **Caché de autenticación.** Un token ya validado se reutiliza `AUTH_CACHE_SECONDS`
  segundos (300 por defecto). Sin esto, cada petición autenticada costaba dos viajes de
  red a Supabase. El precio es que un token revocado sigue siendo válido como máximo ese
  tiempo; pon `AUTH_CACHE_SECONDS=0` para desactivarlo.
- **Métricas en Postgres.** `metricas_resumen()` (migración 004) agrega dentro de la base
  en vez de traer 10 000 filas a Python. Si la migración no está aplicada, el servicio lo
  detecta y cae en el cálculo anterior.
- **Límite de uso.** `ASK_RATE_LIMIT_PER_HOUR` (60 por defecto) acota las preguntas por
  usuario y hora; devuelve `429`. Pon `0` para desactivarlo.

## Registro

Con `LOG_JSON=true` cada evento sale como una línea JSON con el `X-Request-ID` de la
petición, el método, la ruta, el estado y los milisegundos. Las peticiones que superan
`SLOW_REQUEST_MS` se registran como advertencia.

## Alertas automáticas

Se crea una alerta cuando una pregunta no recupera contexto, supera `SLOW_REQUEST_MS`, falla Gemini/Supabase o falla una carga documental. El panel permite resolverlas y registra la acción en auditoría.

## Producción

- Usa HTTPS y limita `CORS_ORIGINS` al dominio real de Flutter Web o del panel.
- Ejecuta Uvicorn detrás de un proxy o despliega el `Dockerfile`, que corre como usuario
  sin privilegios, trae `HEALTHCHECK` y respeta `WEB_CONCURRENCY`.
- Desactiva `--reload` y pon `LOG_JSON=true`.
- Configura límites de gasto y cuota en Gemini.
- Conserva copias de seguridad de Supabase.
- Rota las claves si alguna se expone.

Consulta [INTEGRACION_FLUTTER.md](INTEGRACION_FLUTTER.md) para el cliente de ejemplo.
