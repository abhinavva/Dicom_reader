import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: __dirname,
  base: '/viewer/',
  worker: {
    format: 'es',
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(__dirname, 'index.html'),
      output: {
        entryFileNames: 'assets/viewer.bundle.js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
    target: 'es2020',
    minify: 'esbuild',
    sourcemap: false,
    assetsInlineLimit: 0,
  },
  resolve: {
    alias: {},
  },
  define: {
    'process.env.NODE_ENV': JSON.stringify('production'),
  },
});
