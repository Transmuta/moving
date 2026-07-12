import { redirect, type RequestEvent } from '@sveltejs/kit';
import { apiFetch, reemitSession } from '$lib/server/api';

// Entrada do OAuth Google (ADR-015), proxiada pelo BFF (ADR-005). A API monta a URL de
// autorização do Google e guarda o `state` na sessão; re-emitimos esse cookie no domínio
// do web e mandamos o browser ao Google. Assim o `state` (e depois a sessão) vivem no web.
export async function GET(event: RequestEvent) {
	const res = await apiFetch(event, '/api/auth/strategy/user/google', { redirect: 'manual' });
	reemitSession(event, res);

	const location = res.headers.get('location');
	if (!location) redirect(303, '/entrar?erro=google');

	redirect(302, location);
}
