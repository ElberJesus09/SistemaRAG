/* ============================================================
   Panel de la Plataforma RAG
   Sin dependencias ni build. Todo el DOM se construye con
   createElement/textContent: nunca innerHTML, porque el texto de
   las respuestas lo produce un modelo generativo.
   ============================================================ */

const API = "/api/v1";
let token = sessionStorage.getItem("token_rag") || "";
let usuario = null;
let preguntas = [];
let auditoria = [];
let crudo = "";

const porId = (id) => document.getElementById(id);
const texto = (v, d = "—") => (v === null || v === undefined || v === "" ? d : String(v));
const numero = (v) => Number(v ?? 0).toLocaleString("es-PE");
const ms = (v) => `${numero(Math.round(Number(v ?? 0)))} ms`;
const fecha = (v) => (v ? new Date(v).toLocaleString("es-PE", {
  day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
}) : "—");
const fechaCorta = (v) =>
  v ? new Date(`${v}T12:00:00`).toLocaleDateString("es-PE", { day: "2-digit", month: "short" }) : "";

function crear(etiqueta, clase, contenido) {
  const nodo = document.createElement(etiqueta);
  if (clase) nodo.className = clase;
  if (contenido !== undefined) nodo.textContent = contenido;
  return nodo;
}

const ESTADOS = {
  answered: "Respondida", no_results: "Sin contexto", error: "Error",
  active: "Activo", processing: "Procesando", failed: "Fallido", archived: "Archivado",
};
const SEVERIDADES = { info: "Informativa", warning: "Advertencia", error: "Error", critical: "Crítica" };
const TITULOS = {
  resumen: "Resumen general", pruebas: "Probar el asistente", usuarios: "Usuarios",
  documentos: "Gestión documental", alertas: "Alertas del sistema", auditoria: "Auditoría",
};

/* ---------- 1. API ---------- */
async function solicitar(ruta, opciones = {}) {
  const cabeceras = new Headers(opciones.headers || {});
  if (token) cabeceras.set("Authorization", `Bearer ${token}`);
  if (opciones.body && !(opciones.body instanceof FormData)) {
    cabeceras.set("Content-Type", "application/json");
  }
  let respuesta;
  try {
    respuesta = await fetch(`${API}${ruta}`, { ...opciones, headers: cabeceras });
  } catch (_) {
    throw new Error("No se pudo contactar al servidor. ¿La API está encendida?");
  }
  if (respuesta.status === 401 && ruta !== "/auth/login") {
    cerrarSesion();
    throw new Error("La sesión venció. Vuelve a ingresar.");
  }
  if (!respuesta.ok) {
    let detalle = `Error ${respuesta.status}`;
    try {
      const cuerpo = await respuesta.json();
      if (typeof cuerpo.detail === "string") detalle = cuerpo.detail;
    } catch (_) { /* sin JSON */ }
    throw new Error(detalle);
  }
  return respuesta.status === 204 ? null : respuesta.json();
}

function avisar(mensaje, tipo = "info") {
  const caja = crear("div", `aviso ${tipo}`);
  caja.append(crear("span", "", mensaje));
  porId("avisos").append(caja);
  setTimeout(() => { caja.style.opacity = "0"; setTimeout(() => caja.remove(), 250); }, 4200);
}

/* ---------- 2. Markdown acotado ----------
   La API garantiza parrafos, "- ", "1. " y **negrita**. Nada mas. */
function aplicarNegritas(linea, destino) {
  linea.split(/(\*\*[^*]+\*\*)/g).forEach((parte) => {
    if (!parte) return;
    if (parte.startsWith("**") && parte.endsWith("**") && parte.length > 4) {
      destino.append(crear("strong", "", parte.slice(2, -2)));
    } else {
      destino.append(document.createTextNode(parte));
    }
  });
}

function renderizarMarkdown(fuente, contenedor) {
  contenedor.replaceChildren();
  let parrafo = [];
  let lista = null;

  const cerrarParrafo = () => {
    if (!parrafo.length) return;
    const unido = parrafo.join(" ").trim();
    parrafo = [];
    if (!unido) return;
    const nodo = crear("p", /^\*{0,2}fuente\s*:?\*{0,2}/i.test(unido) ? "cita" : "");
    aplicarNegritas(unido, nodo);
    contenedor.append(nodo);
  };

  String(fuente || "").split("\n").forEach((cruda) => {
    const linea = cruda.trim();
    if (!linea) { cerrarParrafo(); lista = null; return; }
    const vineta = linea.match(/^-\s+(.*)$/);
    const numerada = vineta ? null : linea.match(/^\d{1,2}\.\s+(.*)$/);
    if (vineta || numerada) {
      cerrarParrafo();
      const tipo = vineta ? "ul" : "ol";
      if (!lista || lista.tagName.toLowerCase() !== tipo) {
        lista = crear(tipo);
        contenedor.append(lista);
      }
      const item = crear("li");
      aplicarNegritas((vineta ? vineta[1] : numerada[1]).trim(), item);
      lista.append(item);
      return;
    }
    lista = null;
    parrafo.push(linea);
  });
  cerrarParrafo();
  if (!contenedor.childNodes.length) contenedor.append(crear("p", "apoyo", "La respuesta llegó vacía."));
}

/* ---------- 3. Modal ---------- */
function abrirModal(rotulo, titulo, construirCuerpo) {
  porId("modal-rotulo").textContent = rotulo;
  porId("modal-titulo").textContent = titulo;
  const cuerpo = porId("modal-cuerpo");
  cuerpo.replaceChildren();
  construirCuerpo(cuerpo);
  porId("modal").showModal();
}
function cerrarModal() { porId("modal").close(); }

