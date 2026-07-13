import { redirect, type RequestEvent } from '@sveltejs/kit';
import { apiFetch, SESSION_COOKIE } from '$lib/server/api';

// Sign-out via POST (auditoria doc 13, causa E): GET permitia logout forçado por CSRF
// (`<img src="/auth/sign-out">`). POST ativa a checagem de origem do SvelteKit. Invalida a
// sessão na API e apaga o cookie no domínio do web.
export async function POST(event: RequestEvent) {
	try {
		await apiFetch(event, '/api/auth/sign-out', { method: 'DELETE' });
	} catch {
		// mesmo se a API falhar, apagamos o cookie local abaixo.
	}
	event.cookies.delete(SESSION_COOKIE, { path: '/' });
	redirect(303, '/entrar');
}
