import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { requestMagicLink } from './auth';
import { SESSION_COOKIE } from './api';

function fakeEvent(email: string, fetchImpl?: ReturnType<typeof vi.fn>) {
	const fd = new FormData();
	fd.set('email', email);
	const request = new Request('http://web/entrar', { method: 'POST', body: fd });
	const fetch = fetchImpl ?? vi.fn().mockResolvedValue(new Response('{"ok":true}'));
	return {
		event: { request, fetch, cookies: { get: () => undefined } } as never,
		fetch
	};
}

describe('requestMagicLink (action compartilhada, resposta neutra)', () => {
	it('e-mail vazio: fail(400) e NÃO chama a API', async () => {
		const { event, fetch } = fakeEvent('   ');
		const result = (await requestMagicLink(event)) as { status: number; data: { error: string } };

		expect(result.status).toBe(400);
		expect(result.data.error).toMatch(/e-mail/i);
		expect(fetch).not.toHaveBeenCalled();
	});

	it('form sem o campo email: também fail(400) sem chamar a API', async () => {
		const request = new Request('http://web/entrar', { method: 'POST', body: new FormData() });
		const fetch = vi.fn();
		const event = { request, fetch, cookies: { get: () => undefined } } as never;

		const result = (await requestMagicLink(event)) as { status: number };
		expect(result.status).toBe(400);
		expect(fetch).not.toHaveBeenCalled();
	});

	it('e-mail válido: POST /api/auth/magic-link e retorna {sent:true}', async () => {
		const { event, fetch } = fakeEvent('ana@example.com');
		const result = await requestMagicLink(event);

		expect(result).toEqual({ sent: true, email: 'ana@example.com' });
		const [url, init] = fetch.mock.calls[0];
		expect(url).toBe('http://localhost:4000/api/auth/magic-link');
		expect(init.method).toBe('POST');
		expect(JSON.parse(init.body as string)).toEqual({ email: 'ana@example.com' });
	});

	it('faz trim do e-mail antes de mandar', async () => {
		const { event, fetch } = fakeEvent('  bruno@example.com  ');
		const result = await requestMagicLink(event);

		expect(result).toEqual({ sent: true, email: 'bruno@example.com' });
		expect(JSON.parse(fetch.mock.calls[0][1].body as string)).toEqual({ email: 'bruno@example.com' });
	});

	it('falha de rede não vaza: ainda retorna {sent:true} (neutro)', async () => {
		const failing = vi.fn().mockRejectedValue(new Error('ECONNREFUSED'));
		const { event } = fakeEvent('carla@example.com', failing);

		const result = await requestMagicLink(event);
		expect(result).toEqual({ sent: true, email: 'carla@example.com' });
	});

	it('não repassa cookie de sessão inexistente (SESSION_COOKIE ausente)', async () => {
		const { event, fetch } = fakeEvent('d@example.com');
		await requestMagicLink(event);
		expect((fetch.mock.calls[0][1].headers as Headers).get('cookie')).toBeNull();
		expect(SESSION_COOKIE).toBe('_api_key');
	});
});