/** Caja con un valor que hay que copiar (enlace o contraseña). */
function cajaSecreta(valor) {
  const caja = crear("div", "secreto");
  caja.append(crear("code", "", valor));
  const boton = crear("button", "secundario", "Copiar");
  boton.type = "button";
  boton.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(valor);
      boton.textContent = "Copiado";
      setTimeout(() => { boton.textContent = "Copiar"; }, 1800);
    } catch (_) {
      avisar("El navegador no permitió copiar. Selecciónalo a mano.", "error");
    }
  });
  caja.append(boton);
  return caja;
}

/* ---------- 4. Estados de carga ---------- */
function esqueletoFilas(cuerpo, columnas, filas = 4) {
  cuerpo.replaceChildren();
  for (let f = 0; f < filas; f += 1) {
    const fila = document.createElement("tr");
    for (let c = 0; c < columnas; c += 1) {
      const celda = document.createElement("td");
      celda.append(crear("div", "esqueleto"));
      fila.append(celda);
    }
    cuerpo.append(fila);
  }
}

function filaVacia(cuerpo, columnas, titulo, detalle) {
  cuerpo.replaceChildren();
  const fila = document.createElement("tr");
  const celda = document.createElement("td");
  celda.colSpan = columnas;
  const caja = crear("div", "vacio");
  caja.append(crear("span", "emoji", "🗂️"), crear("strong", "", titulo));
  if (detalle) caja.append(crear("small", "", detalle));
  celda.append(caja);
  fila.append(celda);
  cuerpo.append(fila);
}

function bloqueVacio(contenedor, emoji, titulo, detalle) {
  contenedor.replaceChildren();
  const caja = crear("div", "vacio");
  caja.append(crear("span", "emoji", emoji), crear("strong", "", titulo));
  if (detalle) caja.append(crear("small", "", detalle));
  contenedor.append(caja);
}

/* ---------- 5. Tema ---------- */
function temaGuardado() {
  try { return localStorage.getItem("tema_rag") || ""; } catch (_) { return ""; }
}
function aplicarTema(valor) {
  document.documentElement.dataset.tema = valor;
  const oscuro = valor === "oscuro"
    || (valor === "" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  porId("alternar-tema").textContent = oscuro ? "Modo claro" : "Modo oscuro";
  try { localStorage.setItem("tema_rag", valor); } catch (_) { /* modo privado */ }
}
document.documentElement.dataset.tema = temaGuardado();

/* ---------- 6. Acceso ---------- */
porId("formulario-acceso").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const boton = porId("boton-acceso");
  porId("error-acceso").textContent = "";
  boton.disabled = true;
  boton.textContent = "Verificando...";
  try {
    const datos = await solicitar("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email: porId("correo").value, password: porId("contrasena").value }),
    });
    if (!datos.access_token) throw new Error("Confirma primero tu correo electrónico.");
    token = datos.access_token;
    sessionStorage.setItem("token_rag", token);
    const perfil = await solicitar("/auth/me");
    if (perfil.role !== "admin") throw new Error("Este usuario no tiene rol de administrador.");
    usuario = perfil;
    await mostrarAplicacion();
  } catch (error) {
    token = "";
    sessionStorage.removeItem("token_rag");
    porId("error-acceso").textContent = error.message;
  } finally {
    boton.disabled = false;
    boton.textContent = "Ingresar";
  }
});

function cerrarSesion() {
  token = "";
  usuario = null;
  sessionStorage.removeItem("token_rag");
  porId("aplicacion").classList.add("oculto");
  porId("inicio-sesion").classList.remove("oculto");
}
porId("cerrar-sesion").addEventListener("click", cerrarSesion);

async function mostrarAplicacion() {
  porId("inicio-sesion").classList.add("oculto");
  porId("aplicacion").classList.remove("oculto");
  aplicarTema(temaGuardado());
  if (usuario) {
    const nombre = usuario.full_name || "Administrador";
    porId("nombre-usuario").textContent = nombre;
    porId("correo-usuario").textContent = usuario.email || "";
    porId("avatar").textContent = nombre.trim().charAt(0).toUpperCase() || "A";
  }
  await Promise.all([cargarResumen(), comprobarSalud(), cargarAlertas(true), cargarUsuarios(true)]);
}

/* ---------- 7. Navegación ---------- */
document.querySelectorAll(".navegacion").forEach((boton) => {
  boton.addEventListener("click", async () => {
    const destino = boton.dataset.seccion;
    document.querySelectorAll(".navegacion").forEach((i) => i.classList.remove("activo"));
    boton.classList.add("activo");
    document.querySelectorAll(".seccion").forEach((i) => i.classList.add("oculto"));
    porId(destino).classList.remove("oculto");
    porId("titulo-seccion").textContent = TITULOS[destino];
    document.title = `${TITULOS[destino]} · Plataforma RAG`;
    porId("periodo").classList.toggle("oculto", destino !== "resumen");
    cerrarMenu();
    window.scrollTo({ top: 0, behavior: "smooth" });
    if (destino === "usuarios") await cargarUsuarios();
    if (destino === "documentos") await cargarDocumentos();
    if (destino === "alertas") await cargarAlertas();
    if (destino === "auditoria") await cargarAuditoria();
  });
});

