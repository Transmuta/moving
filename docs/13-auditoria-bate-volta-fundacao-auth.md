# 13 — Auditoria bate-volta: fatia de fundação (identidade + auth multi-tenant)

> Rodada de auditoria pela skill `bate-volta` sobre o branch `feat/identidade-multi-tenant`
> (app inteira, primeira passada). **Só rodadas 1 e 2 (caça); nada foi consertado** — a pedido.
> Cada achado abaixo tem o **output da sonda colado**. Data: 2026-07-12. Stack sondada de pé
> (`docker compose`: api/db/web up).

---

## 1. Onde parou, e por quê

Parou **depois da rodada 2**, por instrução — gerar o mapa de achados para decisão humana, sem
tocar no código. A rodada 1 (checklist) e a rodada 2 (adversarial) rodaram completas; a
consolidação abaixo agrupa por causa-raiz. As rodadas 3–5 (conserto/verificação) **não** foram
executadas.

A rodada 2 pagou: o achado de maior superfície — **`/api/json/pings` público, sem
autenticação, com create aberto** — não sai da leitura de policies (rodada 1), e sim de
*bater no endpoint sem cookie* (rodada 2).

---

## 2. A varredura

Estados: **CONF** = confirmado por sonda · **REF** = refutado por sonda · **N/A** = sem
superfície neste código.

### Segurança

| Item | Estado | Prova (sonda) |
|---|---|---|
| Bypass do BFF / ataque direto na API | **CONF** | API acessível direto em `:4010`; endpoints de auth barram sem cookie (401), mas `pings` não (ver abaixo). |
| Broken Function Level Authz (recurso sem policy) | **CONF** | `Api.Meta.Ping` **sem `Ash.Policy.Authorizer`**, roteado no AshJsonApi. → causa **B**. |
| Rate limit / brute force | **CONF** | 15 POSTs em `/api/auth/magic-link` → 15× HTTP 200, sem throttle. → causa **A**. |
| CSRF: sign-out via GET (web) | **CONF** | `web/src/routes/auth/sign-out/+server.ts` responde a `GET` e apaga sessão. → causa **E** (minor). |
| Headers de segurança (CSP/HSTS/X-Frame) | **CONF** | `endpoint.ex` e `hooks.server.ts` não setam nenhum. → causa **E**. |
| Cookie de sessão sem flag `secure` | **CONF** | `@session_options` no `endpoint.ex` só tem `same_site: "Lax"`. → causa **E**. |
| Tenant vindo do cliente | **REF** | `LoadScope` resolve tenant da sessão; `me`/`switch-tenant` exigem cookie (401 sem ele). |
| IDOR / BOLA (cross-tenant) | **REF** | RLS provada de baixo (ver causa **C**/prova); `professionals` nem roteado na API (404). |
| Enumeração de usuário (corpo/tempo) | **REF** | corpo neutro `{"ok":true}` p/ e-mail que existe e que não; tempos sobrepostos (0.019 vs 0.022s). |
| Vazamento em log (PII/token) | **REF** | log em debug mostra e-mail/`jti`, mas `prod.exs` seta `config :logger, level: :info`. |
| Secrets em código | **REF** | segredos hardcoded só em `dev.exs`/`test.exs`; `prod` via env, `raise` se faltar (`runtime.exs`). |
| Vazamento de `clinic_id` ao cliente | **N/A** | no modelo Vercel (ADR-014) o `clinic_id` é o seletor de tenant do cliente por design (`/me`, `switch-tenant`) — não é segredo de subdomínio. |
| XSS (stored/refletido/e-mail) | **N/A** | zero `{@html}` no `web/`; e-mail de magic link é `text_body` puro; Svelte escapa por padrão. |
| SQL injection | **N/A** | Ash/Ecto parametrizado; GUC via `set_config($1,$2,true)` (binds), não interpolação. |
| SSRF / Open redirect / Path traversal | **N/A** | BFF só chama `API_URL` fixo; redirects são internos/config; sem I/O de arquivo. |
| Mass assignment | **N/A** | `accept`s estreitos (ex. `register` → `[:nome,:email]`; `ping.create` → `[:message]`); `status`/`clinic_id`/`user_id` entram como argumento gerido, não atributo aceito. |
| Dependência vulnerável | **CONF** | `npm audit`: 3 low (`cookie <0.7.0` via `@sveltejs/kit`). `mix hex.audit` limpo. → causa **F**. |

### Performance

