import { describe, it, expect } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { render } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';
import Button from './Button.svelte';

// Snippet mínimo para o slot `children`.
const label = (text: string) =>
	createRawSnippet(() => ({ render: () => `<span>${text}</span>` }));

describe('Button', () => {
	it('renderiza um <button> por padrão', () => {
		const { getByRole } = render(Button, { props: { type: 'submit', children: label('Enviar') } });
		const btn = getByRole('button', { name: 'Enviar' });
		expect(btn).toHaveAttribute('type', 'submit');
	});

	it('vira um link <a> quando recebe href', () => {
		const { getByRole } = render(Button, {
			props: { href: '/auth/google', children: label('Google') }
		});
		expect(getByRole('link', { name: 'Google' })).toHaveAttribute('href', '/auth/google');
	});

	it('fica desabilitado com disabled', () => {
		const { getByRole } = render(Button, {
			props: { disabled: true, children: label('Enviando…') }
		});
		expect(getByRole('button')).toBeDisabled();
	});
});
