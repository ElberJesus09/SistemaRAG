# Integración desde Flutter

La aplicación Flutter consume exclusivamente la API. La clave `SUPABASE_SERVICE_ROLE_KEY` y la clave de Gemini nunca deben estar dentro del APK.

## Dependencia

```yaml
dependencies:
  http: ^1.5.0
```

## Cliente mínimo

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ClienteRag {
  ClienteRag(this.urlBase);

  final String urlBase;
  String? tokenAcceso;
  String? conversacionId;

  Future<void> iniciarSesion(String correo, String contrasena) async {
    final respuesta = await http.post(
      Uri.parse('$urlBase/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': correo, 'password': contrasena}),
    );
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo iniciar sesión');
    }
    tokenAcceso = jsonDecode(respuesta.body)['access_token'] as String;
  }

  Future<void> crearConversacion({String? titulo}) async {
    final respuesta = await http.post(
      Uri.parse('$urlBase/api/v1/chat/conversations'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $tokenAcceso',
      },
      body: jsonEncode({'title': titulo}),
    );
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo crear la conversación');
    }
    conversacionId = jsonDecode(respuesta.body)['id'] as String;
  }

  Future<Map<String, dynamic>> preguntar(String pregunta) async {
    final respuesta = await http.post(
      Uri.parse('$urlBase/api/v1/chat/ask'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $tokenAcceso',
      },
      body: jsonEncode({
        'question': pregunta,
        'conversation_id': conversacionId,
      }),
    );
    if (respuesta.statusCode != 200) {
      throw Exception('No se pudo obtener la respuesta');
    }
    return jsonDecode(respuesta.body) as Map<String, dynamic>;
  }
}
```

La respuesta incluye `answer`, `answer_format`, `sources`, `latency_ms`, `question_id` y `model`. Guarda el `refresh_token` en almacenamiento seguro y usa `/api/v1/auth/refresh` para renovar la sesión.

## Formato de `answer`

El campo `answer` viene en **Markdown**, no en texto plano, y `answer_format` lo declara explícitamente. La API garantiza un subconjunto acotado y estable:

| Elemento | Cómo llega |
|---|---|
| Párrafo | Texto separado por una línea en blanco |
| Lista con viñetas | Líneas que empiezan con `- ` |
| Lista numerada | Líneas que empiezan con `1. `, `2. `, ... |
| Negrita | `**termino**` |

Nunca llegan encabezados `#`, tablas, bloques de código, citas `>`, enlaces `[texto](url)`, asteriscos sueltos ni guiones bajos: `app/services/gemini_service.py` normaliza la salida del modelo antes de devolverla, así que el cliente solo necesita pintar esos cuatro casos.

Si el widget muestra la respuesta con `Text()`, el usuario verá los asteriscos crudos. Usa un renderizador de Markdown:

```yaml
dependencies:
  flutter_markdown: ^0.7.0
```

```dart
import 'package:flutter_markdown/flutter_markdown.dart';

MarkdownBody(
  data: respuesta.respuesta,
  selectable: true,
  styleSheet: MarkdownStyleSheet(
    p: const TextStyle(fontSize: 16, height: 1.35),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    listBullet: const TextStyle(fontSize: 16),
  ),
)
```

El panel administrativo hace exactamente lo mismo en `app/static/panel.js` (función `renderizarMarkdown`), construyendo el DOM con `createElement` y `textContent` en lugar de `innerHTML`, porque el texto lo produce un modelo generativo.