| Item | Estado | Prova (sonda) |
|---|---|---|
| Índice ausente na coluna de tenant | **CONF** | `professionals.clinic_id` sem índice; `EXPLAIN` → `Seq Scan ... Filter: (clinic_id = current_setting(...))`. → causa **C**. |
| Índice ausente em FK | **CONF** | `user_identities.user_id` sem índice de prefixo (P4). → causa **C**. |
| `on_delete` inconsistente | **CONF** | `memberships` CASCADE vs `professionals`/`user_identities` RESTRICT (sem `on_delete`). → causa **D**. |
| Waterfall de fetch no BFF | **CONF** | `+page.server.ts`: `await loadMe` depois `await loadPings` (sequenciais e independentes). → causa **G**. |
| N+1 no `/me` | **REF** | `active_for_user` faz `prepare build(load: [:clinic])` — preload único, não query por linha. |
| LIMIT / paginação | **N/A** | Ash com `default_page_type: :keyset` (config.exs). |
| Pool / transação longa | **N/A** | sem worker concorrente nem HTTP externo dentro de transação nesta fatia. |

### Refatoração / rules

| Item | Estado | Prova (sonda) |
|---|---|---|
| Comentário contradiz o código | **CONF** | `Clinic` @moduledoc diz "provisiona o schema `tenant_<uuid>` via `manage_tenant`"; ADR-017 removeu schema-por-tenant (o comentário logo abaixo já diz o contrário). → causa **H**. |
| DRY: lógica/literal duplicada | **CONF** | `web_app_url/0` idêntico em 3 módulos. → causa **I**. |
| Cobertura de testes | **CONF** | só 2 arquivos de teste; RBAC/RLS/switch-tenant sem teste. → causa **J**. |
| Lógica de negócio/authz fora de action/policy | **REF** | tudo em actions/policies Ash; controllers só orquestram sessão. |
| Nomes / tamanho / god-files | **N/A** | módulos pequenos e descritivos; nada acende a régua. |

**O que a rodada 2 achou que a 1 não tinha:** o `pings` público (causa **B**) e a **prova
positiva** de que a RLS isola de fato (refutou o IDOR) — ambos vieram de exercitar a app viva,
não de ler policy.

---

## 3. As causas-raiz (agrupadas)

- **A** — Ausência de rate limiting (toca brute-force e DoS).
- **B** — Recurso scaffold `Ping` exposto na API sem authorizer (o domínio `Api.Meta` inteiro é o ponto-cego: o que entrar ali herda a abertura).
- **C** — Índices ausentes na coluna de tenant e em FK.
- **D** — `on_delete` inconsistente entre os filhos de `User`/`Clinic`.
- **E** — Hardening de produção pendente (cookie `secure`, headers, sign-out GET).
- **F** — Dependência com advisory low (`cookie` via SvelteKit).
- **G** — Waterfall no `load` do BFF.
- **H** — Comentário do `Clinic` contradiz o ADR-017.
- **I** — DRY: `web_app_url` triplicado.
- **J** — Cobertura de testes parcial.

**Interações a considerar antes de consertar:** **B** e **C** se cruzam num futuro próximo —
quando `Professional` for roteado no AshJsonApi (hoje dá 404), ele precisa **ao mesmo tempo**
de policy (já tem) *e* do índice de tenant (**C**), e o padrão "todo recurso roteado tem
authorizer" (**B**) deve estar valendo. Fechar **B** só no `Ping` sem virar regra deixa a
porta aberta para o próximo recurso do `Meta`.

---

## 4. O que foi corrigido (rodadas 3–5)

Consertado numa segunda passada, na ordem segurança → performance → refatoração. Cada item traz
a **re-sonda da rodada 5** provando o conserto na app rodando + o teste que ficou verde. Suíte
final: **49 testes, 0 falhas**; `mix compile --warnings-as-errors` limpo; `svelte-check` 0/0.

> Decisões suas nesta passada: **remover o `Ping` inteiro** (recurso + rota + tabela + demo do
> web) e **adicionar rate limiting agora, só-prod, com janela deslizante**.

