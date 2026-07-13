import { describe, it, expect, vi } from 'vitest';
import { handle } from './hooks.server';

// Roda o `handle` com um cookie de tema e devolve a função que aplica o transformPageChunk
// ao HTML servido — o mecanismo do dark mode sem flash (doc 03 §4.4).
function transformFor(themeCookie?: string) {
	const event = {
		cookies: { get: (n: string) => (n === 'mv-theme' ? themeCookie : undefined) }
	} as never;

	let transform!: (opts: { html: string }) => string;
	const resolve = vi.fn((_e: unknown, opts: { transformPageChunk: typeof transform }) => {
		transform = opts.transformPageChunk;
		return 'RESOLVED';
	});

	handle({ event, resolve } as never);
	return (html: string) => transform({ html });
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
