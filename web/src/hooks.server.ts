import type { Handle } from '@sveltejs/kit';

// Dark mode sem flash (doc 03 §4.4): estampa `data-theme` no <html> já no HTML servido,
// a partir do cookie `mv-theme`. Sem cookie, NÃO emite o atributo — aí o `prefers-color-scheme`
// do app.css decide. Também troca o `lang` para pt-BR (acessibilidade, §8.5).
export const handle: Handle = async ({ event, resolve }) => {
	const theme = event.cookies.get('mv-theme');
	const themeAttr = theme === 'dark' || theme === 'light' ? ` data-theme="${theme}"` : '';

	return resolve(event, {
		transformPageChunk: ({ html }) =>
			html.replace('%mv-lang%', 'pt-BR').replace('%mv-theme%', themeAttr)
	});
};
