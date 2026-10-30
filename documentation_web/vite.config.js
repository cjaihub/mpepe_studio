import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('@firebase/auth') || id.includes('firebase/auth')) {
              return 'firebase-auth'
            }
            if (id.includes('firebase') || id.includes('@firebase')) {
              return 'firebase-firestore'
            }
            if (id.includes('react') || id.includes('scheduler')) {
              return 'react-vendor'
            }
          }
        },
      },
    },
  },
})
