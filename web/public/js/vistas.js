/** Construcción segura de contenido. El texto de usuarios y modelos nunca se interpreta como HTML. */
export const porId = (id) => document.getElementById(id);

export function crear(etiqueta, clase = '', texto) {
  const nodo = document.createElement(etiqueta);
  nodo.className = clase;
  if (texto !== undefined) nodo.textContent = String(texto);
  return nodo;
}

export function agregarNegritas(texto, destino) {
  for (const parte of texto.split(/(\*\*[^*]+\*\*)/g)) {
    destino.append(
      parte.startsWith('**') && parte.endsWith('**') && parte.length > 4
        ? crear('strong', '', parte.slice(2, -2))
        : document.createTextNode(parte),
    );
  }
}

export function renderizarMarkdown(texto, destino) {
  let parrafo = [];
  let lista = null;
  const cerrarParrafo = () => {
    if (!parrafo.length) return;
    const nodo = crear('p');
    agregarNegritas(parrafo.join(' '), nodo);
    destino.append(nodo);
    parrafo = [];
  };
  for (const linea of String(texto || '')
    .split('\n')
    .map((parte) => parte.trim())) {
    if (!linea) {
      cerrarParrafo();
      lista = null;
      continue;
    }
    const coincidencia = linea.match(/^(-|\d+\.)\s+(.*)$/);
    if (coincidencia) {
      cerrarParrafo();
      const etiqueta = coincidencia[1] === '-' ? 'ul' : 'ol';
      if (!lista || lista.tagName.toLowerCase() !== etiqueta) {
        lista = crear(etiqueta);
        if (etiqueta === 'ol') lista.start = parseInt(coincidencia[1], 10);
        destino.append(lista);
      }
      const elemento = crear('li');
      agregarNegritas(coincidencia[2], elemento);
      lista.append(elemento);
    } else {
      lista = null;
      parrafo.push(linea);
    }
  }
  cerrarParrafo();
}

export function pintarBienvenida(destino) {
  const bloque = crear('div', 'bienvenida');
  bloque.append(
    crear('span', 'sello', 'R'),
    crear('span', 'sobretexto', 'PREGUNTA. CONSULTA. COMPRUEBA.'),
    crear('h2', '', '¿Qué necesitas saber?'),
    crear(
      'p',
      '',
      'Escribe una pregunta concreta. Encontraremos la información en los documentos de la institución.',
    ),
  );
  destino.replaceChildren(bloque);
}

export function pintarIntercambio(mensaje, destino, alValorar) {
  const pregunta = crear('article', 'mensaje usuario', mensaje.question);
  pregunta.setAttribute('aria-label', 'Tu pregunta');
  const respuesta = crear('article', 'mensaje asistente');
  respuesta.append(crear('div', 'autor', 'RAG · ASISTENTE'));
  const texto = crear('div', 'respuesta');
  renderizarMarkdown(
    mensaje.answer ||
      (mensaje.status === 'error'
        ? 'No fue posible generar esta respuesta. Puedes intentarlo nuevamente.'
        : 'Todavía no hay una respuesta disponible. Actualiza la conversación en unos instantes.'),
    texto,
  );
  respuesta.append(texto);
  if (mensaje.sources?.length) {
    const fuentes = crear('div', 'fuentes');
    fuentes.setAttribute('aria-label', 'Fuentes de la respuesta');
    for (const fuente of mensaje.sources) {
      const ficha = crear('div', 'fuente', fuente.document);
      const paginas = fuente.page_start
        ? ` · Pág. ${fuente.page_start}${fuente.page_end && fuente.page_end !== fuente.page_start ? `–${fuente.page_end}` : ''}`
        : '';
      ficha.append(crear('small', '', `${fuente.title || 'Documento'}${paginas}`));
      fuentes.append(ficha);
    }
    respuesta.append(fuentes);
  }
  if (mensaje.answer && mensaje.id) {
    const valoracion = crear('div', 'valoracion');
    valoracion.append(crear('span', '', '¿Te ayudó?'));
    for (const [valor, titulo] of [
      [1, 'Sí'],
      [-1, 'No'],
    ]) {
      const boton = crear('button', '', titulo);
      boton.type = 'button';
      boton.setAttribute('aria-pressed', 'false');
      boton.addEventListener('click', async () => {
        const botones = [...valoracion.querySelectorAll('button')];
        botones.forEach((elemento) => {
          elemento.disabled = true;
        });
        try {
          const guardada = await alValorar(mensaje.id, valor);
          if (guardada)
            botones.forEach((elemento) =>
              elemento.setAttribute('aria-pressed', String(elemento === boton)),
            );
        } finally {
          botones.forEach((elemento) => {
            elemento.disabled = false;
          });
        }
      });
      valoracion.append(boton);
    }
    respuesta.append(valoracion);
  }
  destino.append(pregunta, respuesta);
}
