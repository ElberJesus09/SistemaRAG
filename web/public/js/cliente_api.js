/** Contrato HTTP compartido por todas las vistas. Las claves del servidor nunca llegan aquí. */
export class ErrorApi extends Error {
  constructor(mensaje, estado = 0) {
    super(mensaje);
    this.name = 'ErrorApi';
    this.estado = estado;
  }
}

export function normalizarUrlApi(valor) {
  if (typeof valor !== 'string') throw new ErrorApi('Falta configurar la dirección de la API.');
  const url = valor.trim().replace(/\/+$/, '');
  if (/^\/(?!\/)[\w/-]+$/.test(url)) return url;
  try {
    const absoluta = new URL(url);
    if (
      !['http:', 'https:'].includes(absoluta.protocol) ||
      absoluta.username ||
      absoluta.password ||
      absoluta.search ||
      absoluta.hash
    )
      throw new Error();
    return absoluta.href.replace(/\/+$/, '');
  } catch {
    throw new ErrorApi('La dirección de la API debe ser una ruta local o una URL HTTP(S).');
  }
}

export class ClienteApi {
  #sesion = null;
  #renovacion = null;
  #generacion = 0;
  #peticiones = new Set();

  constructor(
    urlApi,
    { transporte = globalThis.fetch.bind(globalThis), alVencer = () => {} } = {},
  ) {
    this.url = normalizarUrlApi(urlApi);
    this.transporte = transporte;
    this.alVencer = alVencer;
  }

  guardarSesion(sesion) {
    if (!sesion?.access_token) throw new ErrorApi('No se recibió una sesión válida.');
    // Sólo memoria: al cerrar o recargar la página se eliminan los tokens.
    this.#sesion = { access_token: sesion.access_token, refresh_token: sesion.refresh_token };
  }

  cerrarSesion() {
    this.#generacion += 1;
    this.#sesion = null;
    this.#renovacion = null;
    for (const controlador of this.#peticiones) controlador.abort();
    this.#peticiones.clear();
  }

  async #enviar(ruta, { metodo = 'GET', datos, publico = false, espera = 20000 } = {}) {
    const controlador = new AbortController();
    this.#peticiones.add(controlador);
    const temporizador = setTimeout(() => controlador.abort('tiempo'), espera);
    const cabeceras = { Accept: 'application/json' };
    if (datos !== undefined) cabeceras['Content-Type'] = 'application/json';
    if (!publico && this.#sesion) cabeceras.Authorization = `Bearer ${this.#sesion.access_token}`;
    try {
      const respuesta = await this.transporte(`${this.url}${ruta}`, {
        method: metodo,
        headers: cabeceras,
        body: datos === undefined ? undefined : JSON.stringify(datos),
        signal: controlador.signal,
        cache: 'no-store',
        credentials: 'omit',
        redirect: 'error',
      });
      let cuerpo = null;
      if (respuesta.status !== 204) {
        try {
          cuerpo = await respuesta.json();
        } catch {
          /* Algunos proxies responden HTML. */
        }
      }
      if (!respuesta.ok) {
        let detalle =
          typeof cuerpo?.detail === 'string'
            ? cuerpo.detail
            : `No se pudo completar la solicitud (${respuesta.status}).`;
        if (Array.isArray(cuerpo?.detail))
          detalle = 'Revisa los datos del formulario y vuelve a intentarlo.';
        if (respuesta.status === 429 && typeof cuerpo?.detail !== 'string')
          detalle = 'Has alcanzado el límite de solicitudes. Espera unos minutos.';
        throw new ErrorApi(detalle, respuesta.status);
      }
      if (respuesta.status !== 204 && cuerpo === null)
        throw new ErrorApi('El servidor devolvió una respuesta no válida.');
      return cuerpo;
    } catch (error) {
      if (error instanceof ErrorApi) throw error;
      if (controlador.signal.aborted) {
        throw new ErrorApi(
          controlador.signal.reason === 'tiempo'
            ? 'El servidor está tardando demasiado. Actualiza la conversación antes de reenviar tu pregunta.'
            : 'La solicitud fue cancelada.',
        );
      }
      throw new ErrorApi(
        'No se pudo conectar con la API. Comprueba la conexión e inténtalo nuevamente.',
      );
    } finally {
      clearTimeout(temporizador);
      this.#peticiones.delete(controlador);
    }
  }

  async #renovar() {
    if (this.#renovacion) return this.#renovacion;
    const generacion = this.#generacion;
    const refresh_token = this.#sesion?.refresh_token;
    if (!refresh_token) throw new ErrorApi('La sesión venció. Vuelve a iniciar sesión.', 401);
    const pendiente = this.#enviar('/auth/refresh', {
      metodo: 'POST',
      datos: { refresh_token },
      publico: true,
    }).then((sesion) => {
      if (generacion !== this.#generacion) throw new ErrorApi('La sesión se cerró.', 401);
      this.guardarSesion(sesion);
    });
    this.#renovacion = pendiente;
    try {
      await pendiente;
    } finally {
      if (this.#renovacion === pendiente) this.#renovacion = null;
    }
  }

  async solicitar(ruta, opciones = {}) {
    const generacion = this.#generacion;
    const tokenInicial = this.#sesion?.access_token;
    try {
      return await this.#enviar(ruta, opciones);
    } catch (error) {
      if (error.estado !== 401 || opciones.publico || generacion !== this.#generacion) throw error;
      try {
        // Una petición concurrente puede haber renovado el token mientras ésta terminaba.
        if (tokenInicial === this.#sesion?.access_token) await this.#renovar();
        return await this.#enviar(ruta, opciones);
      } catch (errorRenovacion) {
        if (errorRenovacion.estado === 401 && generacion === this.#generacion) {
          this.cerrarSesion();
          this.alVencer();
        }
        throw errorRenovacion;
      }
    }
  }

  acceder(datos, registro = false) {
    return this.solicitar(registro ? '/auth/register' : '/auth/login', {
      metodo: 'POST',
      datos,
      publico: true,
    });
  }
  perfil() {
    return this.solicitar('/auth/me');
  }
  actualizarPerfil(full_name) {
    return this.solicitar('/auth/me', { metodo: 'PATCH', datos: { full_name } });
  }
  cambiarContrasena(datos) {
    return this.solicitar('/auth/password', { metodo: 'POST', datos });
  }
  conversaciones() {
    return this.solicitar('/chat/conversations?limit=200');
  }
  mensajes(id) {
    return this.solicitar(`/chat/conversations/${encodeURIComponent(id)}/messages`);
  }
  crearConversacion(title) {
    return this.solicitar('/chat/conversations', { metodo: 'POST', datos: { title } });
  }
  renombrar(id, title) {
    return this.solicitar(`/chat/conversations/${encodeURIComponent(id)}`, {
      metodo: 'PATCH',
      datos: { title },
    });
  }
  eliminar(id) {
    return this.solicitar(`/chat/conversations/${encodeURIComponent(id)}`, { metodo: 'DELETE' });
  }
  preguntar(question, conversation_id) {
    return this.solicitar('/chat/ask', {
      metodo: 'POST',
      datos: { question, conversation_id },
      espera: 90000,
    });
  }
  valorar(id, rating) {
    return this.solicitar(`/chat/questions/${encodeURIComponent(id)}/feedback`, {
      metodo: 'POST',
      datos: { rating },
    });
  }
}
