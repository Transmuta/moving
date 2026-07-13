import { describe, it, expect } from 'vitest';
import { load } from './+layout.server';

function run(theme?: string) {
	const event = { cookies: { get: (n: string) => (n === 'mv-theme' ? theme : undefined) } } as never;
	return load(event);
}

describe('load /(+layout.server) — expõe a escolha de tema ao cliente', () => {
	it('cookie dark → dark; light → light', () => {
		expect(run('dark')).toEqual({ theme: 'dark' });
		expect(run('light')).toEqual({ theme: 'light' });
	});

	it('sem cookie ou valor inválido → null', () => {
		expect(run(undefined)).toEqual({ theme: null });
		expect(run('roxo')).toEqual({ theme: null });
	});
});