| Causa | Conserto | Re-sonda (rodada 5) |
|---|---|---|
| **B** | `Api.Meta.Ping` + rota + tabela `pings` removidos (migration `drop_pings_scaffold`, reversível); demo de pings tirado do web. | `GET/POST /api/json/pings` → **404** (era 200 público). `to_regclass('pings')` → vazio. |
| **A** | `Hammer` (ETS, **sliding window**) + `ApiWeb.Plugs.RateLimitAuth` nos endpoints de auth, por e-mail **e** IP; gated a prod (`config :api, rate_limit_enabled` no `prod.exs`). | Teste `rate_limit_auth_test`: 6º pedido do mesmo e-mail → **429**. Flood no dev segue **200** (só-prod, por design). |
| **C** | `custom_indexes` — `index [:clinic_id]` em `Professional`, `index [:user_id]` em `UserIdentity`. | `EXPLAIN` (como `movimento_app`) → **`Index Scan using professionals_clinic_id_index`** (era Seq Scan). |
| **D** | `on_delete: :delete` em **ambas** as FKs de tenant: `UserIdentity.user` e `Professional.clinic` (esta via drop+add constraint em SQL cru — `modify` da coluna falha com `0A000`, pois `clinic_id` é usado na policy RLS). | `pg_get_constraintdef` → as duas com **`ON DELETE CASCADE`**; policy `tenant_isolation` intacta. |
| **E** (parcial) | Web: `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy` no `hooks.server.ts`; **sign-out GET→POST** (fecha CSRF de logout, ganha a checagem de origem do SvelteKit). Cookie `secure` já é automático (default do SvelteKit fora de localhost). | `curl -D-` → 3 headers presentes; `GET /auth/sign-out` → **405**, `POST` → 303. |
| **F** | `overrides: { cookie: "^0.7.0" }` no `web/package.json` (o kit ainda fixa `^0.6`). | `npm audit` → **0 vulnerabilidades**; cookie 0.7.2. |
| **G** | `loadPings` removido do `+page.server.ts` (sobrou um `await` — o waterfall some junto com o Ping). | `GET /` (web) → **200**; `svelte-check` 0/0. |
| **H** | Moduledocs mentirosos corrigidos: `Clinic` (não provisiona schema, ADR-017) e `Directory` (`:attribute`, não `:context`). | Leitura. |
| **I** | `Api.web_app_url/0` como fonte única; removidas as 3 cópias (`AuthController`, `AuthStrategyController`, `Emails`). | Compila; 49 testes verdes. |
| **J** (parcial) | Testes novos: `rate_limit_auth_test` (causa A) e `professional_tenant_isolation_test` (isolamento por atributo). | Verdes. RLS-layer não testável no sandbox (conecta como `postgres`/BYPASSRLS) — provada na mão na rodada 2. |

**Auditoria do diff dos consertos (rodada 5):** a única superfície nova é o plug de rate limit
— chave ETS por termo (sem injeção), entradas expiram em 60s + `clean_period` de 1min (ETS não
cresce sem poda), enforcement só-prod. Nenhum endpoint novo; nenhuma rota de auth perdida na
divisão do scope (as 8 seguem sob `:authenticated`).

> Observado durante o conserto: o branch ganhou, em paralelo, um plug `VerifyTokenSubject`
> (binding jti↔sub) e vários testes novos + Vitest/Playwright no web. Não encostei nesse
> trabalho; os consertos convivem com ele (49 testes incluem os dois lados).

---

## 5. O que ficou para você (handoff)

> **Status pós-consertos:** **A, B, C, D, E (headers+sign-out), F, G, H, I e J corrigidos**
> (seção 4). Os itens A–J abaixo ficam como registro do que **era** o problema. Permanece
> **aberto**, e só:
>
> - **CSP** — ✅ **feito** na fatia de prod (`svelte.config.js` `kit.csp`, `mode: auto`);
>   provado no build (`content-security-policy: … script-src 'self' 'nonce-…'`). Ver
>   [docs/17](17-deploy-fly.md).
> - **Prod/deploy** — ✅ **feito** para o **Fly.io** (docs/17): `Dockerfile.prod` (release +
>   adapter-node), `fly.toml` (api/web), `Api.Release` (migrations + role restrito), TLS/HSTS na
>   edge do Fly. A API não é exposta ao browser exceto OAuth/WebSocket; o BFF fala com ela pela
>   rede privada.
> - **Rate limit por IP — ✅ fechado:** o BFF agora repassa o IP real do cliente
>   (`X-Forwarded-For` via `getClientAddress()`/`ADDRESS_HEADER=Fly-Client-IP`), e o plug lê
>   `Fly-Client-IP` (público, autoritativo do Fly) → `X-Forwarded-For` (interno, do BFF) →
>   `remote_ip`. O key por e-mail (5/min) barra bombardear um alvo; o por IP (20/min) barra um
>   IP disparando para muitos e-mails.
> - **Lição do smoke test:** o `scale` do Hammer é em **milissegundos**, não segundos — o plug
>   estava com janela de 60ms (o teste in-process passava por caber nela; só o `curl` no release
>   de prod, com latência de rede, expôs). Corrigido para `:timer.minutes(1)` e **provado no
>   release**: 6 pedidos do mesmo e-mail de 6 IPs → o 6º volta 429.
> - **Decisões suas, já tomadas:** magic link segue `require_interaction? false` (um clique a
>   mais não compensa); `professionals` **cascateia** ao apagar a clínica.

