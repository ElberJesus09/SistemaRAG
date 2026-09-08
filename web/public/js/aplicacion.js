import { ClienteApi } from './cliente_api.js';
import { crear, porId, pintarBienvenida, pintarIntercambio } from './vistas.js';
import { registrarHerramientas } from './herramientas.js';

let api;
const estado = {
  usuario: null,
  conversaciones: [],
  actual: null,
  ocupado: false,
  registro: false,
  generacion: 0,
};
let accionDialogo = null;
let guardandoDialogo = false;

function avisar(mensaje, error = false) {
  porId('aviso').textContent = mensaje;
  porId('aviso').className = error ? 'aviso error' : 'aviso';
  porId('aviso').hidden = !mensaje;
}

function cerrarMenu() {
  porId('lateral').classList.remove('abierto');
  porId('menu').setAttribute('aria-expanded', 'false');
  actualizarAccesoMenu();
}

function actualizarAccesoMenu() {
  porId('lateral').inert =
    matchMedia('(max-width: 850px)').matches && !porId('lateral').classList.contains('abierto');
}

function actualizarControles() {
  const deshabilitado = estado.ocupado || !estado.usuario;
  for (const id of ['nueva', 'actualizar', 'renombrar', 'eliminar', 'cuenta'])
    porId(id).disabled = deshabilitado;
  porId('enviar').disabled =
    deshabilitado ||
    estado.actual?.status === 'closed' ||
    (estado.actual && estado.actual.message_count >= estado.actual.max_messages);
  porId('pregunta').disabled = porId('enviar').disabled;
  porId('enviar').textContent = estado.ocupado ? 'Esperando…' : 'Enviar ↑';
  porId('mensajes').setAttribute('aria-busy', String(estado.ocupado));
  for (const boton of porId('conversaciones').querySelectorAll('button'))
    boton.disabled = deshabilitado;
  porId('titulo-conversacion').textContent = estado.actual?.title || 'Nueva conversación';
  const cerrada =
    estado.actual?.status === 'closed' ||
    (estado.actual && estado.actual.message_count >= estado.actual.max_messages);
  porId('detalle-conversacion').textContent = cerrada
    ? 'Esta conversación terminó. Inicia una nueva para continuar.'
    : estado.actual
      ? `${estado.actual.message_count} de ${estado.actual.max_messages} consultas utilizadas`
      : 'Pregunta sobre los documentos disponibles.';
  porId('renombrar').hidden = !estado.actual;
  porId('eliminar').hidden = !estado.actual;
}

function pintarHistorial() {
  const lista = porId('conversaciones');
  lista.replaceChildren();
  if (!estado.conversaciones.length)
    lista.append(
      crear(
        'p',
        'ayuda-lateral',
        estado.usuario
          ? 'Aún no tienes conversaciones. Empieza con tu primera pregunta.'
          : 'Inicia sesión para ver tu historial.',
      ),
    );
  for (const conversacion of estado.conversaciones) {
    const boton = crear('button', '', conversacion.title || 'Sin título');
    boton.type = 'button';
    boton.setAttribute('aria-current', String(conversacion.id === estado.actual?.id));
    boton.append(
      crear(
        'small',
        '',
        `${conversacion.message_count} consultas${conversacion.status === 'closed' ? ' · Cerrada' : ''}`,
      ),
    );
    boton.addEventListener('click', () => abrirConversacion(conversacion));
    lista.append(boton);
  }
  actualizarControles();
}

function pintarUsuario() {
  const usuario = estado.usuario;
  porId('acceso').hidden = Boolean(usuario);
  porId('chat').hidden = !usuario;
  porId('cuenta').hidden = !usuario;
  porId('salir').hidden = !usuario;
  porId('administracion').hidden = usuario?.role !== 'admin';
  porId('nombre-usuario').textContent = usuario?.full_name || usuario?.email || '';
  porId('iniciales').textContent = (usuario?.full_name || usuario?.email || 'U')
    .slice(0, 1)
    .toUpperCase();
  actualizarControles();
}

