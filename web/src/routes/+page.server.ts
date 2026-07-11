import type { PageServerLoad } from './$types';
import { env } from '$env/dynamic/private';

// BFF: busca server-to-server na API Phoenix (JSON:API), pela rede do compose
// (API_URL=http://api:4000). O browser nunca fala direto com a API.
export const load: PageServerLoad = async ({ fetch }) => {
	const base = env.API_URL ?? 'http://localhost:4000';

	try {
		const res = await fetch(`${base}/api/json/pings`, {
			headers: { accept: 'application/vnd.api+json' }
		});

		if (!res.ok) {
			return { pings: [], error: `API respondeu ${res.status}`, source: base };
		}

		const body = await res.json();
		const pings = (body.data ?? []).map((d: { id: string; attributes?: { message?: string } }) => ({
			id: d.id,
			message: d.attributes?.message ?? ''
		}));

		return { pings, error: null, source: base };
	} catch (e) {
		return { pings: [], error: `Falha ao contatar a API: ${String(e)}`, source: base };
	}
};
