import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		// Tailwind v4 via plugin de Vite (ADR-010): a config é o próprio app.css.
		tailwindcss(),
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// adapter-node for a standalone Node server (ADR-006).
			adapter: adapter()
		})
	],
	server: {
		// Reachable from the host when running inside a container.
		host: true,
		port: 5173,
		strictPort: true
	}
});
