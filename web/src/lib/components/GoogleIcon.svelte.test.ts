import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import GoogleIcon from './GoogleIcon.svelte';

describe('GoogleIcon', () => {
	it('renderiza o SVG da marca, decorativo (aria-hidden)', () => {
		const { container } = render(GoogleIcon);
		const svg = container.querySelector('svg');
		expect(svg).not.toBeNull();
		expect(svg?.getAttribute('aria-hidden')).toBe('true');
	});

	it('respeita o tamanho via prop size', () => {
		const { container } = render(GoogleIcon, { props: { size: 24 } });
		const svg = container.querySelector('svg');
		expect(svg?.getAttribute('width')).toBe('24');
		expect(svg?.getAttribute('height')).toBe('24');
	});
});