function nuevaConversacion() {
  if (estado.ocupado) return;
  estado.actual = null;
  porId('pregunta').value = '';
  porId('contador').textContent = '0 / 2000';
  pintarBienvenida(porId('mensajes'));
  pintarHistorial();
  cerrarMenu();
  porId('pregunta').focus();
}

function cerrarSesion(vencida = false) {
  api?.cerrarSesion();
  estado.generacion += 1;
  Object.assign(estado, { usuario: null, conversaciones: [], actual: null, ocupado: false });
  guardandoDialogo = false;
  porId('dialogo').close();
  porId('cuerpo-dialogo').replaceChildren();
  porId('pregunta').value = '';
  porId('contrasena').value = '';
  pintarBienvenida(porId('mensajes'));
  pintarHistorial();
  pintarUsuario();
  cerrarMenu();
  avisar(
    vencida ? 'Tu sesión venció. Inicia sesión nuevamente.' : 'Has cerrado la sesión.',
    vencida,
  );
  porId('correo').focus();
}

async function cargarHistorial() {
  const generacion = estado.generacion;
  const conversaciones = await api.conversaciones();
  if (generacion !== estado.generacion) return;
  estado.conversaciones = conversaciones;
  if (estado.actual)
    estado.actual = conversaciones.find((item) => item.id === estado.actual.id) || estado.actual;
  pintarHistorial();
}

async function valorar(id, valor) {
  const generacion = estado.generacion;
  try {
    await api.valorar(id, valor);
    if (generacion !== estado.generacion) return false;
    avisar('Gracias. Tu valoración quedó guardada.');
    return true;
  } catch (error) {
    if (generacion === estado.generacion) avisar(error.message, true);
    return false;
  }
}

function pintarMensajes(mensajes) {
  const destino = porId('mensajes');
  destino.replaceChildren();
  if (!mensajes.length) pintarBienvenida(destino);
  for (const mensaje of mensajes) pintarIntercambio(mensaje, destino, valorar);
  destino.scrollTop = destino.scrollHeight;
}

async function abrirConversacion(conversacion) {
  if (estado.ocupado) return;
  const generacion = estado.generacion;
  estado.ocupado = true;
  actualizarControles();
  avisar('');
  try {
    const mensajes = await api.mensajes(conversacion.id);
    if (generacion !== estado.generacion) return;
    estado.actual = conversacion;
    porId('pregunta').value = '';
    porId('contador').textContent = '0 / 2000';
    pintarMensajes(mensajes);
    pintarHistorial();
    cerrarMenu();
  } catch (error) {
    if (generacion === estado.generacion) avisar(error.message, true);
  } finally {
    if (generacion === estado.generacion) {
      estado.ocupado = false;
      actualizarControles();
    }
  }
}

