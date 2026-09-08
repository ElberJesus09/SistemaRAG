import test from 'node:test';
import assert from 'node:assert/strict';
import { ClienteApi, normalizarUrlApi } from '../public/js/cliente_api.js';

const json = (datos, estado = 200) =>
  new Response(JSON.stringify(datos), {
    status: estado,
    headers: { 'Content-Type': 'application/json' },
  });

test('normaliza rutas locales y dominios sin aceptar credenciales ni esquemas inseguros', () => {
  assert.equal(normalizarUrlApi('/api/v1/'), '/api/v1');
  assert.equal(
    normalizarUrlApi('https://api.example.com/api/v1/'),
    'https://api.example.com/api/v1',
  );
  for (const valor of [
    '//otro.example',
    'javascript:alert(1)',
    'https://usuario:clave@api.example.com',
    null,
    '/api?token=algo',
  ])
    assert.throws(() => normalizarUrlApi(valor));
});

test('pregunta con el contrato real y Bearer, sin cookies', async () => {
  const api = new ClienteApi('/api/v1', {
    transporte: async (url, opciones) => {
      assert.equal(url, '/api/v1/chat/ask');
      assert.equal(opciones.headers.Authorization, 'Bearer acceso');
      assert.equal(opciones.credentials, 'omit');
      assert.deepEqual(JSON.parse(opciones.body), {
        question: 'Pregunta real',
        conversation_id: 'conversacion',
      });
      return json({ answer: 'Respuesta' });
    },
  });
  api.guardarSesion({ access_token: 'acceso' });
  assert.equal((await api.preguntar('Pregunta real', 'conversacion')).answer, 'Respuesta');
});

test('no envía tokens en login ni registro', async () => {
  const api = new ClienteApi('/api/v1', {
    transporte: async (_url, opciones) => {
      assert.equal(opciones.headers.Authorization, undefined);
      return json({ requires_email_confirmation: true });
    },
  });
  api.guardarSesion({ access_token: 'anterior' });
  await api.acceder({ email: 'alumno@example.com', password: 'solo-prueba' }, true);
});

test('renueva una sola vez cuando dos solicitudes reciben 401', async () => {
  let renovaciones = 0;
  const api = new ClienteApi('/api/v1', {
    transporte: async (url, opciones) => {
      if (url.endsWith('/auth/refresh')) {
        renovaciones += 1;
        await new Promise((resolver) => setTimeout(resolver, 10));
        return json({ access_token: 'nuevo', refresh_token: 'renovado' });
      }
      return opciones.headers.Authorization === 'Bearer nuevo'
        ? json({ ok: true })
        : json({ detail: 'Vencida' }, 401);
    },
  });
  api.guardarSesion({ access_token: 'viejo', refresh_token: 'renovar' });
  const resultados = await Promise.all([api.perfil(), api.conversaciones()]);
  assert.equal(renovaciones, 1);
  assert.ok(resultados.every((resultado) => resultado.ok));
});

test('cierra la sesión cuando la renovación es rechazada', async () => {
  let vencida = false;
  const api = new ClienteApi('/api/v1', {
    alVencer: () => {
      vencida = true;
    },
    transporte: async () => json({ detail: 'Sesión vencida' }, 401),
  });
  api.guardarSesion({ access_token: 'viejo', refresh_token: 'inválido' });
  await assert.rejects(api.perfil(), { estado: 401 });
  assert.equal(vencida, true);
});

test('no reenvía preguntas ante errores 429 o 503', async () => {
  for (const codigo of [429, 503]) {
    let llamadas = 0;
    const api = new ClienteApi('/api/v1', {
      transporte: async () => {
        llamadas += 1;
        return json({ detail: 'Intenta más tarde' }, codigo);
      },
    });
    await assert.rejects(api.preguntar('Pregunta', null), {
      estado: codigo,
      message: 'Intenta más tarde',
    });
    assert.equal(llamadas, 1);
  }
});

test('interpreta eliminación 204 y errores de validación', async () => {
  const api = new ClienteApi('/api/v1', {
    transporte: async () => new Response(null, { status: 204 }),
  });
  assert.equal(await api.eliminar('id'), null);
  api.transporte = async () => json({ detail: [{ msg: 'Invalid' }] }, 422);
  await assert.rejects(api.acceder({}), /Revisa los datos/);
});

test('informa errores de red y respuestas que no son JSON', async () => {
  const api = new ClienteApi('/api/v1', {
    transporte: async () => {
      throw new TypeError('fetch failed');
    },
  });
  await assert.rejects(api.perfil(), /No se pudo conectar/);
  api.transporte = async () => new Response('<html>Error del proxy</html>', { status: 502 });
  await assert.rejects(api.perfil(), { estado: 502 });
});

test('cancela una solicitud al agotar el tiempo', async () => {
  const api = new ClienteApi('/api/v1', {
    transporte: (_url, { signal }) =>
      new Promise((_resolver, rechazar) =>
        signal.addEventListener('abort', () => rechazar(new Error('abort'))),
      ),
  });
  await assert.rejects(api.solicitar('/auth/me', { espera: 5 }), /tardando demasiado/);
});

test('cerrar sesión impide que una renovación tardía restaure el token', async () => {
  let resolverRenovacion;
  let avisarRenovacion;
  const iniciada = new Promise((resolver) => {
    avisarRenovacion = resolver;
  });
  const api = new ClienteApi('/api/v1', {
    transporte: async (url) => {
      if (url.endsWith('/auth/refresh')) {
        avisarRenovacion();
        return new Promise((resolver) => {
          resolverRenovacion = resolver;
        });
      }
      return json({ detail: 'Vencida' }, 401);
    },
  });
  api.guardarSesion({ access_token: 'viejo', refresh_token: 'renovar' });
  const pendiente = api.perfil();
  await iniciada;
  api.cerrarSesion();
  resolverRenovacion(json({ access_token: 'nuevo' }));
  await assert.rejects(pendiente, /sesión se cerró/);
  api.transporte = async (_url, opciones) => {
    assert.equal(opciones.headers.Authorization, undefined);
    return json({ ok: true });
  };
  await api.perfil();
});
