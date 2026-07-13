import { describe, it, expect, vi } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { render } from '@testing-library/svelte';

// Módulos virtuais do SvelteKit que o AuthForm usa (enhance + page atual).
vi.mock('$app/forms', () => ({ enhance: () => ({ destroy() {} }) }));
vi.mock('$app/state', () => ({ page: { url: { pathname: '/entrar' } } }));

import AuthForm from './AuthForm.svelte';

const baseProps = { submitLabel: 'Enviar link de acesso', googleLabel: 'Entrar com Google' };

describe('AuthForm', () => {
	it('estado neutro (form.sent): confirma sem formulário e ecoa o e-mail', () => {
		const { getByText, queryByRole } = render(AuthForm, {
			props: { ...baseProps, form: { sent: true, email: 'ana@x.com' } }
		});

		expect(getByText('Confira seu e-mail')).toBeInTheDocument();
		expect(getByText('ana@x.com')).toBeInTheDocument();
		// Sem formulário: nada de botão de envio no estado neutro.
		expect(queryByRole('button')).toBeNull();
	});

	it('estado inicial (form null): campo de e-mail, botão de envio e link do Google', () => {
		const { getByLabelText, getByRole } = render(AuthForm, {
			props: { ...baseProps, form: null }
		});

		expect(getByLabelText('E-mail')).toBeInTheDocument();
		expect(getByRole('button', { name: 'Enviar link de acesso' })).toBeInTheDocument();
		expect(getByRole('link', { name: 'Entrar com Google' })).toHaveAttribute(
			'href',
			'/auth/google'
		);
	});

	it('erro de validação: exibe a mensagem retornada pela action', () => {
		const { getByText } = render(AuthForm, {
			props: { ...baseProps, form: { error: 'Informe seu e-mail.' } }
		});

		expect(getByText('Informe seu e-mail.')).toBeInTheDocument();
	});
});
