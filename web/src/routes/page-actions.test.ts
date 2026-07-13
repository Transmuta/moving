import { describe, it, expect, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));

import { actions as entrarActions } from './entrar/+page.server';
import { actions as criarContaActions } from './criar-conta/+page.server';
import { requestMagicLink } from '$lib/server/auth';

// /entrar e /criar-conta compartilham a MESMA action (pedir magic link, ADR-015).
describe('fiação das actions de /entrar e /criar-conta', () => {
	it('ambas apontam para requestMagicLink', () => {
		expect(entrarActions.default).toBe(requestMagicLink);
		expect(criarContaActions.default).toBe(requestMagicLink);
	});
});
