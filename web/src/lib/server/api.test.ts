import { describe, it, expect, vi, beforeEach } from 'vitest';

// env dinâmico do SvelteKit: objeto mutável para exercitar fallback e override.
const { mockEnv } = vi.hoisted(() => ({
	mockEnv: {} as Record<string, string | undefined>
}));
vi.mock('$env/dynamic/private', () => ({ env: mockEnv }));

import { apiBase, apiPublicOrigin, apiFetch, reemitSession, SESSION_COOKIE } from './api';

beforeEach(() => {
	for (const k of Object.keys(mockEnv)) delete mockEnv[k];
});

describe('apiBase / apiPublicOrigin', () => {
	it('caem no default quando o env não define', () => {
		expect(apiBase()).toBe('http://localhost:4000');
		expect(apiPublicOrigin()).toBe('http://localhost:4010');
	});

	it('usam o env quando definido', () => {
		mockEnv.API_URL = 'http://api:4000';
		mockEnv.API_PUBLIC_ORIGIN = 'https://api.example.com';
		expect(apiBase()).toBe('http://api:4000');
		expect(apiPublicOrigin()).toBe('https://api.example.com');
	});
});

describe('apiFetch (BFF repassa o cookie de sessão)', () => {
	function fakeEvent(sessionValue?: string) {
		const fetch = vi.fn().mockResolvedValue(new Response('ok'));
		return {
			fetch,
			cookies: { get: (name: string) => (name === SESSION_COOKIE ? sessionValue : undefined) }
		} as never;
	}

	it('anexa o cookie de sessão quando existe', async () => {
		const event = fakeEvent('abc123');
		await apiFetch(event, '/api/auth/me');

		const [url, init] = (event as unknown as { fetch: ReturnType<typeof vi.fn> }).fetch.mock
			.calls[0];
		expect(url).toBe('http://localhost:4000/api/auth/me');
		expect((init.headers as Headers).get('cookie')).toBe(`${SESSION_COOKIE}=abc123`);
	});

	it('NÃO anexa cookie quando não há sessão', async () => {
		const event = fakeEvent(undefined);
		await apiFetch(event, '/api/json/pings');

		const [, init] = (event as unknown as { fetch: ReturnType<typeof vi.fn> }).fetch.mock.calls[0];
		expect((init.headers as Headers).get('cookie')).toBeNull();
	});

	it('honra API_URL do env na URL final', async () => {
		mockEnv.API_URL = 'http://api:4000';
		const event = fakeEvent('x');
		await apiFetch(event, '/api/health');

		const [url] = (event as unknown as { fetch: ReturnType<typeof vi.fn> }).fetch.mock.calls[0];
		expect(url).toBe('http://api:4000/api/health');
	});
});

describe('reemitSession (re-emite _api_key no domínio do web)', () => {
	function fakeEvent() {
		const set = vi.fn();
		const del = vi.fn();
		return { cookies: { set, del } } as never;
	}

	it('extrai o cookie do Set-Cookie e o re-emite httpOnly/lax', () => {
		const event = fakeEvent();
		const res = new Response('', {
			headers: { 'set-cookie': `${SESSION_COOKIE}=tok.en-value; Path=/; HttpOnly` }
		});

		const value = reemitSession(event, res);

		expect(value).toBe('tok.en-value');
		const set = (event as unknown as { cookies: { set: ReturnType<typeof vi.fn> } }).cookies.set;
		expect(set).toHaveBeenCalledWith(
			SESSION_COOKIE,
			'tok.en-value',
			expect.objectContaining({ path: '/', httpOnly: true, sameSite: 'lax' })
		);
	});

	it('acha o _api_key entre vários Set-Cookie', () => {
		const event = fakeEvent();
		const res = new Response('', {
			headers: [
				['set-cookie', 'outro=1; Path=/'],
				['set-cookie', `${SESSION_COOKIE}=alvo; Path=/`]
			]
		});

		expect(reemitSession(event, res)).toBe('alvo');
	});

	it('sem cookie de sessão: retorna null e não seta nada', () => {
		const event = fakeEvent();
		const res = new Response('', { headers: { 'set-cookie': 'irrelevante=1' } });

		expect(reemitSession(event, res)).toBeNull();
		const set = (event as unknown as { cookies: { set: ReturnType<typeof vi.fn> } }).cookies.set;
		expect(set).not.toHaveBeenCalled();
	});
});
