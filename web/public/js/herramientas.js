/** Integración opcional: reutiliza las mismas acciones y permisos de la interfaz. */
export function registrarHerramientas({ enviarPregunta, obtenerConversaciones }) {
  const contexto = document.modelContext;
  if (!contexto?.registerTool) return;
  const ciclo = new AbortController();
  window.addEventListener('pagehide', () => ciclo.abort(), { once: true });
  const herramientas = [
    {
      name: 'listar_conversaciones',
      title: 'Consultar conversaciones',
      description: 'Lee las conversaciones ya cargadas en la sesión actual.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: true, untrustedContentHint: true },
      execute: () => obtenerConversaciones(),
    },
    {
      name: 'enviar_pregunta',
      title: 'Preguntar al asistente',
      description:
        'Envía y guarda una pregunta en la conversación visible. Requiere sesión iniciada y utiliza la cuota de consultas.',
      inputSchema: {
        type: 'object',
        properties: { pregunta: { type: 'string', minLength: 3, maxLength: 2000 } },
        required: ['pregunta'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: false, untrustedContentHint: true },
      execute: (entrada) => {
        if (
          !entrada ||
          typeof entrada.pregunta !== 'string' ||
          Object.keys(entrada).some((clave) => clave !== 'pregunta')
        )
          throw new Error('Indica solamente una pregunta de texto.');
        return enviarPregunta(entrada.pregunta);
      },
    },
  ];
  for (const herramienta of herramientas) {
    try {
      Promise.resolve(contexto.registerTool(herramienta, { signal: ciclo.signal })).catch(() => {});
    } catch {
      /* La web funciona también sin la integración opcional. */
    }
  }
}
