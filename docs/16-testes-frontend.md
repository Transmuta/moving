# Testes do frontend (a pirâmide no BFF/SvelteKit)

Par frontend do [15-gate-de-cobertura-e-ci.md](15-gate-de-cobertura-e-ci.md) e aplicação da
mesma filosofia do [07-estrategia-de-testes.md](07-estrategia-de-testes.md) §7 ao `web/`:
**base larga de unitário, integração no meio, e2e só nos cenários críticos.** A regra de
ouro é a mesma — cada comportamento é provado no nível mais baixo em que ele pode existir;
o e2e cobre o encanamento, não as regras.

O `web/` é um **BFF** (ADR-005): o browser nunca fala com a API; o SvelteKit repassa tudo
server-to-server, re-emitindo o cookie de sessão. Então o "motor" a testar aqui é a lógica
de servidor do BFF — repasse de cookie, re-emissão de sessão, resposta neutra — não a UI.

## Ferramentas

- **Vitest 4** com dois *projects* (config em [`web/vite.config.ts`](../web/vite.config.ts)):
  - `client` (jsdom): componentes Svelte 5 — arquivos `*.svelte.test.ts`, via
    `@testing-library/svelte`.
  - `server` (node): lógica de BFF e route handlers — `*.test.ts` em `src/lib/server` e
    `src/routes`.
- **Playwright** ([`web/playwright.config.ts`](../web/playwright.config.ts)): sobe o app
  buildado (`build` + `preview`) e dirige o Chromium. Só cenários críticos.
- Scripts: `npm run test:unit` (Vitest), `npm run test:e2e` (Playwright), `npm test` (ambos).

## O que é testado, por nível

### Unitário (o motor do BFF) — `src/lib/server`, `src/hooks.server.ts`

- **`api.ts`** — o coração de segurança do BFF: `apiFetch` **anexa** o cookie de sessão
  quando existe e **não anexa** quando não existe; `reemitSession` extrai o `_api_key` do
  `Set-Cookie` (inclusive entre vários) e o re-emite `httpOnly`/`lax`, ou retorna `null`;
  `apiBase`/`apiPublicOrigin` caem no default ou honram o env.
- **`auth.ts`** — `requestMagicLink`: e-mail vazio → `fail(400)` sem chamar a API; válido →
  `POST /api/auth/magic-link` e `{sent:true}`; **falha de rede não vaza** (ainda `{sent:true}`,
  resposta neutra do ADR-015); faz `trim`.
- **`hooks.server.ts`** — `handle`: cookie `mv-theme` dark/light estampa `data-theme`;
  ausente/ inválido não estampa (deixa o `prefers-color-scheme` decidir); `lang` = pt-BR.

### Integração — route handlers + componentes

- **Route handlers** (compõem `apiFetch` + `redirect` + cookies):
  - `auth/callback` (magic link): sem token → `/entrar?erro=link`; sessão emitida →
    re-emite e vai para `/`; sessão não emitida → volta com erro.
  - `auth/sign-out`: `DELETE` na API, apaga o cookie local, redireciona — **mesmo se a API
    falhar**, o cookie some.
  - `+page.server` (`load`): agrega `/me` + `/pings`; 401 no `/me` → `me` null sem quebrar;
    200 sem `user` → `me` null (não confia em corpo vazio); erro nos pings → mensagem.
- **Componentes** (`@testing-library/svelte`) — **os 7**: `Button` (button vs link por `href`,
  disabled), `Field` (label↔input, name/type/required/value), `ThemeToggle` (alterna aria-label,
  estampa `data-theme` e persiste o cookie), `AuthCard` (título/subtítulo/conteúdo/rodapé +
  toggle), `AuthForm` (estado neutro vs formulário vs erro — com `$app/forms`/`$app/state`
  mockados), `Logo` e `GoogleIcon`.

### E2E (Playwright) — só o crítico

- **Entrada passwordless**: em `/entrar`, submeter o e-mail leva ao estado **neutro**
  "Confira seu e-mail" (funciona mesmo sem a API — o neutro é por design); home
  desautenticada oferece o caminho de entrar.
- **Tema sem flash**: alternar o tema e recarregar mantém o `data-theme` — prova a volta
  inteira (cookie do cliente → `hooks.server` re-estampa no SSR). É o único ponto que só o
  e2e cobre; o resto é unit/integração.

## Gate de cobertura (Vitest v8)

Análogo ao `minimum_coverage` do backend. Configurado em
[`web/vite.config.ts`](../web/vite.config.ts) (`test.coverage`), rodado por `npm run coverage`
(= `vitest run --coverage`), **falha abaixo do threshold**.

- **Escopo** (`include`): `src/lib/**` (server + componentes), `src/hooks.server.ts` e os
  route handlers `src/routes/**/*.ts`. As **páginas `.svelte`** (SSR) ficam fora — são
  território de e2e, como o backend deixa `endpoint`/`telemetry` fora. `assets`/`styles` e os
  `*.test.ts` também são excluídos.
- **Thresholds**: 80% em lines/statements/functions (alinhado ao gate do backend); **branches
  em 75%** de propósito — o v8 conta fallbacks defensivos que não rodam no ambiente de teste
  (`matchMedia`, `getSetCookie`), inerentemente abaixo.
- **Atual**: statements **96,98%**, lines **95,65%**, functions **97,72%**, branches **82,19%**.

## Estado

**51 testes Vitest (17 arquivos) + 3 Playwright, todos verdes.** `svelte-check` limpo.
Cobertura 96,98% (stmts). Todos os 7 componentes e todos os route handlers testados.

## CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml))

- Job **web**: `npm run check` (svelte-check) → `npm run coverage` (testes + gate) → `npm run build`.
- Job **web-e2e**: `npx playwright install --with-deps chromium` → `npm run test:e2e`
  (a config sobe o app sozinha); publica o `playwright-report` como artefato em caso de falha.

## O que ainda falta (ratchet)

- **Cobertura do backend com número por-dimensão**: o Elixir usa um piso único (linha) de 80%;
  aqui temos branch/function/statement separados. Simetria opcional.
- Mais e2e **só** se surgir jornada crítica nova (arrastar agendamento, oferecer vaga da
  fila) — quando os motores existirem; hoje eles nem foram portados (07).
