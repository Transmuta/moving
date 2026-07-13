import { describe, it, expect, vi } from 'vitest';
import { handle } from './hooks.server';

function fakeEvent(themeCookie?: string) {
	return {
		cookies: { get: (n: string) => (n === 'mv-theme' ? themeCookie : undefined) }
	} as never;
}

// resolve mock: captura o transformPageChunk e devolve uma Response real — o `handle` seta
// os headers de segurança nela (doc 03 §4.4 + auditoria doc 13).
function fakeResolve() {
	let transform!: (opts: { html: string }) => string;
	const resolve = vi.fn((_e: unknown, opts: { transformPageChunk: typeof transform }) => {
		transform = opts.transformPageChunk;
		return new Response('RESOLVED');
	});
	return { resolve, getTransform: () => transform };
}

// Roda o `handle` com um cookie de tema e devolve a função que aplica o transformPageChunk
// ao HTML servido — o mecanismo do dark mode sem flash.
function transformFor(themeCookie?: string) {
	const { resolve, getTransform } = fakeResolve();
	handle({ event: fakeEvent(themeCookie), resolve } as never);
	return (html: string) => getTransform()({ html });
}

const TEMPLATE = '<html lang="%mv-lang%"%mv-theme%>';

describe('handle (tema sem flash + lang pt-BR)', () => {
	it('cookie dark estampa data-theme="dark"', () => {
		expect(transformFor('dark')(TEMPLATE)).toBe('<html lang="pt-BR" data-theme="dark">');
	});

	it('cookie light estampa data-theme="light"', () => {
		expect(transformFor('light')(TEMPLATE)).toBe('<html lang="pt-BR" data-theme="light">');
	});

	it('sem cookie: NÃO estampa data-theme (deixa o prefers-color-scheme decidir)', () => {
		expect(transformFor(undefined)(TEMPLATE)).toBe('<html lang="pt-BR">');
	});

	it('cookie inválido: tratado como ausente', () => {
		expect(transformFor('azul')(TEMPLATE)).toBe('<html lang="pt-BR">');
	});
});

describe('handle (headers de segurança, auditoria doc 13)', () => {
	it('seta nosniff, X-Frame-Options DENY e Referrer-Policy na resposta', async () => {
		const { resolve } = fakeResolve();
		const res = await handle({ event: fakeEvent(), resolve } as never);

		expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
		expect(res.headers.get('X-Frame-Options')).toBe('DENY');
		expect(res.headers.get('Referrer-Policy')).toBe('strict-origin-when-cross-origin');
	});
});
