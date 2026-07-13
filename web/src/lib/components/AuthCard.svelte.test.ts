import { describe, it, expect } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { render } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';
import AuthCard from './AuthCard.svelte';

const snippet = (html: string) =>
	createRawSnippet(() => ({ render: () => `<div>${html}</div>` }));

describe('AuthCard', () => {
	it('renderiza título, subtítulo, conteúdo, rodapé e o toggle de tema', () => {
		const { getByRole, getByText } = render(AuthCard, {
			props: {
				title: 'Entrar na clínica',
				subtitle: 'O sistema que enche a sua agenda.',
				// theme explícito evita o ramo matchMedia do ThemeToggle (ausente no jsdom).
				theme: 'light',
				children: snippet('conteúdo-do-form'),
				footer: snippet('rodapé-aqui')
			}
		});

		expect(getByRole('heading', { name: 'Entrar na clínica' })).toBeInTheDocument();
		expect(getByText('O sistema que enche a sua agenda.')).toBeInTheDocument();
		expect(getByText('conteúdo-do-form')).toBeInTheDocument();
		expect(getByText('rodapé-aqui')).toBeInTheDocument();
		// ThemeToggle no canto (initial=light → oferece ativar o escuro).
		expect(getByRole('button', { name: 'Ativar tema escuro' })).toBeInTheDocument();
	});
});
