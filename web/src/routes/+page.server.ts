import type { PageServerLoad } from './$types';
import { apiFetch } from '$lib/server/api';

// BFF: tudo server-to-server na API Phoenix, repassando o cookie de sessão (ADR-005).
// O browser nunca fala direto com a API.
export const load: PageServerLoad = async (event) => {
	const me = await loadMe(event);
	const pings = await loadPings(event);
	return { me, ...pings };
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

async function loadPings(event: Parameters<PageServerLoad>[0]) {
	try {
		const res = await apiFetch(event, '/api/json/pings', {
			headers: { accept: 'application/vnd.api+json' }
		});
		if (!res.ok) return { pings: [], error: `API respondeu ${res.status}` };
		const body = await res.json();
		const pings = (body.data ?? []).map((d: { id: string; attributes?: { message?: string } }) => ({
			id: d.id,
			message: d.attributes?.message ?? ''
		}));
		return { pings, error: null };
	} catch (e) {
		return { pings: [], error: `Falha ao contatar a API: ${String(e)}` };
	}
}
