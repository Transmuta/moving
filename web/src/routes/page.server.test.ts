import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { load } from './+page.server';

// O tipo de retorno de PageServerLoad inclui `void`; nos testes sabemos a forma concreta.
type LoadResult = {
	me: { user?: { nome?: string; email?: string } } | null;
	pings: { id: string; message: string }[];
	error: string | null;
};
const runLoad = async (event: never): Promise<LoadResult> => (await load(event)) as LoadResult;

function json(body: unknown, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' }
	});
}

// Roteia o fetch do BFF por fragmento de path (/api/auth/me vs /api/json/pings).
function fakeEvent(routes: Record<string, Response>) {
	const fetch = vi.fn((url: string) => {
		for (const [frag, res] of Object.entries(routes)) {
			if (url.includes(frag)) return Promise.resolve(res);
		}
		return Promise.resolve(new Response('', { status: 404 }));
	});
	return { fetch, cookies: { get: () => undefined } } as never;
}

describe('load /(+page.server) — BFF agrega /me e /pings', () => {
	it('sessão ativa: devolve o me e mapeia os pings', async () => {
		const event = fakeEvent({
			'/api/auth/me': json({ user: { id: 'u1', nome: 'Ana', email: 'ana@x.com' } }),
			'/api/json/pings': json({ data: [{ id: 'p1', attributes: { message: 'oi' } }] })
		});

		const data = await runLoad(event);

		expect(data.me?.user?.nome).toBe('Ana');
		expect(data.pings).toEqual([{ id: 'p1', message: 'oi' }]);
		expect(data.error).toBeNull();
	});

	it('sem sessão (401 no /me): me vira null, pings seguem', async () => {
		const event = fakeEvent({
			'/api/auth/me': json({ error: 'not_authenticated' }, 401),
			'/api/json/pings': json({ data: [] })
		});

		const data = await runLoad(event);

		expect(data.me).toBeNull();
		expect(data.pings).toEqual([]);
	});

	it('resposta 200 mas sem user: me null (não confia em corpo vazio)', async () => {
		const event = fakeEvent({
			'/api/auth/me': json({}),
			'/api/json/pings': json({ data: [] })
		});

		expect((await runLoad(event)).me).toBeNull();
	});

	it('erro na API de pings: expõe a mensagem de erro, sem quebrar', async () => {
		const event = fakeEvent({
			'/api/auth/me': json({ user: { id: 'u1' } }),
			'/api/json/pings': json({ error: 'boom' }, 500)
		});

		const data = await runLoad(event);
		expect(data.pings).toEqual([]);
		expect(data.error).toContain('500');
	});

	it('exceção de rede: me vira null e o erro de pings é reportado (catch)', async () => {
		const event = {
			fetch: vi.fn().mockRejectedValue(new Error('ECONNREFUSED')),
			cookies: { get: () => undefined }
		} as never;

		const data = await runLoad(event);
		expect(data.me).toBeNull();
		expect(data.error).toContain('Falha ao contatar');
	});
});