function cerrarMenu() { porId("rail").classList.remove("abierto"); porId("velo").classList.remove("visible"); }
porId("abrir-menu").addEventListener("click", () => {
  porId("rail").classList.add("abierto");
  porId("velo").classList.add("visible");
});
porId("velo").addEventListener("click", cerrarMenu);
porId("alternar-tema").addEventListener("click", () => {
  const actual = document.documentElement.dataset.tema;
  const oscuro = actual === "oscuro"
    || (actual === "" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  aplicarTema(oscuro ? "claro" : "oscuro");
});

porId("actualizar").addEventListener("click", async () => {
  const activa = document.querySelector(".navegacion.activo").dataset.seccion;
  await comprobarSalud();
  if (activa === "resumen") await cargarResumen();
  if (activa === "usuarios") await cargarUsuarios();
  if (activa === "documentos") await cargarDocumentos();
  if (activa === "alertas") await cargarAlertas();
  if (activa === "auditoria") await cargarAuditoria();
});

/* ---------- 8. Estado del sistema ---------- */
async function comprobarSalud() {
  const pulso = porId("pulso");
  try {
    const salud = await fetch("/health").then((r) => r.json());
    const bien = salud.status === "ok";
    pulso.className = `pulso ${bien ? "" : "caido"}`;
    pulso.textContent = bien ? "Sistema operativo" : "Supabase no responde";
    porId("ficha-modelos").replaceChildren(
      ...[
        ["Respuestas", salud.generation_model],
        ["Embeddings", salud.embedding_model],
        ["Dimensiones", "768"],
        ["Entorno", salud.environment],
      ].map(([nombre, valor]) => {
        const fila = document.createElement("div");
        fila.append(crear("dt", "", nombre), crear("dd", "", texto(valor)));
        return fila;
      }),
    );
  } catch (_) {
    pulso.className = "pulso caido";
    pulso.textContent = "API inalcanzable";
  }
}

/* ---------- 9. Resumen ---------- */
porId("periodo").addEventListener("change", cargarResumen);
porId("filtro-preguntas").addEventListener("input", pintarPreguntas);

async function cargarResumen() {
  esqueletoFilas(porId("tabla-preguntas"), 7);
  porId("indicadores").replaceChildren(...Array.from({ length: 6 }, () => {
    const caja = crear("article", "tarjeta indicador");
    caja.append(crear("div", "esqueleto"), crear("div", "esqueleto alto"));
    return caja;
  }));
  try {
    const datos = await solicitar(`/admin/overview?days=${porId("periodo").value}`);
    pintarIndicadores(datos.kpis);
    pintarTiempos(datos.timing, datos.kpis);
    pintarGrafico(datos.daily || []);
    pintarRecurrentes(datos.recurrent_questions || []);
    preguntas = datos.recent_questions || [];
    pintarPreguntas();
  } catch (error) {
    avisar(error.message, "error");
    filaVacia(porId("tabla-preguntas"), 7, "No se pudo cargar la actividad", error.message);
  }
}

function pintarIndicadores(k) {
  const valores = [
    ["Preguntas", numero(k.questions), "en el periodo"],
    ["Resueltas", `${k.answer_rate}%`, "con contexto encontrado"],
    ["Demora media", ms(k.average_latency_ms), "de pregunta a respuesta"],
    ["Usuarios", numero(k.users), "registrados"],
    ["Documentos", numero(k.documents), "activos"],
    ["Alertas", numero(k.open_alerts), "sin resolver"],
  ];
  const contenedor = porId("indicadores");
  contenedor.replaceChildren();
  valores.forEach(([nombre, valor, pista], indice) => {
    const destacar = indice === 5 && Number(k.open_alerts) > 0;
    const caja = crear("article", `tarjeta indicador${destacar ? " destacado" : ""}`);
    caja.append(crear("small", "", nombre), crear("strong", "", valor), crear("span", "pista", pista));
    contenedor.append(caja);
  });
  const contador = porId("contador-alertas");
  contador.textContent = numero(k.open_alerts);
  contador.classList.toggle("cero", !Number(k.open_alerts));
}

/** Barra apilada: preparacion -> busqueda -> generacion, en orden cronologico. */
function pintarTiempos(timing, kpis) {
  const t = timing || {};
  const total = Number(t.total_p50) || 0;
  porId("tiempo-total").textContent = total ? ms(total) : "—";
  porId("tiempo-p95").textContent = kpis && kpis.p95_latency_ms ? ms(kpis.p95_latency_ms) : "—";

  const partes = [
    { nombre: "Preparación", clase: "seg-preparacion", valor: Number(t.other_p50) || 0,
      nota: "validar la sesión, leer la conversación y guardar" },
    { nombre: "Búsqueda", clase: "seg-busqueda", valor: Number(t.retrieval_p50) || 0,
      nota: "embedding de la pregunta y búsqueda vectorial" },
    { nombre: "Generación", clase: "seg-generacion", valor: Number(t.generation_p50) || 0,
      nota: "Gemini redactando la respuesta" },
  ];

  const pila = porId("pila-tiempos");
  const leyenda = porId("leyenda-tiempos");
  pila.replaceChildren();
  leyenda.replaceChildren();

  if (!total) {
    pila.style.display = "none";
    bloqueVacio(leyenda, "⏱️", "Sin mediciones todavía",
      "El desglose aparece cuando haya preguntas respondidas en el periodo.");
    porId("nota-tiempos").textContent = "";
    return;
  }
  pila.style.display = "";

  partes.forEach((parte) => {
    const porcentaje = Math.max(0, (parte.valor / total) * 100);
    const segmento = crear("div", parte.clase);
    segmento.style.width = `${porcentaje}%`;
    segmento.title = `${parte.nombre}: ${ms(parte.valor)} (${porcentaje.toFixed(0)}%)`;
    // Etiqueta directa dentro del segmento: es el apoyo que exige la paleta
    // cuando el contraste sobre el fondo queda por debajo de 3:1.
    if (porcentaje >= 12) segmento.textContent = ms(parte.valor);
    pila.append(segmento);

    const entrada = crear("span");
    const punto = crear("i");
    punto.style.background = `var(--serie-${parte.clase.replace("seg-", "")})`;
    entrada.append(punto, document.createTextNode(`${parte.nombre} `), crear("b", "", ms(parte.valor)));
    leyenda.append(entrada);
  });

  const mayor = partes.reduce((a, b) => (b.valor > a.valor ? b : a));
  porId("nota-tiempos").textContent =
    `Lo que más pesa es ${mayor.nombre.toLowerCase()}: ${mayor.nota}.`;
}

function pintarGrafico(diario) {
  const grafico = porId("grafico");
  const marco = grafico.parentElement;
  const vacio = porId("grafico-vacio");
  const total = diario.reduce((suma, dia) => suma + dia.questions, 0);
  porId("total-periodo").textContent = `${numero(total)} preguntas`;

  if (!diario.length) {
    marco.classList.add("oculto");
    vacio.classList.remove("oculto");
    return;
  }
  marco.classList.remove("oculto");
  vacio.classList.add("oculto");

  const maximo = Math.max(1, ...diario.map((d) => d.questions));
  porId("eje-y").replaceChildren(
    ...[maximo, Math.round(maximo / 2), 0].map((v) => crear("span", "", numero(v))),
  );
  grafico.replaceChildren();
  diario.forEach((dia) => {
    const barra = crear("div", "barra-dia");
    barra.style.height = `${Math.max(2, (dia.questions / maximo) * 100)}%`;
    barra.dataset.etiqueta =
      `${fechaCorta(dia.date)} · ${numero(dia.questions)} preguntas · ${ms(dia.average_latency_ms)}`;
    grafico.append(barra);
  });
  porId("eje-x").replaceChildren(
    crear("span", "", fechaCorta(diario[0].date)),
    crear("span", "", fechaCorta(diario[diario.length - 1].date)),
  );
}

function pintarRecurrentes(lista) {
  const contenedor = porId("recurrentes");
  if (!lista.length) {
    bloqueVacio(contenedor, "💬", "Sin patrones todavía",
      "Cuando haya más consultas verás aquí las preguntas que más se repiten.");
    return;
  }
  contenedor.replaceChildren();
  lista.forEach((item, indice) => {
    const fila = crear("div", "fila-lista");
    fila.append(
      crear("span", "puesto", `${indice + 1}`),
      crear("span", "texto", item.question || "—"),
      crear("span", "conteo", `${item.count}×`),
    );
    contenedor.append(fila);
  });
}

function pintarPreguntas() {
  const filtro = porId("filtro-preguntas").value.trim().toLowerCase();
  const cuerpo = porId("tabla-preguntas");
  const filas = filtro
    ? preguntas.filter((p) => String(p.question || "").toLowerCase().includes(filtro))
    : preguntas;

  if (!filas.length) {
    filaVacia(cuerpo, 7,
      filtro ? "Ninguna pregunta coincide" : "Sin preguntas en el periodo",
      filtro ? "Prueba con otras palabras." : "Los estudiantes aún no han consultado al asistente.");
    return;
  }
  cuerpo.replaceChildren();
  filas.forEach((item) => {
    const fila = document.createElement("tr");
    const estado = document.createElement("td");
    estado.append(crear("span", `etiqueta ${item.status}`, ESTADOS[item.status] || item.status));
    fila.append(
      crear("td", "recorte", texto(item.question)),
      estado,
      crear("td", "num", ms(item.latency_ms)),
      crear("td", "num", item.retrieval_ms != null ? ms(item.retrieval_ms) : "—"),
      crear("td", "num", item.generation_ms != null ? ms(item.generation_ms) : "—"),
      crear("td", "num", item.top_similarity ? Number(item.top_similarity).toFixed(3) : "—"),
      crear("td", "num", fecha(item.created_at)),
    );
    cuerpo.append(fila);
  });
}

/* ---------- 10. Usuarios ---------- */
let usuarios = [];

porId("ventana-activos").addEventListener("change", () => cargarUsuarios());
porId("filtro-usuarios").addEventListener("input", pintarUsuarios);

async function cargarUsuarios(silencioso = false) {
  const minutos = porId("ventana-activos").value;
  const cuerpo = porId("tabla-usuarios");
  if (!silencioso) esqueletoFilas(cuerpo, 6, 5);
  try {
    usuarios = await solicitar(`/admin/users?minutes=${minutos}`);
    const activos = usuarios.filter((u) => u.activo).length;
    const contador = porId("contador-activos");
    contador.textContent = numero(activos);
    contador.classList.toggle("cero", !activos);
    if (!silencioso) pintarUsuarios();
  } catch (error) {
    if (!silencioso) filaVacia(cuerpo, 6, "No se pudo cargar la lista de usuarios", error.message);
  }
}

function pintarUsuarios() {
  const filtro = porId("filtro-usuarios").value.trim().toLowerCase();
  const cuerpo = porId("tabla-usuarios");
  const filas = filtro
    ? usuarios.filter((u) =>
        `${u.full_name || ""} ${u.email || ""}`.toLowerCase().includes(filtro))
    : usuarios;

  if (!filas.length) {
    filaVacia(cuerpo, 6,
      filtro ? "Ningún usuario coincide" : "Todavía no hay usuarios",
      filtro ? "Prueba con otro nombre o correo." : "Aparecerán aquí en cuanto alguien se registre.");
    return;
  }

  cuerpo.replaceChildren();
  filas.forEach((u) => {
    const fila = document.createElement("tr");

    const identidad = document.createElement("td");
    const caja = document.createElement("div");
    caja.style.display = "flex";
    caja.style.alignItems = "center";
    caja.style.gap = "9px";
    const punto = crear("span", `punto-actividad${u.activo ? " vivo" : ""}`);
    punto.title = u.activo ? "Preguntó algo hace poco" : "Sin actividad reciente";
    const nombres = document.createElement("div");
    nombres.append(
      crear("strong", "", texto(u.full_name, u.email || "Sin nombre")),
      crear("small", "sutil", texto(u.email, "")),
    );
    caja.append(punto, nombres);
    identidad.append(caja);

    // Rol y estado comparten celda: dos columnas separadas dejaban sin sitio
    // a los botones de accion.
    const cuenta = document.createElement("td");
    const chips = crear("div", "chips-cuenta");
    chips.append(
      crear("span", `etiqueta ${u.role === "admin" ? "info" : "active"}`,
        u.role === "admin" ? "Administrador" : "Estudiante"),
    );
    if (!u.is_active) chips.append(crear("span", "etiqueta error", "Desactivada"));
    cuenta.append(chips);

    const votos = document.createElement("td");
    votos.className = "num";
    if (u.votos_positivos || u.votos_negativos) {
      votos.textContent = `${u.votos_positivos} 👍  ${u.votos_negativos} 👎`;
    } else {
      votos.textContent = "—";
    }

    const acciones = crear("td", "celda-acciones");
    acciones.append(botonContrasena(u), botonRol(u), botonEstado(u));

    // Las dos fechas comparten celda: por separado la tabla no cabia y
    // recortaba los botones de accion.
    const actividad = crear("td", "num");
    if (u.ultima_pregunta || u.last_sign_in_at) {
      actividad.append(
        crear("span", "", u.ultima_pregunta ? `Preguntó ${fecha(u.ultima_pregunta)}` : "Nunca preguntó"),
        crear("small", "sutil", u.last_sign_in_at ? `Ingresó ${fecha(u.last_sign_in_at)}` : "Sin sesiones"),
      );
    } else {
      actividad.textContent = "—";
    }

    fila.append(
      identidad, cuenta,
      crear("td", "num", numero(u.preguntas)),
      votos,
      actividad,
      acciones,
    );
    cuerpo.append(fila);
  });
}

function botonContrasena(u) {
  const boton = crear("button", "fantasma", "Contraseña");
  boton.addEventListener("click", () => abrirContrasena(u));
  return boton;
}

/** Dos caminos: el seguro primero. */
function abrirContrasena(u) {
  const quien = u.full_name || u.email;
  abrirModal("Restablecer contraseña", quien, (cuerpo) => {
    const enlace = crear("div", "opcion-modal");
    enlace.append(
      crear("h3", "", "Enviar un enlace de restablecimiento"),
      crear("p", "", "El estudiante abre el enlace y elige su propia contraseña. "
        + "Tú nunca la conoces, así que no puedes suplantarlo. Es la opción recomendada."),
    );
    const botonEnlace = crear("button", "", "Generar enlace");
    botonEnlace.type = "button";
    botonEnlace.addEventListener("click", () => ejecutarContrasena(
      botonEnlace, `/admin/users/${u.id}/reset-link`, enlace,
      (datos) => [
        cajaSecreta(datos.action_link),
        crear("p", "apoyo", "Cópialo y hazlo llegar al estudiante. Caduca en unas horas y solo sirve una vez."),
      ],
    ));
    enlace.append(botonEnlace);

    const temporal = crear("div", "opcion-modal");
    temporal.append(
      crear("h3", "", "Generar una contraseña temporal"),
      crear("p", "", "Para cuando el estudiante no puede entrar a su correo. "
        + "Se muestra una sola vez y no queda guardada; entrégasela y pídele que la cambie desde la app."),
    );
    const botonTemporal = crear("button", "secundario", "Generar contraseña");
    botonTemporal.type = "button";
    botonTemporal.addEventListener("click", () => ejecutarContrasena(
      botonTemporal, `/admin/users/${u.id}/temporary-password`, temporal,
      (datos) => [
        cajaSecreta(datos.password),
        crear("p", "apoyo", "Anótala ahora: al cerrar esta ventana no se puede recuperar."),
      ],
    ));
    temporal.append(botonTemporal);

    cuerpo.append(enlace, temporal);
    cuerpo.append(crear("p", "apoyo",
      "Las dos acciones quedan registradas en Auditoría con tu nombre."));
  });
}

async function ejecutarContrasena(boton, ruta, contenedor, construir) {
  const original = boton.textContent;
  boton.disabled = true;
  boton.textContent = "Generando...";
  try {
    const datos = await solicitar(ruta, { method: "POST" });
    boton.remove();
    construir(datos).forEach((nodo) => contenedor.append(nodo));
  } catch (error) {
    avisar(error.message, "error");
    boton.disabled = false;
    boton.textContent = original;
  }
}

function botonRol(u) {
  const admin = u.role === "admin";
  const boton = crear("button", "fantasma", admin ? "Quitar admin" : "Hacer admin");
  boton.addEventListener("click", () =>
    cambiarUsuario(u, { role: admin ? "user" : "admin" },
      admin ? `${u.full_name || u.email} ya no es administrador.`
            : `${u.full_name || u.email} ahora es administrador.`));
  return boton;
}

function botonEstado(u) {
  const boton = crear("button", "fantasma", u.is_active ? "Desactivar" : "Reactivar");
  boton.addEventListener("click", () =>
    cambiarUsuario(u, { is_active: !u.is_active },
      u.is_active ? "Cuenta desactivada. No podrá preguntar."
                  : "Cuenta reactivada."));
  return boton;
}

async function cambiarUsuario(u, cambios, mensaje) {
  try {
    await solicitar(`/admin/users/${u.id}`, {
      method: "PATCH", body: JSON.stringify(cambios),
    });
    avisar(mensaje, "exito");
    await cargarUsuarios();
  } catch (error) {
    avisar(error.message, "error");
  }
}

/* ---------- 11. Documentos ---------- */
const zona = porId("zona");
const campoArchivo = porId("archivo");

["dragenter", "dragover"].forEach((e) =>
  zona.addEventListener(e, (ev) => { ev.preventDefault(); zona.classList.add("encima"); }));
["dragleave", "drop"].forEach((e) =>
  zona.addEventListener(e, (ev) => { ev.preventDefault(); zona.classList.remove("encima"); }));
zona.addEventListener("drop", (ev) => {
  const archivo = ev.dataTransfer?.files?.[0];
  if (!archivo) return;
  const dt = new DataTransfer();
  dt.items.add(archivo);
  campoArchivo.files = dt.files;
  campoArchivo.dispatchEvent(new Event("change"));
});

campoArchivo.addEventListener("change", () => {
  const archivo = campoArchivo.files[0];
  const etiqueta = porId("texto-archivo");
  const boton = porId("boton-carga");
  if (!archivo) {
    etiqueta.textContent = "Arrastra el archivo o haz clic para elegirlo";
    boton.disabled = true;
    return;
  }
  etiqueta.textContent = `${archivo.name} · ${(archivo.size / 1024 / 1024).toFixed(2)} MB`;
  boton.disabled = false;
  porId("progreso-carga").className = "mensaje";
  porId("progreso-carga").textContent = "Archivo listo para cargar.";
});

porId("formulario-carga").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const archivo = campoArchivo.files[0];
  if (!archivo) return;
  const boton = porId("boton-carga");
  const barra = porId("barra-progreso");
  const estado = porId("progreso-carga");
  boton.disabled = true;
  barra.classList.remove("oculto", "determinado");
  barra.firstElementChild.style.width = "";
  estado.className = "mensaje";
  estado.textContent = "Validando el archivo...";

  const cuerpo = new FormData();
  cuerpo.append("file", archivo);
  try {
    const trabajo = await solicitar("/admin/documents/upload", { method: "POST", body: cuerpo });
    campoArchivo.value = "";
    porId("texto-archivo").textContent = "Arrastra el archivo o haz clic para elegirlo";
    await seguirCarga(trabajo);
  } catch (error) {
    estado.className = "mensaje error";
    estado.textContent = error.message;
    barra.classList.add("oculto");
    avisar(error.message, "error");
  } finally {
    boton.disabled = false;
  }
});

