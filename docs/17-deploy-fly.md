# 17 — Deploy no Fly.io

Produção do Movimento no [Fly.io](https://fly.io): **dois apps** (a API e o web BFF) + um
Postgres. O TLS, o redirect http→https e o HSTS são da **edge do Fly** (`force_https` no
`fly.toml`) — por isso o `force_ssl` foi tirado do `prod.exs` (a API também é chamada
internamente por http). Artefatos: `api/Dockerfile.prod`, `web/Dockerfile.prod`, `api/fly.toml`,
`web/fly.toml`, `Api.Release`.

## Arquitetura

```
                 (TLS, HSTS, http→https na edge do Fly)
  browser ──https──> movimento-web.fly.dev  ──6PN──> movimento-api.internal:4000
                          (SvelteKit BFF)      (http privado, não passa pela edge)
  browser ──https──> movimento-api.fly.dev   (só OAuth callback do Google + WebSocket)
```

- **web** fala com a **api** pela rede privada 6PN (`http://movimento-api.internal:4000`) — nunca
  pela internet. Isso é o `API_URL`.
- O browser só toca a **api** direto em dois casos: o redirect do OAuth do Google e o WebSocket
  (`API_PUBLIC_ORIGIN`). O resto é sempre browser → web (BFF) → api.

## Modelo de dois roles do banco (RLS, ADR-018)

A RLS exige que o **app** conecte como um role **NOBYPASSRLS**. Migrations/DDL precisam de um
role **owner**. No Fly o `release_command` e o app rodam com os mesmos secrets, então separamos
por variável:

- `DATABASE_ADMIN_URL` — owner. Usado **só** pelo `release_command`
  (`Api.Release.setup()` → migrations + cria o role restrito).
- `DATABASE_URL` — restrito (`movimento_app`). Usado pelo app em runtime.

O `Api.Release.setup/0` (roda antes de trocar as máquinas) cria o role restrito com
`DATABASE_APP_USER`/`DATABASE_APP_PASSWORD`; o app sobe já sujeito à RLS.

## Secrets (por `fly secrets set`, no app da API)

```bash
fly secrets set \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  TOKEN_SIGNING_SECRET="$(mix phx.gen.secret)" \
  DATABASE_ADMIN_URL="ecto://<owner>:<senha>@<host>/<db>" \
  DATABASE_URL="ecto://movimento_app:<senha-app>@<host>/<db>" \
  DATABASE_APP_USER="movimento_app" \
  DATABASE_APP_PASSWORD="<senha-app>" \
  PHX_HOST="movimento-api.fly.dev" \
  WEB_APP_URL="https://movimento-web.fly.dev" \
  GOOGLE_CLIENT_ID="..." GOOGLE_CLIENT_SECRET="..." \
  GOOGLE_REDIRECT_URI="https://movimento-api.fly.dev/api/auth/strategy/user/google/callback" \
  --app movimento-api
```

> O `DATABASE_URL` (restrito) aponta para um role que só passa a existir depois do primeiro
> `release_command`. Tudo bem: o `release_command` usa a `DATABASE_ADMIN_URL` e roda **antes**
> de o app subir. Garanta que o owner do `DATABASE_ADMIN_URL` pode `CREATE ROLE` e fazer DDL.

O **web** não tem secrets sensíveis — `API_URL`, `API_PUBLIC_ORIGIN` e `ORIGIN` já estão no
`web/fly.toml` (`[env]`). Ajuste-os se usar domínio próprio.

## Passos (primeira vez)

```bash
# 1. Apps (ajuste nomes/região no fly.toml antes)
fly apps create movimento-api
fly apps create movimento-web

# 2. Postgres (Fly PG ou externo) e as URLs owner/app nos secrets acima
fly postgres create --name movimento-db --region gru   # ou um Postgres gerenciado externo

# 3. Secrets da API (bloco acima)

# 4. Deploy — cada app do seu diretório
cd api && fly deploy && cd ..
cd web && fly deploy && cd ..
```

Deploys seguintes: `fly deploy` em cada diretório (o `release_command` reaplica migrations).

## Verificar antes / depois

- **Local, sem Fly:** `docker compose -p movimento-smoke -f compose.prod.yml up --build` sobe as
  **mesmas imagens de prod** (release + role restrito + web buildado) em `localhost:4020` /
  `localhost:3020`. Prova que compila, migra e serve.
- **CSP:** já validado no build (`svelte.config.js` `kit.csp`, `mode: auto`) — o header
  `content-security-policy` sai com `script-src 'self' 'nonce-…'`.
- **Google OAuth:** cadastre o `GOOGLE_REDIRECT_URI` acima no console do Google.
- **Bind IPv6:** a API já escuta em `::` (runtime.exs). Se o web (adapter-node) ficar
  inalcançável no Fly, setar `HOST="::"` no `web/fly.toml`.
- **Domínio próprio:** `fly certs add ...` e atualize `PHX_HOST`/`WEB_APP_URL`/`ORIGIN`/
  `API_PUBLIC_ORIGIN`/`GOOGLE_REDIRECT_URI`.
