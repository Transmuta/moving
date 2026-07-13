/// <reference types="vitest/config" />
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { svelteTesting } from '@testing-library/svelte/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
	plugins: [
		// Tailwind v4 via plugin de Vite (ADR-010): a config é o próprio app.css.
		tailwindcss(),
		// A config do SvelteKit (adapter, compilerOptions runes, CSP) vive em svelte.config.js.
		sveltekit()
	],
	server: {
		// Reachable from the host when running inside a container.
		host: true,
		port: 5173,
		strictPort: true
	},
	// Pirâmide de testes (doc 16): dois projetos Vitest.
	//  - client (jsdom): componentes Svelte — arquivos *.svelte.test.ts
	//  - server (node):  lógica de BFF e route handlers — *.test.ts em src/lib/server e src/routes
	test: {
		// Gate de cobertura (análogo ao minimum_coverage do backend). Escopo: o que a
		// pirâmide unit/integração cobre — lib (server + componentes), hooks e os route
		// handlers .ts. As páginas .svelte (SSR) são território de e2e e ficam fora.
		coverage: {
			provider: 'v8',
			reporter: ['text-summary', 'text'],
			include: ['src/lib/**', 'src/hooks.server.ts', 'src/routes/**/*.ts'],
			exclude: [
				'src/lib/index.ts',
				'src/lib/assets/**',
				'src/lib/styles/**',
				'src/**/*.d.ts',
				'src/**/*.{test,spec}.ts'
			],
			// 80 nas métricas estáveis (alinhado ao gate do backend). Branches ganha folga:
			// o v8 conta fallbacks defensivos que não rodam no ambiente de teste
			// (matchMedia, getSetCookie), inerentemente abaixo — hoje estamos em ~82%.
			thresholds: { lines: 80, functions: 80, statements: 80, branches: 75 }
		},
		projects: [
			{
				extends: './vite.config.ts',
				plugins: [svelteTesting()],
				test: {
					name: 'client',
					environment: 'jsdom',
					clearMocks: true,
					include: ['src/**/*.svelte.{test,spec}.{js,ts}'],
					exclude: ['src/lib/server/**'],
					setupFiles: ['./vitest-setup-client.ts']
				}
			},
			{
				extends: './vite.config.ts',
				test: {
					name: 'server',
					environment: 'node',
					include: ['src/**/*.{test,spec}.{js,ts}'],
					exclude: ['src/**/*.svelte.{test,spec}.{js,ts}']
				}
			}
		]
	}
});
