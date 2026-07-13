import { test, expect } from '@playwright/test';

// Contrato do dark mode sem flash (doc 03 §4.4): o toggle grava o cookie mv-theme e o
// hooks.server re-estampa o MESMO tema no SSR do próximo request. Só um e2e prova a volta
// inteira (cookie → SSR) — o resto é unit/integração.
test('tema alterna e persiste após reload (sem flash, via cookie)', async ({ page }) => {
	await page.goto('/entrar');
	const html = page.locator('html');

	const toggle = page.getByRole('button', { name: /Ativar tema/ });
	await toggle.click();

	const chosen = await html.getAttribute('data-theme');
	expect(chosen === 'dark' || chosen === 'light').toBeTruthy();

	await page.reload();
	// O atributo veio já do HTML servido (SSR), não de um flash pós-hidratação.
	await expect(html).toHaveAttribute('data-theme', chosen!);
});
