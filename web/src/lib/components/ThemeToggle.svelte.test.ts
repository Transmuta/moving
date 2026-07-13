import { describe, it, expect, beforeEach } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { render, fireEvent } from '@testing-library/svelte';
import ThemeToggle from './ThemeToggle.svelte';

beforeEach(() => {
	document.documentElement.removeAttribute('data-theme');
	// zera o cookie mv-theme entre casos.
	document.cookie = 'mv-theme=; max-age=0; path=/';
});

describe('ThemeToggle', () => {
	it('estado inicial dark: oferece "Ativar tema claro"', () => {
		const { getByRole } = render(ThemeToggle, { props: { initial: 'dark' } });
		expect(getByRole('button')).toHaveAttribute('aria-label', 'Ativar tema claro');
	});

	it('estado inicial light: oferece "Ativar tema escuro"', () => {
		const { getByRole } = render(ThemeToggle, { props: { initial: 'light' } });
		expect(getByRole('button')).toHaveAttribute('aria-label', 'Ativar tema escuro');
	});

	it('sem initial: deriva do data-theme já estampado no SSR', () => {
		document.documentElement.setAttribute('data-theme', 'dark');
		const { getByRole } = render(ThemeToggle, { props: { initial: null } });
		expect(getByRole('button')).toHaveAttribute('aria-label', 'Ativar tema claro');
	});

	it('clicar alterna o tema: estampa data-theme e persiste no cookie', async () => {
		const { getByRole } = render(ThemeToggle, { props: { initial: 'light' } });
		const btn = getByRole('button');

		await fireEvent.click(btn);

		expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
		expect(document.cookie).toContain('mv-theme=dark');
		expect(btn).toHaveAttribute('aria-label', 'Ativar tema claro');
	});
});