Ordem sugerida: **segurança → performance → refatoração**, causa antes de sintoma.

### A — Sem rate limiting (segurança) · estrutural
**O que é:** nenhum endpoint tem limiter; `/api/auth/magic-link` aceita flood (spam de e-mail
a endereços arbitrários + geração ilimitada de tokens).
**Sonda:**
```
req  1..15 -> HTTP 200   (POST /api/auth/magic-link, sem qualquer 429)
```
**Por que não foi corrigido:** a pedido; e é **estrutural** — exige um limiter (Hammer/
PlugAttack) e uma política de chave (por IP + por e-mail), infra que não existe no branch.
**Correção sugerida:** plug de rate limit nos endpoints de auth (janela curta por IP e por
e-mail), com resposta neutra ao estourar (não revelar existência de conta).

### B — `Api.Meta.Ping` público sem authorizer (segurança) · rápido, mas vira regra
**O que é:** `GET /api/json/pings` responde a **anônimo** com dados, e o domínio publica
`post :create` — **escrita anônima** na API. Causa: `Ping` sem `Ash.Policy.Authorizer`.
**Sonda:**
```
pings (json) sem cookie: HTTP 200
{"data":[{"attributes":{"message":"via movimento_app"},...,"type":"ping"}], ...}

# superfície pública inteira:
AshJsonApiRouter -> domains: [Api.Meta]
Api.Meta routes -> /pings: index :read, get :read, post :create
Ping: SEM policy  <-- exposto sem authorizer
```
(Não executei o `POST` — probe-safety; a exposição do create está provada pela config da rota +
ausência de authorizer.)
**Por que não foi corrigido:** a pedido.
**Correção sugerida:** decidir se `Ping` é scaffold descartável (remover recurso+rota antes de
prod) ou fica; se ficar, adicionar `authorizers: [Ash.Policy.Authorizer]` + policy explícita.
E **adotar a regra** "todo recurso roteado no AshJsonApi tem authorizer" — hoje o `Meta` é o
único domínio roteado e o buraco está nele.

### C — Índice ausente na coluna de tenant e em FK (performance) · rápido
**O que é:** `professionals.clinic_id` — a coluna que a RLS injeta em **toda** query da tabela
por-tenant — não tem índice; `user_identities.user_id` (FK) também não.
**Sonda:**
```
-- EXPLAIN como movimento_app, com GUC setada:
Seq Scan on professionals  (cost=0.00..25.00 rows=4 width=80)
  Filter: (clinic_id = (current_setting('movimento.clinic_id'::text, true))::uuid)

-- FKs sem índice de prefixo:
professionals   | clinic_id | tem_indice_prefixo = f
user_identities | user_id   | tem_indice_prefixo = f
```
(Hoje o planner escolhe seq scan porque a tabela tem 6 linhas — correto para o tamanho atual.
O achado é o **índice ausente na coluna de maior seletividade e presença**, que vira full scan
por query conforme a tabela cresce.)
**Correção sugerida:** `custom_indexes` no Ash — `index [:clinic_id]` em `Professional`,
`index [:user_id]` em `UserIdentity` — e `mix ash.codegen`.

### D — `on_delete` inconsistente (correção/performance) · baixo
**O que é:** filhos do mesmo pai divergem: `memberships.*` CASCADE, mas `professionals.clinic_id`
e `user_identities.user_id` são RESTRICT (sem `on_delete`). Efeito latente: apagar um `User`
com identidade Google fica **bloqueado** (as memberships somem em cascata, a identity trava o
delete); idem apagar `Clinic` com `Professional`.
**Sonda:**
```
memberships_user_id_fkey     ... REFERENCES users(id)   ON DELETE CASCADE
user_identities_user_id_fkey ... REFERENCES users(id)               (RESTRICT)
professionals_clinic_id_fkey ... REFERENCES clinics(id)             (RESTRICT)
```
**Correção sugerida:** decidir a semântica por relação (provável: `user_identities` cascade com
o user; `professionals` cascade/`nilify` com a clínica) e declarar em `references do`. Sem fluxo
de delete de user/clínica hoje, é dívida, não incidente.

