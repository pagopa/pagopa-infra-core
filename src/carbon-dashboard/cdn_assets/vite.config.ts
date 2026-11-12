import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Relative base: the bundle must work from any path on Storage/Front Door
  // without knowing its public prefix at build time.
  base: './',
  server: {
    host: '0.0.0.0',
    port: 5173,
    watch: { usePolling: true },
  },
});
