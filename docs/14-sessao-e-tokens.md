# Sessão e tokens — ciclo de vida, segurança e modelo de ameaça

Como uma sessão nasce, trafega e morre no Movimento: quais tokens existem, onde ficam
armazenados, o vai-e-vem entre o browser, o BFF (SvelteKit) e a API (Phoenix/Ash), o que é
verificado a cada request, e o que acontece — com exercício de ameaça e mitigações — se a
`token_signing_secret` vazar.

Contexto: autenticação **sem senha** ([ADR-015](00-decisoes.md#adr-015--autenticação-por-google-oauth--magic-link-sem-senha)),
identidade global multi-tenant ([ADR-014](00-decisoes.md#adr-014--identidade-global-multi-tenant-modelo-vercel)),
o browser só fala com o **BFF** ([ADR-005](00-decisoes.md#adr-005--sveltekit-como-bff-nunca-como-cliente-de-banco)),
e RLS como defesa-em-profundidade ([ADR-018](00-decisoes.md#adr-018--rls-como-defesa-em-profundidade-da-tenancy-por-atributo)).
Tudo aqui foi verificado contra o código do AshAuthentication 4.14 e a stack rodando.

---

## 1. Os tokens em jogo

São quatro, com papéis distintos. Os defaults saem do AshAuthentication e da nossa config.

| Token | Vida | Uso | Assinatura | Único uso? |
|---|---|---|---|---|
| **Magic link** | **10 min** | provar posse do e-mail (login/registro) | JWT HS256 (`token_signing_secret`) | sim |
| **Sessão** (JWT) | **14 dias** | autenticar cada request | JWT HS256 (`token_signing_secret`) | não |
| **Remember-me** | 30 dias | re-emitir sessão | JWT | **instalado mas inativo** (§6) |
| **Realtime (WS)** | **15 min** | `join` do Phoenix Channel | `Phoenix.Token` (`secret_key_base`) | não |

- Magic link e sessão usam a **mesma** secret de assinatura (`token_signing_secret`), via
  [`Api.Secrets`](../api/lib/api/secrets.ex). O realtime usa o `secret_key_base` do endpoint
  (segredo **separado**), em [`AuthController.realtime_token`](../api/lib/api_web/controllers/auth_controller.ex).
- As vidas: magic link `{10, :minutes}` e remember-me `{30, :days}` são defaults da lib;
  a sessão é o `@default_token_lifetime_days = 14`; o realtime é `@realtime_max_age = 900`.

## 2. Onde cada coisa é armazenada

- **Cookie `_api_key`** (a sessão): cookie de sessão do Phoenix (`store: :cookie`),
  **assinado** com o `secret_key_base` (íntegro, não-adulterável), `HttpOnly` + `SameSite=Lax`.
  Como configuramos `require_token_presence_for_authentication? true` em
  [`User`](../api/lib/api/accounts/user.ex), o que vai **dentro** do cookie é o **JWT inteiro**
  (sob a chave de sessão `user_token`). Ou seja: cookie assinado *contendo* um JWT assinado —
  dupla integridade.
- **Tabela `tokens`** (Postgres, [`Api.Accounts.Token`](../api/lib/api/accounts/token.ex)): com
  `store_all_tokens? true`, todo token emitido grava `jti` + `subject` + `expires_at` + `purpose`.
  É o que permite **revogar do servidor**.
- **Tabela `user_identities`**: o `access_token`/`refresh_token` do **Google** ficam aqui —
  são para chamar APIs do Google, **não** para a nossa sessão (hoje lemos e-mail+nome uma vez
  no login e não usamos mais).
- **No JavaScript do browser: nada.** O `_api_key` é `HttpOnly` (JS não lê). O único token que
  chega ao JS é o **efêmero de WebSocket** (15 min).

## 3. O vai-e-vem (browser ↔ BFF ↔ API)

```
① login  → API emite JWT(14d), grava jti na tabela tokens, coloca o JWT na sessão
           → Set-Cookie _api_key (assinado com secret_key_base)
② BFF    → captura esse Set-Cookie e RE-EMITE _api_key no domínio do web (reemitSession).
           O web é só um "carteiro": não assina nada, carrega o cookie opaco da API.
③ browser→ guarda _api_key só para o domínio do web. Nunca vê o JWT cru; nunca fala com a API.
④ request autenticada:
     browser --_api_key--> BFF --forward Cookie: _api_key--> API
   a API verifica a assinatura do cookie → extrai o JWT → verifica o JWT → carrega o User
⑤ realtime: BFF pede GET /api/realtime/token (repassando o cookie) → recebe token de 15 min
   → entrega ao JS → WebSocket direto no Phoenix (exceção ao BFF, como o OAuth)
```

O repasse do cookie do BFF para a API é o [`apiFetch`](../web/src/lib/server/api.ts); a
re-emissão no domínio do web é o `reemitSession` no mesmo arquivo, usado pelos callbacks de
[magic link](../web/src/routes/auth/callback/+server.ts) e Google. O **único token no cliente**
é o de WebSocket; todo o resto é o cookie `HttpOnly`, manuseado só pelo BFF.

## 4. O que a API valida em CADA request autenticada

Pipeline `:authenticated` do [router](../api/lib/api_web/router.ex): `:fetch_session` →
`:load_from_session` → `VerifyTokenSubject` → `LoadScope`.

1. **Assinatura do cookie** (Phoenix, `secret_key_base`).
2. **Assinatura do JWT** (HS256, `token_signing_secret`) + `exp`/`nbf`/`iss`/`aud`.
3. **`jti` não revogado** (`validate_jti` → `valid_jti?` na tabela `tokens`).
4. **Presença do `jti`** (allowlist): `get_token(jti, purpose: "user")` — o token precisa
   **existir** na tabela. Sem isso, revogar = apagar/revogar a linha e a sessão morre.
5. **Binding `jti`↔`sub`** ([`VerifyTokenSubject`](../api/lib/api_web/plugs/verify_token_subject.ex)):
   o `subject` guardado daquele `jti` tem que ser **exatamente** o `sub` do JWT (ver §7).
6. `subject_to_user(sub)` → carrega o `User` do Postgres → `current_user`.
7. [`LoadScope`](../api/lib/api_web/plugs/load_scope.ex) resolve o `Membership` ativo → monta o
   `Api.Scope` (`user + clinic_id + papel + professional_id`) e seta `actor`/`tenant` do Ash.

## 5. Como o app pega o usuário logado

O front **não decodifica nada** — ele pergunta. O BFF chama `GET /api/auth/me` repassando o
cookie; a API roda o pipeline acima e o [`me/2`](../api/lib/api_web/controllers/auth_controller.ex)
devolve `user + active_clinic_id + papel + professional_id + memberships`.

Ponto-chave: **o JWT carrega só o `sub`** (um ponteiro de identidade, tipo `user?id=<uuid>`),
nunca o perfil. Os dados vêm sempre frescos do banco. Dentro do Ash, "o usuário logado" é o
**actor** (`actor(:id)` nas policies).

## 6. Expiração e refresh — tem refresh token?

**Refresh clássico (OAuth): não.** A sessão é o JWT de 14 dias; ao expirar, re-autentica
(novo magic link / Google — barato, é um clique, não um "resete de senha").

- O **remember-me (30d)** está *instalado* (o installer adicionou a estratégia e o
  `sign_in_with_magic_link` aceita o argumento), mas **não está ativo**: os controllers não
  passam `remember_me: true` nem o BFF trata o cookie. Ligá-lo é o caminho para "manter
  conectado" além dos 14 dias.
- O **`refresh_token` do Google** é guardado em `user_identities` mas não é usado para a nossa
  sessão.
- O `maxAge` do cookie no web é **alinhado a 14 dias** (o `token_lifetime` do JWT) para não
  haver "logout súbito" (cookie vivo com JWT já expirado).

## 7. Modelo de ameaça — vazamento da `token_signing_secret`

HS256 é **simétrico**: a mesma secret assina e verifica. De posse dela, o atacante assina
JWTs que passam na verificação de assinatura. A tentativa óbvia: forjar um JWT de sessão com
o `sub` da vítima. Duas barreiras além da assinatura contêm isso:

| Barreira | O que exige a mais | Efeito |
|---|---|---|
| **Envelope do cookie** | o JWT trafega **dentro** do cookie assinado com o **`secret_key_base`** (segredo *separado*); só aceitamos sessão, **não** `Bearer` | sem o `secret_key_base` o atacante não consegue **entregar** o JWT forjado |
| **Presença do `jti`** | `require_token_presence` + `store_all_tokens`: o `jti` precisa **existir** na tabela | JWT forjado do nada (jti aleatório) → **rejeitado** |

Raio de dano por cenário:

- **Só o `token_signing_secret`**: praticamente inócuo — falta o `secret_key_base` (envelope) e
  um `jti` real (presença).
- **`token_signing_secret` + `secret_key_base`** (vazamento de config típico): forjam o envelope
  com um JWT arbitrário — mas o `jti` forjado não está na tabela.
- **O ataque sutil (jti/sub confusion):** o atacante, sendo um usuário legítimo qualquer, tem
  **um `jti` válido (o dele)**. Forja `{ jti = o meu, sub = da vítima }`. A presença olhava só
  o `jti` — que existe — e o `subject_to_user` confiava no `sub` do JWT. **Sem o binding do §4.5,
  isso carregaria a vítima.** Foi o buraco fechado pelo `VerifyTokenSubject` (compara o `subject`
  guardado do `jti` com o `sub` apresentado; mismatch → 401 + alerta, que também vira sinal de
  intrusão altíssimo).
- **+ acesso de escrita ao banco**: inserem a linha `tokens` e forjam qualquer um → *game over*,
  mas é comprometimento composto, muito além de "só a secret".

Observação de defesa-em-profundidade: mesmo uma sessão forjada de um usuário X fica presa às
clínicas de X (memberships + RLS, [ADR-018](00-decisoes.md#adr-018--rls-como-defesa-em-profundidade-da-tenancy-por-atributo)).
O **tenant boundary reduz-se ao identity boundary** — não há escalada lateral além do que a
vítima já acessa. O `tenant_id` **não está no token**: vem do `active_clinic_id` da sessão,
validado contra os memberships pelo `LoadScope`.

## 8. Mitigações

### 8.1 Implementadas

- **Binding `jti`↔`sub`** (`VerifyTokenSubject`) — fecha a jti/sub confusion. Provado por teste
  (forja `{jti_A + sub_B}` → 401) e ao vivo (sessão legítima passa).
- **Sign-out revoga o token no servidor** (`revoke_session_tokens`) — mesmo um cookie capturado
  deixa de valer. Provado ao vivo: o mesmo cookie cai para 401 após o sign-out.
- **`maxAge` ↔ `exp`** alinhados (14 dias).
- **`Secure`** no cookie: o SvelteKit ativa automático fora de `localhost` (o cookie que chega
  ao browser é o re-emitido pelo web).
- Segredos **separados** (`token_signing_secret` ≠ `secret_key_base`) e `redact_sensitive_values_in_errors?`.

### 8.2 Operacional — proteger e rotacionar a secret

A secret já vem de env (`Api.Secrets` ← `Application` ← `TOKEN_SIGNING_SECRET` no
[runtime.exs](../api/config/runtime.exs)). No deploy (Fly.io, [ADR-008](00-decisoes.md#adr-008--deploy-em-flyio-observabilidade-via-opentelemetry-sem-vendor-lock)):

```bash
mix phx.gen.secret                          # gerar
fly secrets set TOKEN_SIGNING_SECRET=<novo> # dispara rolling deploy → runtime.exs recarrega
```

Rotacionar é **corte seco** (a lib usa uma única `signing_secret`): todo JWT antigo para de
verificar → todos re-autenticam. É o que se quer num **incidente**; para rotação de rotina, o
passwordless torna o re-login barato (opção recomendada) — verificação com 2 chaves (aceitar
`atual`+`anterior`) exigiria um plug custom e não se paga. Rotacionar também em: suspeita de
vazamento, offboarding de acesso a prod, e num calendário.

### 8.3 Arquitetural — assimétrico + signer isolado

Trocar para `signing_algorithm "EdDSA"`/`"RS256"` é um toggle, **mas não ajuda no monólito**:
o `token_signer` usa a mesma chave para assinar e verificar, e a nossa API **emite** tokens →
precisa da chave privada na mesma caixa. O ganho só aparece **separando o emissor do
verificador**: um serviço/KMS guarda a privada e assina; a API principal só tem a pública e só
verifica → vazar a config da API não dá poder de forjar. É evolução para quando/se o auth virar
serviço próprio.

## 9. Dívidas e pendências

- **Remember-me** desligado — ligar quando quisermos "manter conectado" > 14 dias.
- **Rotação (§8.2)** — executar no deploy (Fly secrets + este runbook).
- **`force_ssl`/`Secure` no endpoint da API** — para o cookie interno API↔BFF em prod (o
  browser-facing já está coberto pelo SvelteKit).
- **Assimétrico + signer isolado (§8.3)** — só com serviço de auth separado.
