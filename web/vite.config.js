import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';
import { readVersion } from './build-version.js';

const localPath = (path) => fileURLToPath(new URL(path, import.meta.url));

export default defineConfig({
  root: localPath('./'),
  plugins: [react()],
  build: {
    rolldownOptions: {
      input: {
        main: localPath('./index.html'),
        themes: localPath('./themes/index.html'),
      },
    },
  },
  define: {
    __CHROMATICLI_VERSION__: JSON.stringify(readVersion(
      new URL('../.release-please-manifest.json', import.meta.url),
      process.env.CHROMATICLI_RELEASE_TAG,
    )),
  },
  server: {
    fs: {
      allow: [localPath('./'), localPath('../themes.json'), localPath('../logo/chromaticli.svg')],
    },
  },
});
