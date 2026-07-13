import { describe, it, expect } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { render } from '@testing-library/svelte';
import Logo from './Logo.svelte';

describe('Logo', () => {
	it('exibe o wordmark "Movimento"', () => {
		const { getByText } = render(Logo);
		expect(getByText('Movimento')).toBeInTheDocument();
	});
});
