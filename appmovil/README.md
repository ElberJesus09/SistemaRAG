# DonTramite

Aplicacion Flutter para estudiantes. Consume la API RAG de `D:\SistemaRAG\plataforma_rag`
y funciona con el mismo codigo en **Android** y en **Web**.

## Que hace

- Acceso y registro con **solo correo y contrasena**. La app resuelve sola a que
  servidor conectarse; el estudiante nunca ve una URL.
- La sesion se guarda en el dispositivo y **se renueva sola** con el `refresh_token`,
  asi que no hay que volver a ingresar cada hora ni cada vez que se abre la app.
- Multiples conversaciones guardadas en el servidor: se listan, se abren con su
  historial completo, se renombran y se eliminan.
- Las respuestas se pintan con formato (titulos en negrita, listas numeradas y con
  vinetas) en vez de mostrar los asteriscos del Markdown.
- **La app no muestra las fuentes.** Ni los chips de documento y pagina, ni la linea
  "Fuente: ..." con la que la API cierra el texto. El dato sigue llegando en la respuesta
  y el panel administrativo lo sigue mostrando para poder auditar; solo se oculta al
  estudiante. Para volver a mostrarlo, quita `mostrarFuente: false` en
  `widgets/burbuja_mensaje.dart` y vuelve a pintar `Burbuja.fuentes`.
- Cada respuesta se puede calificar con pulgar arriba o abajo.
- Pantalla de cuenta: cambiar el nombre, cambiar la contrasena y cerrar sesion.

## Estructura

```
lib/
  main.dart                      Arranque y enrutado segun el estado de sesion
  nucleo/
    colores.dart                 Paleta institucional
    tema.dart                    ThemeData de la app
    configuracion.dart           A que servidor se conecta la app
  datos/
    modelos.dart                 Perfil, Conversacion, Intercambio, Fuente...
    cliente_api.dart             HTTP + renovacion automatica de sesion
    almacenamiento.dart          Sesion y ajustes persistidos
    excepciones.dart
  estado/
    sesion.dart                  Estado compartido (ChangeNotifier)
  pantallas/
    pantalla_acceso.dart         Ingresar / crear cuenta
    pantalla_principal.dart      Lista de chats + conversacion
    pantalla_cuenta.dart         Nombre, contrasena y cierre de sesion
  widgets/
    texto_markdown.dart          Renderizador del Markdown que devuelve la API
    burbuja_mensaje.dart         Burbuja de chat con fuentes
    panel_conversaciones.dart    Lista lateral de chats
    marca.dart                   Logo, pantalla de arranque, franja de colores
test/
  markdown_test.dart             Contrato de formato de las respuestas
  configuracion_test.dart        Resolucion y validacion de la URL
  widget_test.dart               La pantalla de acceso no pide servidor
```

## Como sabe la app a que servidor conectarse

Por orden de prioridad:

1. **`--dart-define=API_URL=...`** al compilar. Es lo que debe usarse en produccion.
2. Un valor guardado desde el **ajuste avanzado** (ver mas abajo), solo para pruebas.
3. Un valor por defecto segun la plataforma:

| Plataforma | Valor por defecto |
|---|---|
| Web servida desde un dominio real (puerto 80/443) | El mismo origen de la pagina |
| Web en el servidor de desarrollo de Flutter (8080, 5000...) | `http://<mismo host>:8000` |
| Emulador de Android | `http://10.0.2.2:8000` |
| Escritorio | `http://localhost:8000` |

### Ajuste avanzado (celular fisico)

Manten pulsado el **logo** de la pantalla de acceso durante 3 segundos. Se abre un
dialogo para escribir la IP de tu PC, por ejemplo `http://192.168.1.20:8000`.
El boton **Restablecer** vuelve al valor automatico. Este atajo no existe si la app
se compilo con `--dart-define=API_URL`.

## Ejecutar

Primero levanta la API:

```powershell
cd D:\SistemaRAG\plataforma_rag
.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Requisito de Windows: Modo de desarrollador

La app usa el plugin `shared_preferences`, y Flutter necesita crear enlaces simbolicos
para los plugins. Si el Modo de desarrollador esta desactivado veras:

```
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

Se activa una sola vez:

```powershell
start ms-settings:developers
```

Enciende **Modo de desarrollador**, cierra los ajustes y vuelve a ejecutar `flutter pub get`.

### Dependencias

```powershell
cd D:\SistemaRAG\appmovil
flutter pub get
```

### Android

```powershell
flutter run -d emulator-5554
```

### Web

La API permite CORS para los puertos 3000, 5000 y 8080 en `localhost` y `127.0.0.1`:

```powershell
flutter run -d chrome --web-port 8080
```

### Produccion

```powershell
flutter build web --dart-define=API_URL=https://tu-servidor
flutter build apk --release --dart-define=API_URL=https://tu-servidor
```

> En release, Android **exige https://**. El permiso para trafico `http://` sin
> cifrar solo esta en `android/app/src/debug/AndroidManifest.xml`, es decir, solo
> durante el desarrollo.

## Validar

```powershell
dart analyze
flutter test
```

## Si la compilacion de Android falla

En esta maquina el proyecto esta en `D:\` y la cache de paquetes de Dart en `C:\`.
Cuando un plugin trae codigo Kotlin, la cache incremental de Kotlin intenta guardar la
ruta del fuente relativa a la carpeta del proyecto y en Windows eso falla si estan en
unidades distintas:

```
this and base files have different roots:
C:\Users\...\shared_preferences_android-2.4.27\...\LegacySharedPreferencesPlugin.kt
y D:\SistemaRAG\appmovil\android
```

Por eso `android/gradle.properties` lleva `kotlin.incremental=false`. Solo se pierde
velocidad al recompilar el codigo Kotlin de los plugins, que casi nunca cambia; el
codigo Dart conserva el hot reload.

Si el error persiste porque quedaron caches corruptas del intento anterior, ejecuta
`reconstruir.bat` desde la raiz del proyecto: comprueba el Modo de desarrollador, detiene
los demonios de Gradle y Kotlin (en Windows mantienen los archivos bloqueados), borra
`build/`, `android/.gradle` y `android/.kotlin`, y vuelve a compilar.

### `JAVA_HOME is not set` al llamar a gradlew desde Git Bash

Solo afecta a ejecutar `./android/gradlew.bat` a mano: `flutter run` encuentra el JDK por
su cuenta, el que trae Android Studio. Si quieres usar gradlew directamente, mira donde
esta el JDK con `flutter doctor -v` (linea "Java binary at") y exportalo:

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
```

`reconstruir.bat` no lo necesita: detiene los demonios por nombre de proceso, sin Java.

Como alternativa, para recuperar la compilacion incremental, mueve la cache de paquetes
a la misma unidad:

```powershell
setx PUB_CACHE D:\pub-cache
# cierra y reabre la terminal
flutter pub get
```
