import { redirect, type RequestEvent } from '@sveltejs/kit';
import { apiBase, reemitSession } from '$lib/server/api';

// Callback do magic link (ADR-005/015): o link do e-mail cai AQUI (no web), não na API.
// O BFF valida o token via API, captura o cookie de sessão e o re-emite no domínio do web.
export async function GET(event: RequestEvent) {
	const token = event.url.searchParams.get('token');
	if (!token) redirect(303, '/entrar?erro=link');

	const res = await event.fetch(
		`${apiBase()}/api/auth/magic-link/callback?token=${encodeURIComponent(token)}`,
		{ redirect: 'manual' }
	);

	if (!reemitSession(event, res)) redirect(303, '/entrar?erro=link');

	redirect(303, '/');
}
