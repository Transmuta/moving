import { describe, it, expect } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { render } from '@testing-library/svelte';
import Field from './Field.svelte';

describe('Field', () => {
	it('associa o label ao input e repassa name/type/required', () => {
		const { getByLabelText } = render(Field, {
			props: { label: 'E-mail', name: 'email', type: 'email', required: true, autocomplete: 'email' }
		});

		const input = getByLabelText('E-mail');
		expect(input).toHaveAttribute('name', 'email');
		expect(input).toHaveAttribute('type', 'email');
		expect(input).toBeRequired();
		expect(input).toHaveAttribute('autocomplete', 'email');
	});

	it('reflete o value inicial', () => {
		const { getByLabelText } = render(Field, {
			props: { label: 'E-mail', name: 'email', value: 'ja@preenchido.com' }
		});
		expect(getByLabelText('E-mail')).toHaveValue('ja@preenchido.com');
	});
});
