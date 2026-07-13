import { defineConfig, devices } from '@playwright/test';

// E2E só nos cenários críticos (doc 16): sobe o app buildado (produção-like) e dirige o
// browser real. Poucos, caros — cobrem o encanamento; as regras já são exauridas embaixo.
const PORT = 4173;

export default defineConfig({
	testDir: 'e2e',
	timeout: 30_000,
	expect: { timeout: 5_000 },
	fullyParallel: true,
	forbidOnly: !!process.env.CI,
	retries: process.env.CI ? 1 : 0,
	reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
	use: {
		baseURL: `http://localhost:${PORT}`,
		trace: 'on-first-retry'
	},
	webServer: {
		command: `npm run build && npm run preview -- --port ${PORT}`,
		port: PORT,
		reuseExistingServer: !process.env.CI,
		timeout: 120_000
	},
	projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }]
});
