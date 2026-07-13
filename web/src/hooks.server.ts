import type { Handle } from '@sveltejs/kit';

// Dark mode sem flash (doc 03 §4.4): estampa `data-theme` no <html> já no HTML servido,
// a partir do cookie `mv-theme`. Sem cookie, NÃO emite o atributo — aí o `prefers-color-scheme`
// do app.css decide. Também troca o `lang` para pt-BR (acessibilidade, §8.5).
export const handle: Handle = async ({ event, resolve }) => {
	const theme = event.cookies.get('mv-theme');
	const themeAttr = theme === 'dark' || theme === 'light' ? ` data-theme="${theme}"` : '';

	const response = await resolve(event, {
		transformPageChunk: ({ html }) =>
			html.replace('%mv-lang%', 'pt-BR').replace('%mv-theme%', themeAttr)
	});

	// Headers de segurança (auditoria doc 13, causa E). CSP fica de fora por ora — precisa de
	// uma passada cuidadosa (fontes/estilos inline do Tailwind/Svelte) verificada no browser.
	response.headers.set('X-Content-Type-Options', 'nosniff');
	response.headers.set('X-Frame-Options', 'DENY');
	response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');

	return response;
};
