import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { GET } from './+server';
import { SESSION_COOKIE } from '$lib/server/api';

async function caught(fn: () => Promise<unknown>) {
	try {
		await fn();
		throw new Error('esperava um redirect');
	} catch (e) {
		return e as { status: number; location: string };
	}
}

function fakeEvent(fetchImpl?: ReturnType<typeof vi.fn>) {
	const fetch = fetchImpl ?? vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
	const del = vi.fn();
	return {
		event: { fetch, cookies: { get: () => 'sessao-atual', delete: del } } as never,
		fetch,
		del
	};
}

describe('GET /auth/sign-out', () => {
	it('invalida na API (DELETE), apaga o cookie local e vai para /entrar', async () => {
		const { event, fetch, del } = fakeEvent();
		const r = await caught(() => GET(event));

		const [url, init] = fetch.mock.calls[0];
		expect(url).toContain('/api/auth/sign-out');
		expect(init.method).toBe('DELETE');
		expect(del).toHaveBeenCalledWith(SESSION_COOKIE, { path: '/' });
		expect(r.status).toBe(303);
		expect(r.location).toBe('/entrar');
	});

	it('mesmo se a API falhar, apaga o cookie e redireciona', async () => {
		const failing = vi.fn().mockRejectedValue(new Error('down'));
		const { event, del } = fakeEvent(failing);
		const r = await caught(() => GET(event));

		expect(del).toHaveBeenCalledWith(SESSION_COOKIE, { path: '/' });
		expect(r.location).toBe('/entrar');
	});
});
