import type { PageServerLoad } from './$types';
import { apiFetch } from '$lib/server/api';

// BFF: tudo server-to-server na API Phoenix, repassando o cookie de sessão (ADR-005).
// O browser nunca fala direto com a API.
export const load: PageServerLoad = async (event) => {
	const me = await loadMe(event);
	return { me };
};

async function loadMe(event: Parameters<PageServerLoad>[0]) {
	try {
		const res = await apiFetch(event, '/api/auth/me', { headers: { accept: 'application/json' } });
		if (!res.ok) return null;
		const body = await res.json();
		return body?.user ? body : null;
	} catch {
		return null;
	}
}