async function seguirCarga(trabajo) {
  const barra = porId("barra-progreso");
  const relleno = barra.firstElementChild;
  const estado = porId("progreso-carga");
  const total = Number(trabajo.chunks_total) || 0;
  if (total > 0) barra.classList.add("determinado");
  estado.textContent = `Generando ${numero(total)} embeddings...`;

  for (let intento = 0; intento < 600; intento += 1) {
    await new Promise((listo) => setTimeout(listo, intento < 5 ? 800 : 2000));
    let job;
    try {
      job = await solicitar(`/admin/jobs/${trabajo.job_id}`);
    } catch (error) {
      estado.className = "mensaje error";
      estado.textContent = `No se pudo consultar el progreso: ${error.message}`;
      return;
    }
    const hechos = Number(job.chunks_processed) || 0;
    if (total > 0) relleno.style.width = `${Math.min(100, Math.round((hechos / total) * 100))}%`;

    if (job.status === "completed") {
      relleno.style.width = "100%";
      estado.className = "mensaje exito";
      estado.textContent = `Listo: ${numero(hechos)} de ${numero(total)} chunks almacenados.`;
      avisar(`${job.filename} cargado correctamente.`, "exito");
      await cargarDocumentos();
      setTimeout(() => barra.classList.add("oculto"), 1200);
      return;
    }
    if (job.status === "failed") {
      estado.className = "mensaje error";
      estado.textContent = job.error_message || "La carga falló.";
      avisar("La carga falló. Revisa las alertas.", "error");
      barra.classList.add("oculto");
      await cargarAlertas();
      return;
    }
    estado.textContent =
      `Generando embeddings: ${numero(hechos)} de ${numero(total)} chunks. No cierres esta página.`;
  }
  estado.className = "mensaje";
  estado.textContent = "La carga sigue en curso. Vuelve a esta sección en unos minutos.";
}

