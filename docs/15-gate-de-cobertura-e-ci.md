# Gate de cobertura e CI

Como a garantia de "nenhuma mudança quebra o que já está pronto" deixou de depender de
disciplina manual e passou a ser **mecânica**. Este documento é o par de execução da
[07-estrategia-de-testes.md](07-estrategia-de-testes.md): o 07 diz *o que* testar (os
motores de regra, com o protótipo como oráculo); este diz *o que trava o merge* hoje.

## Ponto de partida (o que a auditoria encontrou)

O padrão ">80% de cobertura, >90% em regra de negócio, TDD" existia só como **texto de
persona** nos agentes (`.claude/agents/*.md` — "100% Coverage Or Death" etc.). Isso é
instrução de comportamento do agente, **não** um gate. Na prática, antes desta fatia:

- nenhuma ferramenta de cobertura instalada (sem `excoveralls`);
- nenhum CI — zero workflows; nada rodava os testes antes de um merge;
- 9 testes, cobrindo só parte da fundação de auth;
- superfícies **críticas de segurança em 0%**: o check de RBAC (`HasClinicRole`), o plug
  de sessão (`LoadScope`), os controllers de auth (`AuthController`, `AuthStrategyController`)
  e o mapeador do Google (`SetFromGoogleUserInfo`).

## O que passou a existir

### 1. Ferramenta — ExCoveralls

- `{:excoveralls, "~> 0.18", only: :test}` em [`api/mix.exs`](../api/mix.exs), com
  `test_coverage: [tool: ExCoveralls]`.
- [`api/coveralls.json`](../api/coveralls.json) define o **`minimum_coverage: 80`** e
  ignora só glue de framework genuinamente sem valor de teste unitário
  (`endpoint.ex`, `telemetry.ex`, `gettext.ex`). Nenhuma lógica de negócio é pulada —
  código não coberto **conta contra** o número, de propósito.
- `mix coveralls` roda a suíte e **sai com erro** abaixo de 80%. É o comando do gate.

> **Nota sobre o número.** O ExCoveralls mede linhas *executáveis relevantes* e ignora o
> DSL declarativo do Ash (um recurso todo em `attributes`/`actions`/`policies` tem 0
> linhas relevantes). Por isso o total (82,6%) é muito mais alto e mais honesto que o
> `mix test --cover` embutido (~34%), que conta cada linha de macro.

### 2. Backfill das superfícies de segurança (0% → coberto)

| Módulo | Antes | Agora | Teste |
|---|---|---|---|
| `Api.Accounts.Checks.HasClinicRole` (RBAC) | 0% | 87,5% | `test/api/accounts/checks/has_clinic_role_test.exs` |
| `ApiWeb.Plugs.LoadScope` (sessão→tenant) | 0% | 100% | `test/api_web/plugs/load_scope_test.exs` |
| `ApiWeb.AuthController` | 0% | ~90% | `test/api_web/controllers/auth_controller_test.exs` |
| `ApiWeb.AuthStrategyController` (OAuth) | 0% | 100% | `test/api_web/controllers/auth_strategy_controller_test.exs` |
| `...Changes.SetFromGoogleUserInfo` | 0% | 100% | `test/api/accounts/user/changes/set_from_google_user_info_test.exs` |

Os testes provam **comportamento de segurança**, não linhas: RBAC nega não-membro / papel
errado / vínculo apenas pendente / actor anônimo; a resolução de tenant nunca vem do
corpo/URL; o magic link responde de forma **neutra** (não revela se a conta existe);
`switch-tenant` só troca com vínculo ativo; o token de realtime carrega `user_id`+`clinic_id`;
o sign-out revoga o token.

Total da suíte: **45 testes, 0 falhas, 82,6%**.

### 3. CI — GitHub Actions ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml))

Roda em todo push para `main` e em todo PR. Dois jobs:

- **API** (Elixir 1.18.4 / OTP 27, Postgres 16 de serviço): `mix format --check-formatted`
  → `mix compile --warnings-as-errors` → `mix ash.setup` → **`mix coveralls`** (falha < 80%).
- **Web** (Node 22): `npm ci` → `npm run check` (svelte-check) → `npm run build`.

## Achados registrados para decisão humana (não corrigidos aqui)

O backfill revelou dois pontos que **não** são bug de teste — são comportamento do código
que merece decisão:

1. **`Membership.invite` não convida outro usuário por `user_id` com autorização ligada.**
   O `manage_relationship(:user_id, :user, :append)` faz um lookup autorizado do User, e a
   policy do User é `id == actor.id` — então o convidante não "enxerga" o convidado e a ação
   falha com `NotFound`. Hoje o convite só passa com `authorize?: false`. Provável correção:
   convidar por **e-mail** (upsert/lookup sem depender de enxergar o outro User) ou um lookup
   de sistema dedicado. (Os testes de RBAC contornam validando a *decisão* via
   `can_invite_member?`.)
2. **`magic_link_callback` com token inválido responde `401` com header `Location`.** O
   `put_status(:unauthorized)` sobrepõe o `302` do `redirect`, então o browser não segue o
   redirecionamento. Se a intenção é mandar o usuário de volta ao login, deveria ser `302`.

## O alvo e o caminho (ratchet)

- **Piso hoje: 80% global.** É o mínimo que trava o merge. Sobe conforme a cobertura real
  crescer — a regra é **nunca baixar o número**.
- **Regra de negócio > 90%** (07 §2): ainda não vale porque os motores (`scheduling`,
  `waitlist`, `packages`) não foram portados. Quando cada motor entrar, ele vem com sua
  tabela-verdade table-driven + property-based (o protótipo é o oráculo), o que naturalmente
  o leva a ~100% e puxa o piso global para cima. **Nesse momento, subir o `minimum_coverage`.**
- **Frontend** ainda sem test runner (Vitest/Playwright) — o job web só faz `check`+`build`.
  É o próximo passo da rede de segurança (07 §7).