async function enviarPregunta(texto) {
  if (!estado.usuario) throw new Error('Inicia sesión antes de preguntar.');
  if (estado.ocupado) throw new Error('Espera a que termine la consulta actual.');
  const pregunta = String(texto).trim().replace(/\s+/g, ' ');
  if (pregunta.length < 3 || pregunta.length > 2000)
    throw new Error('Escribe entre 3 y 2000 caracteres.');
  if (
    estado.actual?.status === 'closed' ||
    (estado.actual && estado.actual.message_count >= estado.actual.max_messages)
  )
    throw new Error('Esta conversación terminó. Crea una nueva.');
  const generacion = estado.generacion;
  estado.ocupado = true;
  actualizarControles();
  avisar('');
  const esperando = crear('p', 'cargando', 'Consultando los documentos…');
  porId('mensajes').append(esperando);
  esperando.scrollIntoView({ block: 'nearest' });
  try {
    // Se crea primero para conservar el identificador incluso si /ask agota el tiempo.
    if (!estado.actual) {
      const nueva = await api.crearConversacion(pregunta.slice(0, 120));
      if (generacion !== estado.generacion) throw new Error('La sesión se cerró.');
      estado.actual = nueva;
      estado.conversaciones.unshift(nueva);
      pintarHistorial();
    }
    const resultado = await api.preguntar(pregunta, estado.actual.id);
    if (generacion !== estado.generacion) throw new Error('La sesión se cerró.');
    porId('mensajes').querySelector('.bienvenida')?.remove();
    pintarIntercambio(
      {
        id: resultado.question_id,
        question: pregunta,
        answer: resultado.answer,
        sources: resultado.sources,
      },
      porId('mensajes'),
      valorar,
    );
    porId('pregunta').value = '';
    porId('contador').textContent = '0 / 2000';
    estado.actual.message_count += 1;
    try {
      await cargarHistorial();
    } catch {
      avisar('La respuesta se recibió, pero no se pudo actualizar el historial. Pulsa actualizar.');
    }
    return {
      conversation_id: resultado.conversation_id,
      answer: resultado.answer,
      sources: resultado.sources,
    };
  } finally {
    esperando.remove();
    if (generacion === estado.generacion) {
      estado.ocupado = false;
      actualizarControles();
      porId('mensajes').scrollTop = porId('mensajes').scrollHeight;
      porId('pregunta').focus();
    }
  }
}

function cambiarModoAcceso() {
  estado.registro = !estado.registro;
  porId('campo-nombre').hidden = !estado.registro;
  porId('nombre').required = estado.registro;
  porId('contrasena').autocomplete = estado.registro ? 'new-password' : 'current-password';
  porId('titulo-acceso').textContent = estado.registro ? 'Crea tu cuenta' : 'Inicia sesión';
  porId('descripcion-acceso').textContent = estado.registro
    ? 'Guarda tus consultas y retómalas cuando quieras.'
    : 'Accede a tus consultas y conversaciones.';
  porId('entrar').textContent = estado.registro ? 'Crear cuenta' : 'Iniciar sesión';
  porId('texto-alternar').textContent = estado.registro
    ? '¿Ya tienes una cuenta?'
    : '¿Aún no tienes cuenta?';
  porId('alternar').textContent = estado.registro ? 'Inicia sesión' : 'Regístrate';
  avisar('');
}

function abrirDialogo(titulo, construir, accion, confirmar = 'Guardar') {
  porId('titulo-dialogo').textContent = titulo;
  porId('cuerpo-dialogo').replaceChildren();
  porId('error-dialogo').hidden = true;
  porId('confirmar-dialogo').textContent = confirmar;
  porId('confirmar-dialogo').disabled = false;
  accionDialogo = accion;
  construir(porId('cuerpo-dialogo'));
  if (!porId('dialogo').open) porId('dialogo').showModal();
}

function campoFormulario(destino, nombre, titulo, valor = '', tipo = 'text', minimo = 2) {
  const etiqueta = crear('label', '', titulo);
  const entrada = crear('input');
  Object.assign(entrada, {
    name: nombre,
    value: valor,
    type: tipo,
    required: true,
    minLength: minimo,
    maxLength: tipo === 'password' ? 128 : 120,
  });
  if (tipo === 'password')
    entrada.autocomplete = nombre === 'actual' ? 'current-password' : 'new-password';
  etiqueta.append(entrada);
  destino.append(etiqueta);
}

porId('formulario-acceso').addEventListener('submit', async (evento) => {
  evento.preventDefault();
  if (!api || porId('entrar').disabled) return;
  porId('entrar').disabled = true;
  porId('alternar').disabled = true;
  porId('entrar').textContent = 'Verificando…';
  avisar('');
  try {
    const datos = { email: porId('correo').value.trim(), password: porId('contrasena').value };
    if (estado.registro) datos.full_name = porId('nombre').value.trim();
    const sesion = await api.acceder(datos, estado.registro);
    if (sesion.requires_email_confirmation) {
      if (estado.registro) cambiarModoAcceso();
      avisar(
        'Tu cuenta fue creada. Revisa tu correo y confirma la dirección antes de iniciar sesión.',
      );
      return;
    }
    api.guardarSesion(sesion);
    estado.usuario = await api.perfil();
    estado.generacion += 1;
    pintarUsuario();
    nuevaConversacion();
    try {
      await cargarHistorial();
    } catch (error) {
      avisar(error.message, true);
    }
  } catch (error) {
    api.cerrarSesion();
    avisar(error.message, true);
  } finally {
    porId('contrasena').value = '';
    porId('entrar').disabled = false;
    porId('alternar').disabled = false;
    porId('entrar').textContent = estado.registro ? 'Crear cuenta' : 'Iniciar sesión';
  }
});