porId("actualizar-documentos").addEventListener("click", cargarDocumentos);

async function cargarDocumentos() {
  const cuerpo = porId("tabla-documentos");
  esqueletoFilas(cuerpo, 4, 3);
  try {
    const datos = await solicitar("/admin/documents");
    if (!datos.length) {
      filaVacia(cuerpo, 4, "Sin documentos cargados",
        "Sube un archivo .chunks.jsonl para que el asistente tenga qué responder.");
      return;
    }
    cuerpo.replaceChildren();
    datos.forEach((item) => {
      const fila = document.createElement("tr");
      const estado = document.createElement("td");
      estado.append(crear("span", `etiqueta ${item.status}`, ESTADOS[item.status] || item.status));
      fila.append(
        crear("td", "", texto(item.filename)),
        estado,
        crear("td", "num", numero(item.chunk_count)),
        crear("td", "num", fecha(item.created_at)),
      );
      cuerpo.append(fila);
    });
  } catch (error) {
    filaVacia(cuerpo, 4, "No se pudieron cargar los documentos", error.message);
  }
}

/* ---------- 12. Laboratorio ---------- */
let conversacionPrueba = null;
let historialPruebas = [];

document.querySelectorAll(".ejemplo").forEach((boton) =>
  boton.addEventListener("click", () => {
    porId("pregunta").value = boton.dataset.pregunta;
    porId("pregunta").focus();
  }));

