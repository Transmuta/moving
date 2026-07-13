import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { GET } from './+server';

async function caught(fn: () => Promise<unknown>) {
	try {
		await fn();
		throw new Error('esperava um redirect');
	} catch (e) {
		return e as { status: number; location: string };
	}
}

function fakeEvent(location: string | null) {
	const headers: Record<string, string> = location ? { location } : {};
	const fetch = vi.fn().mockResolvedValue(new Response('', { headers }));
	return { event: { fetch, cookies: { get: () => undefined, set: vi.fn() } } as never, fetch };
}

describe('GET /auth/google (entrada do OAuth, proxiada pelo BFF)', () => {
	it('a API devolve a URL do Google: redireciona (302) para lá', async () => {
		const url = 'https://accounts.google.com/o/oauth2/v2/auth?state=abc';
		const { event, fetch } = fakeEvent(url);
		const r = await caught(() => GET(event));

		expect(fetch.mock.calls[0][0]).toContain('/api/auth/strategy/user/google');
		expect(r.status).toBe(302);
		expect(r.location).toBe(url);
	});

	it('sem Location da API: volta a /entrar?erro=google', async () => {
		const { event } = fakeEvent(null);
		const r = await caught(() => GET(event));

		expect(r.status).toBe(303);
		expect(r.location).toBe('/entrar?erro=google');
	});
});
