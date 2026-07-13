import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { load } from './+page.server';

// O tipo de retorno de PageServerLoad inclui `void`; nos testes sabemos a forma concreta.
type LoadResult = { me: { user?: { nome?: string; email?: string } } | null };
const runLoad = async (event: never): Promise<LoadResult> => (await load(event)) as LoadResult;

function json(body: unknown, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' }
	});
}

// Roteia o fetch do BFF por fragmento de path (só /api/auth/me — o Ping foi removido, doc 13).
function fakeEvent(routes: Record<string, Response>) {
	const fetch = vi.fn((url: string) => {
		for (const [frag, res] of Object.entries(routes)) {
			if (url.includes(frag)) return Promise.resolve(res);
		}
		return Promise.resolve(new Response('', { status: 404 }));
	});
	return { fetch, cookies: { get: () => undefined } } as never;
}

describe('load /(+page.server) — BFF carrega /me', () => {
	it('sessão ativa: devolve o me', async () => {
		const event = fakeEvent({
			'/api/auth/me': json({ user: { id: 'u1', nome: 'Ana', email: 'ana@x.com' } })
		});

		expect((await runLoad(event)).me?.user?.nome).toBe('Ana');
	});

	it('sem sessão (401 no /me): me vira null', async () => {
		const event = fakeEvent({ '/api/auth/me': json({ error: 'not_authenticated' }, 401) });
		expect((await runLoad(event)).me).toBeNull();
	});

	it('resposta 200 mas sem user: me null (não confia em corpo vazio)', async () => {
		const event = fakeEvent({ '/api/auth/me': json({}) });
		expect((await runLoad(event)).me).toBeNull();
	});

	it('exceção de rede: me vira null (catch)', async () => {
		const event = {
			fetch: vi.fn().mockRejectedValue(new Error('ECONNREFUSED')),
			cookies: { get: () => undefined }
		} as never;

		expect((await runLoad(event)).me).toBeNull();
	});
});
