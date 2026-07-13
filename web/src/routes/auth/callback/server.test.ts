import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { GET } from './+server';
import { SESSION_COOKIE } from '$lib/server/api';

// redirect() do SvelteKit lança um objeto {status, location}; capturamos para inspecionar.
async function caught(fn: () => Promise<unknown>) {
	try {
		await fn();
		throw new Error('esperava um redirect, mas a função retornou normalmente');
	} catch (e) {
		return e as { status: number; location: string };
	}
}

function fakeEvent({ token, setCookie }: { token?: string; setCookie?: string }) {
	const qs = token !== undefined ? `?token=${encodeURIComponent(token)}` : '';
	const url = new URL(`http://web/auth/callback${qs}`);
	const headers: Record<string, string> = setCookie ? { 'set-cookie': setCookie } : {};
	const fetch = vi.fn().mockResolvedValue(new Response('', { headers }));
	const set = vi.fn();
	return { event: { url, fetch, cookies: { get: () => undefined, set } } as never, fetch, set };
}

describe('GET /auth/callback (magic link cai no BFF)', () => {
	it('sem token: redireciona a /entrar?erro=link e nem chama a API', async () => {
		const { event, fetch } = fakeEvent({});
		const r = await caught(() => GET(event));

		expect(r.status).toBe(303);
		expect(r.location).toBe('/entrar?erro=link');
		expect(fetch).not.toHaveBeenCalled();
	});

	it('token válido + sessão emitida: re-emite o cookie e vai para /', async () => {
		const { event, fetch, set } = fakeEvent({
			token: 'tok123',
			setCookie: `${SESSION_COOKIE}=assinado; Path=/; HttpOnly`
		});
		const r = await caught(() => GET(event));

		// chamou o callback da API com o token.
		expect(fetch.mock.calls[0][0]).toContain('/api/auth/magic-link/callback?token=tok123');
		// re-emitiu a sessão no domínio do web.
		expect(set).toHaveBeenCalledWith(SESSION_COOKIE, 'assinado', expect.any(Object));
		expect(r.status).toBe(303);
		expect(r.location).toBe('/');
	});

	it('token inválido (API não devolve sessão): volta a /entrar?erro=link', async () => {
		const { event, set } = fakeEvent({ token: 'ruim' }); // sem Set-Cookie
		const r = await caught(() => GET(event));

		expect(set).not.toHaveBeenCalled();
		expect(r.status).toBe(303);
		expect(r.location).toBe('/entrar?erro=link');
	});
});