porId("mantener-chat").addEventListener("change", async (evento) => {
  if (!evento.target.checked) {
    conversacionPrueba = null;
    porId("estado-chat").textContent = "";
    return;
  }
  try {
    conversacionPrueba = await solicitar("/chat/conversations", {
      method: "POST",
      body: JSON.stringify({ title: `Prueba del panel · ${new Date().toLocaleString("es-PE")}` }),
    });
    pintarEstadoChat();
  } catch (error) {
    evento.target.checked = false;
    avisar(error.message, "error");
  }
});

function pintarEstadoChat() {
  if (!conversacionPrueba) return;
  const usados = conversacionPrueba.message_count || 0;
  porId("estado-chat").textContent =
    `Conversación activa · ${usados}/${conversacionPrueba.max_messages} mensajes. `
    + `Las preguntas siguientes recuerdan a las anteriores.`;
}

porId("limpiar-historial").addEventListener("click", () => {
  historialPruebas = [];
  pintarHistorial();
});

porId("ver-crudo").addEventListener("click", () => {
  const caja = porId("texto-respuesta");
  const boton = porId("ver-crudo");
  if (boton.dataset.modo === "crudo") {
    renderizarMarkdown(crudo, caja);
    caja.style.whiteSpace = "";
    boton.textContent = "Ver texto crudo";
    boton.dataset.modo = "";
  } else {
    caja.replaceChildren(document.createTextNode(crudo));
    caja.style.whiteSpace = "pre-wrap";
    boton.textContent = "Ver formateado";
    boton.dataset.modo = "crudo";
  }
});