porId('alternar').addEventListener('click', cambiarModoAcceso);
porId('salir').addEventListener('click', () => cerrarSesion());
porId('nueva').addEventListener('click', () => {
  avisar('');
  nuevaConversacion();
});
porId('menu').addEventListener('click', () => {
  const abierto = porId('lateral').classList.toggle('abierto');
  porId('menu').setAttribute('aria-expanded', String(abierto));
  actualizarAccesoMenu();
});
matchMedia('(max-width: 850px)').addEventListener('change', actualizarAccesoMenu);
document.addEventListener('keydown', (evento) => {
  if (evento.key === 'Escape') cerrarMenu();
});
porId('contenido').addEventListener('click', (evento) => {
  if (!evento.target.closest('#menu')) cerrarMenu();
});
porId('pregunta').addEventListener('input', () => {
  porId('contador').textContent = `${porId('pregunta').value.length} / 2000`;
});
porId('pregunta').addEventListener('keydown', (evento) => {
  if (evento.key === 'Enter' && !evento.shiftKey && !evento.isComposing) {
    evento.preventDefault();
    if (!porId('enviar').disabled) porId('formulario-pregunta').requestSubmit();
  }
});
porId('formulario-pregunta').addEventListener('submit', async (evento) => {
  evento.preventDefault();
  const generacion = estado.generacion;
  try {
    await enviarPregunta(porId('pregunta').value);
  } catch (error) {
    if (generacion === estado.generacion) avisar(error.message, true);
  }
});
porId('actualizar').addEventListener('click', async () => {
  if (estado.ocupado) return;
  const generacion = estado.generacion;
  estado.ocupado = true;
  actualizarControles();
  try {
    await cargarHistorial();
    if (generacion !== estado.generacion) return;
    if (estado.actual) {
      const mensajes = await api.mensajes(estado.actual.id);
      if (generacion !== estado.generacion) return;
      pintarMensajes(mensajes);
    }
    avisar('Historial actualizado.');
  } catch (error) {
    if (generacion === estado.generacion) avisar(error.message, true);
  } finally {
    if (generacion === estado.generacion) {
      estado.ocupado = false;
      actualizarControles();
    }
  }
});

porId('renombrar').addEventListener('click', () => {
  const id = estado.actual.id;
  abrirDialogo(
    'Renombrar conversación',
    (destino) => campoFormulario(destino, 'titulo', 'Título', estado.actual.title || '', 'text', 1),
    async (datos) => {
      const titulo = String(datos.get('titulo')).trim();
      if (!titulo) throw new Error('Escribe un título.');
      estado.actual = await api.renombrar(id, titulo);
      await cargarHistorial();
      actualizarControles();
    },
  );
});
porId('eliminar').addEventListener('click', () => {
  const id = estado.actual.id;
  abrirDialogo(
    'Eliminar conversación',
    (destino) =>
      destino.append(
        crear(
          'p',
          '',
          `Se quitará «${estado.actual.title || 'Sin título'}» de tu historial. Esta acción no se puede deshacer. Las preguntas se conservan en la auditoría de la institución.`,
        ),
      ),
    async () => {
      await api.eliminar(id);
      estado.conversaciones = estado.conversaciones.filter((item) => item.id !== id);
      nuevaConversacion();
      avisar('Conversación eliminada del historial.');
    },
    'Eliminar',
  );
});

