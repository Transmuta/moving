import { test, expect } from '@playwright/test';

// A jornada mais crítica: entrar sem senha (ADR-015). O submit chega ao estado NEUTRO
// mesmo sem depender do e-mail chegar — a API responde neutro por design.
test.describe('Entrada passwordless', () => {
	test('/entrar: submeter e-mail leva ao estado neutro "Confira seu e-mail"', async ({ page }) => {
		await page.goto('/entrar');
		await expect(page.getByRole('heading', { name: 'Entrar na clínica' })).toBeVisible();

		const email = 'teste-e2e@example.com';
		await page.getByLabel('E-mail').fill(email);
		await page.getByRole('button', { name: 'Enviar link de acesso' }).click();

		// Neutro: confirma sem revelar se a conta existe, e ecoa o e-mail informado.
		await expect(page.getByText('Confira seu e-mail')).toBeVisible();
		await expect(page.getByText(email)).toBeVisible();
	});

	test('home desautenticada oferece o caminho de entrar', async ({ page }) => {
		await page.goto('/');
		const entrar = page.getByRole('link', { name: 'Entrar' });
		await expect(entrar).toBeVisible();

		await entrar.click();
		await expect(page).toHaveURL(/\/entrar$/);
		await expect(page.getByLabel('E-mail')).toBeVisible();
	});
});