### E — Hardening de produção pendente (segurança) · para antes de prod
**O que é:** (1) cookie de sessão sem `secure`; (2) sem CSP/HSTS/X-Frame no web nem headers de
segurança na API; (3) sign-out do web via `GET` (CSRF de logout, baixo).
**Sonda (leitura):** `endpoint.ex` `@session_options` só `same_site: "Lax"`; `hooks.server.ts`
sem CSP; `auth/sign-out/+server.ts` exporta `GET`.
**Por que não foi corrigido:** a pedido; e em dev (`http://localhost`) `secure: true` quebraria
o cookie. É trabalho de env de produção.
**Correção sugerida:** `secure: true` no cookie via runtime (só prod); `put_secure_browser_headers`
+ CSP no BFF; sign-out via `POST`/form action.

### F — Dependência com advisory low (segurança) · rápido
**Sonda:** `npm audit` → `cookie <0.7.0` (GHSA-pxg6-pf52-xh8x) via `@sveltejs/kit`; 3 low.
`mix hex.audit`: limpo.
**Correção sugerida:** subir `@sveltejs/kit` para a versão com `cookie ≥ 0.7`.

### G — Waterfall no BFF (performance) · rápido
**O que é:** `+page.server.ts` faz `await loadMe(event)` e só então `await loadPings(event)` —
duas idas independentes à API em série.
**Correção sugerida:** `Promise.all([loadMe, loadPings])`.

### H — Comentário contradiz o ADR-017 (refatoração) · trivial
**O que é:** `Api.Accounts.Clinic` @moduledoc afirma "provisiona o schema `tenant_<uuid>` via
`manage_tenant`" — ADR-017 trocou schema-por-tenant por tenancy de atributo; o comentário logo
abaixo (linhas 14-16) já diz o contrário. Comentário mentiroso.
**Correção sugerida:** reescrever o @moduledoc para o modelo por-atributo.

### I — DRY: `web_app_url` triplicado (refatoração) · trivial
**O que é:** `defp web_app_url, do: Application.get_env(:api, :web_app_url, "http://localhost:5173")`
idêntico em `AuthController`, `AuthStrategyController` e `Accounts.Emails`.
**Correção sugerida:** um único `Api.web_app_url/0` (ou config helper) consumido pelos três.

### J — Cobertura de testes parcial (refatoração/qualidade) · incremental
**O que é:** 2 arquivos de teste; `auth_flow_test` cobre magic link, sign-in, onboard→owner,
scope e `onboard` sem actor. **Sem teste:** RBAC de `Membership` (read/update/revoke),
`NotLastOwner`, `switch-tenant`, isolamento RLS cross-tenant, `HasClinicRole`.
**Correção sugerida:** um teste por política/invariante — em especial o cross-tenant (a RLS foi
provada na mão nesta auditoria; merece regressão automatizada).

### Estrutural / decisão de negócio (fora de fila)

- **Magic link com `require_interaction? false`** (GET consome o token): escolha deliberada do
  contrato (09 §8), mas expõe o link a *prefetch* de scanners de e-mail (SafeLinks etc.), que
  podem consumir o token antes do usuário. Se virar problema, a mitigação é uma página de
  interação (um clique) — o que o contrato hoje evita de propósito. Decisão de produto.
- **Porta da API publicada (`:4010`) alcançável direto** em dev: correto para o container; em
  prod, a API não deve ficar publicamente exposta (só o BFF/rede interna), senão a superfície
  direta (hoje o `pings`) fica na internet.

---

### Sondas usadas (para reproduzir)

- RLS de baixo: `psql -U movimento_app` + `set_config('movimento.clinic_id', <A>, true)` e
  tentativa de ler clínica B → 0 linhas (isolamento **confirmado funcionando**).
- Rate limit / enumeração: `curl` em `/api/auth/magic-link` (flood + timing existe×inexiste).
- Fronteira: `curl` sem cookie em `/api/auth/me`, `/switch-tenant`, `/realtime/token`,
  `/api/json/pings`, `/api/json/professionals`.
- Planos: `EXPLAIN` como `movimento_app`; `pg_indexes`, `pg_constraint`, `information_schema`.
- Deps: `mix hex.audit`, `npm audit`.
