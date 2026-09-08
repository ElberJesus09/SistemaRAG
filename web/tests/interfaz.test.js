import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';

const html = await readFile(new URL('../public/index.html', import.meta.url), 'utf8');
const dom = new JSDOM(html, { url: 'http://localhost:8000/web/' });
const { window } = dom;
for (const nombre of ['window', 'document', 'location', 'FormData'])
  globalThis[nombre] = window[nombre];
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
window.HTMLElement.prototype.scrollIntoView = function () {};
window.HTMLDialogElement.prototype.showModal = function () {
  this.open = true;
};
window.HTMLDialogElement.prototype.close = function () {
  this.open = false;
  queueMicrotask(() => this.dispatchEvent(new window.Event('close')));
};

const porId = (id) => window.document.getElementById(id);
let conversaciones = [];
let mensajes = [];
let peticiones = [];
let fallaPregunta = false;
let resolverPregunta = null;
let nombrePerfil = 'Ana Prueba';
const json = (datos, estado = 200) => new Response(JSON.stringify(datos), { status: estado });

globalThis.fetch = async (direccion, opciones = {}) => {
  const ruta = new URL(direccion, window.location.href).pathname;
  const metodo = opciones.method || 'GET';
  const datos = opciones.body ? JSON.parse(opciones.body) : null;
  peticiones.push({ ruta, metodo, datos });
  if (ruta.endsWith('/configuracion.json')) return json({ url_api: '/api/v1' });
  if (ruta.endsWith('/auth/login'))
    return json({ access_token: 'token-prueba', refresh_token: 'renovar-prueba' });
  if (ruta.endsWith('/auth/me')) {
    if (metodo === 'PATCH') nombrePerfil = datos.full_name;
    return json({ id: 'usuario', email: 'ana@example.com', full_name: nombrePerfil, role: 'user' });
  }
  if (ruta.endsWith('/chat/conversations')) {
    if (metodo === 'POST') {
      const nueva = {
        id: 'conversacion',
        title: datos.title,
        status: 'active',
        message_count: 0,
        max_messages: 20,
      };
      conversaciones.unshift(nueva);
      return json(nueva);
    }
    return json(conversaciones);
  }
  if (ruta.endsWith('/messages')) return json(mensajes);
  if (ruta.endsWith('/chat/ask')) {
    if (fallaPregunta) return json({ detail: 'Servicio temporalmente no disponible' }, 503);
    if (resolverPregunta === 'esperar')
      return new Promise((resolver) => {
        resolverPregunta = resolver;
      });
    const respuesta = {
      question_id: 'pregunta-1',
      conversation_id: 'conversacion',
      answer: '**Documento**\n\n- Presenta tu DNI.\n- <img src=x onerror=alert(1)>',
      sources: [{ document: 'Manual.pdf', title: 'Requisitos', page_start: 3, page_end: 4 }],
    };
    mensajes.push({ id: respuesta.question_id, question: datos.question, ...respuesta });
    conversaciones[0].message_count += 1;
    return json(respuesta);
  }
  if (ruta.endsWith('/feedback')) return new Response(null, { status: 204 });
  if (ruta.endsWith('/conversations/conversacion')) {
    if (metodo === 'PATCH') {
      conversaciones[0].title = datos.title;
      return json(conversaciones[0]);
    }
    if (metodo === 'DELETE') {
      conversaciones = [];
      mensajes = [];
      return new Response(null, { status: 204 });
    }
  }
  throw new Error(`Ruta no prevista: ${metodo} ${ruta}`);
};

async function esperar(condicion) {
  for (let intento = 0; intento < 100; intento += 1) {
    if (condicion()) return;
    await new Promise((resolver) => setTimeout(resolver, 5));
  }
  assert.fail('La interfaz no alcanzó el estado esperado.');
}
function enviar(id) {
  porId(id).dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
}

await import('../public/js/aplicacion.js');