porId("formulario-prueba").addEventListener("submit", async (evento) => {
  evento.preventDefault();
  const pregunta = porId("pregunta").value.trim();
  if (!pregunta) return;
  const boton = porId("boton-probar");
  const estado = porId("estado-prueba");
  boton.disabled = true;
  boton.textContent = "Consultando...";
  estado.className = "mensaje";
  estado.textContent = "Buscando en los documentos y redactando la respuesta...";
  porId("resultado").classList.add("oculto");

  const inicio = performance.now();
  try {
    const cuerpo = { question: pregunta };
    if (conversacionPrueba) cuerpo.conversation_id = conversacionPrueba.id;
    const datos = await solicitar("/chat/ask", {
      method: "POST", body: JSON.stringify(cuerpo),
    });
    const total = Math.round(performance.now() - inicio);
    mostrarRespuesta(datos, total);

    if (conversacionPrueba) {
      conversacionPrueba.message_count = (conversacionPrueba.message_count || 0) + 1;
      pintarEstadoChat();
    }
    historialPruebas.unshift({
      pregunta, respuesta: datos, total, cuando: new Date(),
    });
    historialPruebas = historialPruebas.slice(0, 15);
    pintarHistorial();

    estado.className = "mensaje exito";
    estado.textContent = "Prueba completada.";
    // El desglose de tiempos solo esta en la fila guardada, no en /chat/ask.
    cargarDesglose(datos.question_id);
  } catch (error) {
    estado.className = "mensaje error";
    estado.textContent = error.message;
    avisar(error.message, "error");
  } finally {
    boton.disabled = false;
    boton.textContent = "Consultar al RAG";
  }
});

function mostrarRespuesta(datos, total) {
  crudo = datos.answer || "";
  porId("ver-crudo").dataset.modo = "";
  porId("ver-crudo").textContent = "Ver texto crudo";
  porId("texto-respuesta").style.whiteSpace = "";
  renderizarMarkdown(crudo, porId("texto-respuesta"));

  const sinFuentes = !datos.sources.length;
  porId("metricas").replaceChildren(
    crear("span", "metrica", `${ms(datos.latency_ms)} en la API`),
    crear("span", "metrica", `${ms(total)} extremo a extremo`),
    crear("span", "metrica", texto(datos.model)),
    crear("span", `metrica${sinFuentes ? " aviso" : ""}`,
      `${datos.sources.length} ${datos.sources.length === 1 ? "fuente" : "fuentes"}`),
  );

  const fuentes = porId("fuentes");
  if (sinFuentes) {
    bloqueVacio(fuentes, "🔍", "No se recuperó contexto",
      "Ninguna sección superó el umbral de similitud. Revisa si el documento está cargado o baja RETRIEVAL_THRESHOLD.");
  } else {
    fuentes.replaceChildren();
    datos.sources.forEach((f) => {
      const caja = crear("div", "fuente pulsable");
      const fin = f.page_end ?? f.page_start;
      const paginas = f.page_start
        ? (fin === f.page_start ? `página ${f.page_start}` : `páginas ${f.page_start}–${fin}`)
        : "sin paginación";
      caja.append(
        crear("strong", "", texto(f.title)),
        crear("span", "", `${texto(f.document)} · ${paginas} · similitud ${Number(f.similarity).toFixed(3)}`),
      );
      const medidor = crear("div", "medidor");
      const relleno = document.createElement("div");
      relleno.style.width = `${Math.min(100, Math.max(0, f.similarity * 100))}%`;
      medidor.append(relleno);
      caja.append(medidor);
      caja.addEventListener("click", () => verFragmento(f));
      fuentes.append(caja);
    });
  }
  porId("resultado").classList.remove("oculto");
}

/** El texto literal que recibió el modelo: separa un fallo de búsqueda de uno de redacción. */
async function verFragmento(fuente) {
  abrirModal("Fragmento recuperado", fuente.title || "Fuente", (cuerpo) => {
    cuerpo.append(crear("p", "apoyo", "Cargando el texto..."));
  });
  try {
    const chunk = await solicitar(`/admin/chunks/${encodeURIComponent(fuente.chunk_id)}`);
    const cuerpo = porId("modal-cuerpo");
    cuerpo.replaceChildren();
    cuerpo.append(
      crear("p", "apoyo",
        `${texto(fuente.document)} · similitud ${Number(fuente.similarity).toFixed(3)}`
        + (chunk.estimated_tokens ? ` · ~${numero(chunk.estimated_tokens)} tokens` : "")),
      crear("div", "fragmento", chunk.content || ""),
    );
  } catch (error) {
    porId("modal-cuerpo").replaceChildren(crear("p", "mensaje error", error.message));
  }
}

/** Trae retrieval_ms y generation_ms de la fila ya guardada. */
async function cargarDesglose(questionId) {
  const caja = porId("desglose-prueba");
  if (!questionId) { caja.classList.add("oculto"); return; }
  try {
    const fila = await solicitar(`/admin/questions/${questionId}`);
    const busqueda = Number(fila.retrieval_ms) || 0;
    const generacion = Number(fila.generation_ms) || 0;
    const totalApi = Number(fila.latency_ms) || 0;
    const preparacion = Math.max(0, totalApi - busqueda - generacion);
    if (!totalApi) { caja.classList.add("oculto"); return; }

    const partes = [
      ["Preparación", "seg-preparacion", preparacion],
      ["Búsqueda", "seg-busqueda", busqueda],
      ["Generación", "seg-generacion", generacion],
    ];
    const pila = porId("pila-prueba");
    const leyenda = porId("leyenda-prueba");
    pila.replaceChildren();
    leyenda.replaceChildren();
    partes.forEach(([nombre, clase, valor]) => {
      const porcentaje = Math.max(0, (valor / totalApi) * 100);
      const segmento = crear("div", clase);
      segmento.style.width = `${porcentaje}%`;
      segmento.title = `${nombre}: ${ms(valor)}`;
      if (porcentaje >= 14) segmento.textContent = ms(valor);
      pila.append(segmento);

      const entrada = crear("span");
      const punto = crear("i");
      punto.style.background = `var(--serie-${clase.replace("seg-", "")})`;
      entrada.append(punto, document.createTextNode(`${nombre} `), crear("b", "", ms(valor)));
      leyenda.append(entrada);
    });
    caja.classList.remove("oculto");
  } catch (_) {
    caja.classList.add("oculto");
  }
}

