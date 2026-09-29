import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { viteSingleFile } from 'vite-plugin-singlefile'

export default defineConfig({
  plugins: [vue(), viteSingleFile()],
  build: {
    target: 'es2015',
    cssCodeSplit: false,
    assetsInlineLimit: 100000000,
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
} as any)
