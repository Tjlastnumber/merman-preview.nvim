import { build } from 'esbuild';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
await build({
  absWorkingDir: root,
  entryPoints: ['source/renderer.ts'],
  outfile: 'bin/render.mjs',
  bundle: true,
  platform: 'node',
  target: 'node20', format: 'esm',
  plugins: [{
    name: 'grid-only-opentui', setup(b) {
      b.onResolve({ filter: /^@opentui\/core$/ }, () => ({ path: path.join(root, 'source/opentui-adapter.ts') }));
    }
  }],
});