function pintarHistorial() {
  const contenedor = porId("historial-pruebas");
  if (!historialPruebas.length) {
    bloqueVacio(contenedor, "🧪", "Sin pruebas todavía",
      "Cada consulta que hagas se guarda aquí para comparar. Se pierde al recargar la página.");
    return;
  }
  contenedor.replaceChildren();
  historialPruebas.forEach((item) => {
    const fila = crear("div", "fila-historial");
    const izquierda = document.createElement("div");
    izquierda.append(
      crear("div", "texto", item.pregunta),
      crear("small", "sutil",
        `${item.cuando.toLocaleTimeString("es-PE")} · ${ms(item.respuesta.latency_ms)} · `
        + `${item.respuesta.sources.length} fuentes`),
    );
    const chip = crear("span", `etiqueta ${item.respuesta.sources.length ? "answered" : "no_results"}`,
      item.respuesta.sources.length ? "Con contexto" : "Sin contexto");
    fila.append(izquierda, chip);
    fila.addEventListener("click", () => {
      porId("pregunta").value = item.pregunta;
      mostrarRespuesta(item.respuesta, item.total);
      cargarDesglose(item.respuesta.question_id);
      porId("resultado").scrollIntoView({ behavior: "smooth", block: "nearest" });
    });
    contenedor.append(fila);
  });
}

pintarHistorial();

/* ---------- 13. Alertas ---------- */
porId("filtro-alertas").addEventListener("change", () => cargarAlertas());

async function cargarAlertas(silencioso = false) {
  const estado = porId("filtro-alertas").value;
  const lista = porId("lista-alertas");
  if (!silencioso) {
    lista.replaceChildren(...Array.from({ length: 3 }, () => crear("div", "esqueleto alto")));
  }
  try {
    const datos = await solicitar(`/admin/alerts?status=${estado}`);
    if (estado === "open") {
      const contador = porId("contador-alertas");
      contador.textContent = numero(datos.length);
      contador.classList.toggle("cero", !datos.length);
    }
    if (silencioso) return;
    if (!datos.length) {
      bloqueVacio(lista, "✅", "Todo en orden",
        "No hay alertas con este estado. Se crean solas ante preguntas sin contexto, respuestas lentas o fallos.");
      return;
    }
    lista.replaceChildren();
    datos.forEach((item) => {
      const caja = crear("div", `alerta ${item.severity}`);
      const contenido = document.createElement("div");
      const titulo = document.createElement("div");
      titulo.style.display = "flex";
      titulo.style.gap = "8px";
      titulo.style.alignItems = "center";
      titulo.append(
        crear("strong", "", texto(item.title)),
        crear("span", `etiqueta ${item.severity}`, SEVERIDADES[item.severity] || item.severity),
      );
      contenido.append(titulo, crear("p", "", texto(item.message)), crear("small", "", fecha(item.created_at)));
      caja.append(contenido);
      if (item.status !== "resolved") {
        const boton = crear("button", "secundario", "Resolver");
        boton.addEventListener("click", async () => {
          boton.disabled = true;
          try {
            await solicitar(`/admin/alerts/${item.id}`, {
              method: "PATCH", body: JSON.stringify({ status: "resolved" }),
            });
            avisar("Alerta resuelta.", "exito");
            await cargarAlertas();
          } catch (error) {
            avisar(error.message, "error");
            boton.disabled = false;
          }
        });
        caja.append(boton);
      } else {
        caja.append(crear("span", "etiqueta resolved", "Resuelta"));
      }
      lista.append(caja);
    });
  } catch (error) {
    if (!silencioso) bloqueVacio(lista, "⚠️", "No se pudieron cargar las alertas", error.message);
  }
}

/* ---------- 14. Auditoría ---------- */
porId("filtro-auditoria").addEventListener("input", pintarAuditoria);

async function cargarAuditoria() {
  const cuerpo = porId("tabla-auditoria");
  esqueletoFilas(cuerpo, 4);
  try {
    auditoria = await solicitar("/admin/audit?limit=200");
    pintarAuditoria();
  } catch (error) {
    filaVacia(cuerpo, 4, "No se pudo cargar la auditoría", error.message);
  }
}

function pintarAuditoria() {
  const filtro = porId("filtro-auditoria").value.trim().toLowerCase();
  const cuerpo = porId("tabla-auditoria");
  const filas = filtro
    ? auditoria.filter((i) =>
        `${i.action} ${i.entity_type} ${JSON.stringify(i.details)}`.toLowerCase().includes(filtro))
    : auditoria;
  if (!filas.length) {
    filaVacia(cuerpo, 4,
      filtro ? "Sin coincidencias" : "Sin acciones registradas",
      filtro ? "Prueba con otro término." : "Aquí aparecerán las cargas de documentos y los cambios en alertas.");
    return;
  }
  cuerpo.replaceChildren();
  filas.forEach((item) => {
    const fila = document.createElement("tr");
    fila.append(
      crear("td", "", texto(item.action)),
      crear("td", "", texto(item.entity_type)),
      crear("td", "recorte", texto(JSON.stringify(item.details ?? {}))),
      crear("td", "num", fecha(item.created_at)),
    );
    cuerpo.append(fila);
  });
}

/* ---------- 15. Sesión persistida ---------- */
if (token) {
  solicitar("/auth/me")
    .then(async (perfil) => {
      if (perfil.role !== "admin") return cerrarSesion();
      usuario = perfil;
      await mostrarAplicacion();
    })
    .catch(cerrarSesion);
}