function abrirCambioContrasena() {
  abrirDialogo(
    'Cambiar contraseña',
    (destino) => {
      campoFormulario(destino, 'actual', 'Contraseña actual', '', 'password', 8);
      campoFormulario(destino, 'nueva', 'Nueva contraseña', '', 'password', 8);
      campoFormulario(destino, 'repetida', 'Repite la nueva contraseña', '', 'password', 8);
    },
    async (datos) => {
      if (datos.get('nueva') !== datos.get('repetida'))
        throw new Error('Las contraseñas nuevas no coinciden.');
      if (datos.get('nueva') === datos.get('actual'))
        throw new Error('Elige una contraseña distinta a la actual.');
      await api.cambiarContrasena({
        current_password: datos.get('actual'),
        new_password: datos.get('nueva'),
      });
      cerrarSesion();
      avisar('Contraseña actualizada. Inicia sesión con tu nueva contraseña.');
    },
    'Cambiar contraseña',
  );
}
porId('cuenta').addEventListener('click', () => {
  cerrarMenu();
  abrirDialogo(
    'Mi cuenta',
    (destino) => {
      destino.append(crear('p', 'secundario', estado.usuario.email));
      campoFormulario(destino, 'nombre', 'Nombre completo', estado.usuario.full_name || '');
      const cambiar = crear('button', 'enlace', 'Cambiar contraseña');
      cambiar.type = 'button';
      cambiar.addEventListener('click', abrirCambioContrasena);
      destino.append(cambiar);
    },
    async (datos) => {
      const nombre = String(datos.get('nombre')).trim();
      if (nombre.length < 2) throw new Error('Escribe un nombre de al menos dos caracteres.');
      estado.usuario = await api.actualizarPerfil(nombre);
      pintarUsuario();
      avisar('Perfil actualizado.');
    },
  );
});
for (const id of ['cerrar-dialogo', 'cancelar-dialogo'])
  porId(id).addEventListener('click', () => {
    if (!guardandoDialogo) porId('dialogo').close();
  });
porId('dialogo').addEventListener('cancel', (evento) => {
  if (guardandoDialogo) evento.preventDefault();
});
porId('dialogo').addEventListener('close', () => {
  if (!porId('dialogo').open) porId('cuerpo-dialogo').replaceChildren();
});
porId('formulario-dialogo').addEventListener('submit', async (evento) => {
  evento.preventDefault();
  if (guardandoDialogo || !accionDialogo) return;
  const generacion = estado.generacion;
  guardandoDialogo = true;
  porId('confirmar-dialogo').disabled = true;
  porId('error-dialogo').hidden = true;
  try {
    await accionDialogo(new FormData(evento.currentTarget));
    porId('dialogo').close();
  } catch (error) {
    if (generacion === estado.generacion) {
      porId('error-dialogo').textContent = error.message;
      porId('error-dialogo').hidden = false;
    }
  } finally {
    guardandoDialogo = false;
    porId('confirmar-dialogo').disabled = false;
  }
});

async function iniciar() {
  actualizarAccesoMenu();
  try {
    const respuesta = await fetch(new URL('../configuracion.json', import.meta.url), {
      cache: 'no-store',
      signal: AbortSignal.timeout(10000),
    });
    if (!respuesta.ok) throw new Error('No se pudo cargar la configuración de la web.');
    const configuracion = await respuesta.json();
    api = new ClienteApi(configuracion.url_api, { alVencer: () => cerrarSesion(true) });
    porId('administracion').href = new URL('/admin', new URL(api.url, location.href)).href;
    porId('entrar').disabled = false;
    porId('entrar').textContent = 'Iniciar sesión';
    registrarHerramientas({
      enviarPregunta,
      obtenerConversaciones: () =>
        estado.conversaciones.map(({ id, title, status }) => ({ id, title, status })),
    });
  } catch (error) {
    porId('entrar').textContent = 'Conexión no disponible';
    avisar(`${error.message} Recarga la página para volver a intentarlo.`, true);
  }
}
iniciar();
