/** Valida la sintaxis y genera una distribución pública sin copiar secretos ni herramientas. */
import { cp, mkdir, readdir, stat } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const raiz = fileURLToPath(new URL('../', import.meta.url));
const publico = path.join(raiz, 'public');
async function validar(directorio) {
  for (const entrada of await readdir(directorio, { withFileTypes: true })) {
    const archivo = path.join(directorio, entrada.name);
    if (entrada.isSymbolicLink())
      throw new Error('No se permiten enlaces simbólicos en la distribución.');
    if (entrada.isDirectory()) await validar(archivo);
    else if (entrada.name.endsWith('.js'))
      execFileSync(process.execPath, ['--check', archivo], { stdio: 'inherit' });
  }
}
await validar(publico);
await stat(path.join(publico, 'index.html'));
await mkdir(path.join(raiz, 'dist'), { recursive: true });
await cp(publico, path.join(raiz, 'dist'), { recursive: true });
console.log('Web validada y generada en web/dist. No requiere dependencias de ejecución.');
