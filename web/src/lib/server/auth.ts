import { fail, type RequestEvent } from '@sveltejs/kit';
import { apiFetch } from './api';

// Action compartilhada por /entrar e /criar-conta: pede o magic link (ADR-015). O BFF só
// repassa para a API; a resposta é sempre neutra (não revela se o e-mail tem conta).
export async function requestMagicLink(event: RequestEvent) {
	const data = await event.request.formData();
	const email = String(data.get('email') ?? '').trim();

	if (email === '') {
		return fail(400, { email, error: 'Informe seu e-mail.' });
	}

	try {
		await apiFetch(event, '/api/auth/magic-link', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ email })
		});
	} catch {
		// Falha de rede não vira erro visível: resposta neutra (ADR-015).
	}

	return { sent: true, email };
}
