import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	compilerOptions: {
		// Runes forçadas no projeto (exceto libs em node_modules). Removível no Svelte 6.
		runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true)
	},
	kit: {
		// Servidor Node standalone (ADR-006).
		adapter: adapter(),

		// Content-Security-Policy (auditoria doc 13, causa E). `mode: 'auto'` faz o SvelteKit
		// injetar nonce nos seus próprios scripts inline (hidratação), então `script-src 'self'`
		// não os bloqueia. `style-src` permite inline por causa do `style="display:contents"` do
		// app.html e dos estilos que o Svelte insere — risco baixo de XSS via style.
		csp: {
			mode: 'auto',
			directives: {
				'default-src': ['self'],
				'script-src': ['self'],
				'style-src': ['self', 'unsafe-inline'],
				'img-src': ['self', 'data:'],
				'font-src': ['self'],
				'connect-src': ['self'],
				'base-uri': ['self'],
				'form-action': ['self'],
				'frame-ancestors': ['none'],
				'object-src': ['none']
			}
		}
	}
};

export default config;