test('flujo completo de la web sobre el contrato HTTP simulado', async (t) => {
  await esperar(() => !porId('entrar').disabled);

  await t.test('acceso de usuario y estado vacío', async () => {
    porId('correo').value = 'ana@example.com';
    porId('contrasena').value = 'contraseña-de-prueba';
    enviar('formulario-acceso');
    await esperar(() => !porId('chat').hidden && !porId('entrar').disabled);
    assert.equal(porId('nombre-usuario').textContent, 'Ana Prueba');
    assert.equal(porId('administracion').hidden, true);
    assert.match(porId('mensajes').textContent, /Qué necesitas saber/);
    assert.equal(porId('contrasena').value, '');
  });

  await t.test(
    'crea conversación, pregunta y muestra Markdown y fuentes sin ejecutar HTML',
    async () => {
      porId('pregunta').value = 'Qué documentos necesito?';
      enviar('formulario-pregunta');
      await esperar(() => porId('mensajes').querySelector('.fuente') && !porId('enviar').disabled);
      assert.equal(porId('mensajes').querySelector('strong').textContent, 'Documento');
      assert.equal(porId('mensajes').querySelectorAll('li').length, 2);
      assert.equal(porId('mensajes').querySelector('img'), null);
      assert.match(porId('mensajes').textContent, /<img src=x/);
      assert.match(porId('mensajes').querySelector('.fuente').textContent, /Manual.pdf.*3–4/);
      assert.equal(porId('pregunta').value, '');
      assert.equal(peticiones.filter((p) => p.ruta.endsWith('/chat/ask')).length, 1);
    },
  );

  await t.test('guarda una valoración y renombra la conversación', async () => {
    const boton = porId('mensajes').querySelector('.valoracion button');
    boton.click();
    await esperar(() => boton.getAttribute('aria-pressed') === 'true');
    porId('renombrar').click();
    porId('cuerpo-dialogo').querySelector('input').value = 'Mis requisitos';
    enviar('formulario-dialogo');
    await esperar(() => !porId('dialogo').open);
    assert.equal(porId('titulo-conversacion').textContent, 'Mis requisitos');
  });

  await t.test('ante un error conserva la pregunta y no la reenvía automáticamente', async () => {
    fallaPregunta = true;
    const anteriores = peticiones.filter((p) => p.ruta.endsWith('/chat/ask')).length;
    porId('pregunta').value = 'Y cuánto cuesta?';
    enviar('formulario-pregunta');
    await esperar(() => !porId('enviar').disabled);
    assert.equal(porId('pregunta').value, 'Y cuánto cuesta?');
    assert.match(porId('aviso').textContent, /temporalmente/);
    assert.equal(peticiones.filter((p) => p.ruta.endsWith('/chat/ask')).length, anteriores + 1);
    fallaPregunta = false;
  });

  await t.test(
    'actualiza perfil y conserva el formulario al cambiar al diálogo de contraseña',
    async () => {
      porId('cuenta').click();
      porId('cuerpo-dialogo').querySelector('input').value = 'Ana Actualizada';
      enviar('formulario-dialogo');
      await esperar(() => !porId('dialogo').open);
      assert.equal(porId('nombre-usuario').textContent, 'Ana Actualizada');
      porId('cuenta').click();
      porId('cuerpo-dialogo').querySelector('button').click();
      await new Promise((resolver) => setTimeout(resolver, 0));
      assert.equal(porId('cuerpo-dialogo').querySelectorAll('input[type=password]').length, 3);
      porId('cancelar-dialogo').click();
      await new Promise((resolver) => setTimeout(resolver, 0));
    },
  );

  await t.test('eliminar requiere confirmar y deja el historial vacío', async () => {
    porId('eliminar').click();
    assert.equal(porId('dialogo').open, true);
    assert.equal(conversaciones.length, 1);
    enviar('formulario-dialogo');
    await esperar(() => !porId('dialogo').open);
    assert.equal(conversaciones.length, 0);
    assert.equal(porId('titulo-conversacion').textContent, 'Nueva conversación');
    assert.match(porId('conversaciones').textContent, /Aún no tienes/);
  });

  await t.test('cerrar sesión durante una consulta descarta respuestas tardías', async () => {
    resolverPregunta = 'esperar';
    porId('pregunta').value = 'Pregunta pendiente';
    enviar('formulario-pregunta');
    await esperar(() => typeof resolverPregunta === 'function');
    porId('salir').click();
    resolverPregunta(json({ question_id: 'tardia', answer: 'No debe mostrarse', sources: [] }));
    await new Promise((resolver) => setTimeout(resolver, 20));
    assert.equal(porId('chat').hidden, true);
    assert.equal(porId('mensajes').textContent.includes('No debe mostrarse'), false);
    assert.equal(porId('nombre-usuario').textContent, '');
  });
});
