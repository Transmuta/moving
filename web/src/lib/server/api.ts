import { env } from '$env/dynamic/private';
import type { RequestEvent } from '@sveltejs/kit';

// Nome do cookie de sessão emitido pela API Phoenix (endpoint.ex :key "_api_key").
export const SESSION_COOKIE = '_api_key';

// Endereço interno da API (server-to-server, pela rede do compose). O browser nunca fala
// direto com a API (ADR-005) — só o BFF, e ele repassa o cookie de sessão.
export function apiBase(): string {
	return env.API_URL ?? 'http://localhost:4000';
}

// Origem PÚBLICA da API (browser-reachable). Usada só para o redirect do OAuth ao provedor,
// que exige uma navegação real do browser — a mesma exceção ao BFF que o WebSocket é.
export function apiPublicOrigin(): string {
	return env.API_PUBLIC_ORIGIN ?? 'http://localhost:4010';
}

// Fetch para a API repassando o cookie de sessão do request atual (BFF).
export function apiFetch(event: RequestEvent, path: string, init: RequestInit = {}): Promise<Response> {
	const headers = new Headers(init.headers);
	const session = event.cookies.get(SESSION_COOKIE);
	if (session) headers.set('cookie', `${SESSION_COOKIE}=${session}`);
	return event.fetch(`${apiBase()}${path}`, { ...init, headers });
}

// Re-emite o cookie de sessão da API (`_api_key`) no domínio do WEB, a partir do Set-Cookie
// de uma resposta da API. É o que faz a sessão (e o `state` do OAuth) viverem no web — o
// browser nunca precisa falar direto com a API (ADR-005). Retorna o valor setado, ou null.
// Espelha o token_lifetime do JWT na API (AshAuthentication default = 14 dias). Manter
// alinhado: um cookie que vive mais que o JWT só geraria um "logout súbito" quando o token
// expira mas o cookie ainda existe. `secure` é omitido de propósito — o SvelteKit já ativa
// Secure automaticamente fora de localhost.
const SESSION_MAX_AGE = 60 * 60 * 24 * 14;

export function reemitSession(event: RequestEvent, res: Response): string | null {
	const value = extractSessionCookie(res);
	if (value) {
		event.cookies.set(SESSION_COOKIE, value, {
			path: '/',
			httpOnly: true,
			sameSite: 'lax',
			maxAge: SESSION_MAX_AGE
		});
	}
	return value;
}

function extractSessionCookie(res: Response): string | null {
	const list =
		typeof res.headers.getSetCookie === 'function'
			? res.headers.getSetCookie()
			: [res.headers.get('set-cookie') ?? ''];

	for (const cookie of list) {
		const match = cookie.match(new RegExp(`${SESSION_COOKIE}=([^;]+)`));
		if (match) return match[1];
	}
	return null;
}
