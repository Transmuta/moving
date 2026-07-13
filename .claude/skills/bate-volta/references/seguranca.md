# Segurança — por classe de ataque

Para cada item: **existe superfície nova no diff?** Se não, NÃO SE APLICA em uma linha. Se
sim, sonde e prove — com o output colado. As sondas estão na SKILL.md (seção "As sondas deste
projeto"): `psql` no `db`, `mix test`/`iex`/`curl` no `api`, Playwright no `web`.

## Fronteira da API

**Bypass do BFF / ataque direto na API**
O backend confia em algo que só o BFF do SvelteKit garante — cookie de sessão, origem, formato
do corpo? A porta do backend (`localhost:4010`) é alcançável sem passar pelo BFF (`web`, 5173)?
> Sonda: `docker compose exec api iex -S mix` e leia o bind do Endpoint
> (`Application.get_env(:api, ApiWeb.Endpoint)[:http]`). Bata direto com `curl -i
> http://localhost:4010/api/json/…` sem cookie e veja se a `:authenticated` barra.

**Tenant vindo do cliente** — regra dura (09 §8)
O `clinic_id` **nunca** vem do corpo, da query string ou de header do cliente. Ele é resolvido
no servidor pelo `ApiWeb.Plugs.LoadScope`, a partir do `active_clinic_id` da sessão + o
`Membership` ativo, e propagado como tenant do Ash. Um request que consegue **escolher** a
clínica pelo payload fura o modelo inteiro.
> Sonda: `ConnCase` forjando `params` com `clinic_id` de outra clínica; confirme que a action
> ignora o corpo e usa o tenant do escopo. Cruze com a leitura da action no resource.

**Broken Object Level Authorization (IDOR / BOLA)**
O actor da clínica A alcança um record da clínica B trocando o ID na URL? Aqui há **duas**
defesas que precisam ambas valer: a policy do Ash (actor) e a RLS por GUC (tenant). Uma não
cobre a outra.
> Sonda 1 (policy): `iex` chamando a action com `actor` de A e `id` de B — deve dar forbidden
> ou not-found, nunca o record.
> Sonda 2 (RLS, ADR-018): `psql -U movimento_app`, dentro de transação
> `SELECT set_config('movimento.clinic_id','<A>',true);` e então `SELECT` das linhas de B.
> **Zero linhas** é a defesa-em-profundidade funcionando; qualquer linha é CONFIRMADO.

**Broken Function Level Authorization**
Action sem policy, ou policy que passa por `authorize_if always()`. A regra do projeto
(`.claude/rules/ash.md`) é dura: authz vive em **policies**, nunca no controller. Lembre que
em policy Ash o **primeiro check que decide** manda — `authorize_if` em sequência é OR, não AND.
> Sonda: no `iex`, `Ash.Resource.Info.actions(Recurso)` + leitura do bloco `policies`; liste
> action ↔ policy. Toda action nova tem policy? Alguma virou permissiva sem querer por ordem
> de check?

**Mass assignment / over-posting**
`accept` amplo demais deixa o cliente escrever atributo que não devia: `role` de membership,
`clinic_id`, `confirmed_at`, campos de identidade. Em Ash, confira o `accept`/`argument` de
cada create/update novo.

**CORS / CSRF**
Cookie de sessão (`_api_key`, repassado pelo BFF) é `httpOnly` **e** `SameSite`? Há endpoint
que muta estado aceitando request cross-site? `Access-Control-Allow-Origin: *` combinado com
credencial é furo. As rotas de mutação (`switch-tenant`, `sign-out`) exigem verbo e proteção
adequados?

## Autenticação e credenciais

O Movimento é **passwordless** (ADR-015): Google OAuth + Magic Link, via AshAuthentication +
`UserIdentity`. Não há senha para vazar — mas os vetores mudam de lugar, não somem.

**Brute force / enumeração no request de magic link**
`POST /api/auth/magic-link` aceita e-mail. Tem rate limit/backoff, ou aceita tentativa
infinita? E a resposta é **igual** para e-mail que existe e que não existe — no corpo, no
status **e no tempo**? Vazar "esse e-mail tem conta" é enumeração de usuário. Ausência de
limiter no pipeline **é** o achado.
> Sonda: `curl` repetido em `localhost:4010/api/auth/magic-link` com e-mail conhecido e
> desconhecido; compare corpo, status e latência. `docker compose logs api` para ver o que
> loga em cada caso.

**Segurança do token de magic link / capability tokens**
Entropia suficiente, uso único, expira. E **não vaza**: em log, em `Referer`, em URL indexável.
O link chega por e-mail — confira o HTML no dev mailbox.
> Sonda: dispare o fluxo, abra `http://localhost:4010/dev/mailbox`, inspecione o token no
> link; tente **reusar** o mesmo token duas vezes e depois do prazo.

**OAuth (Google)**
O casamento da pessoa é pelo par `(iss, sub)`, não pelo e-mail (mais estável/seguro) — confira
que não regrediu para casar por e-mail (account takeover por e-mail não verificado). `state`
anti-CSRF presente no fluxo de authorize/callback?

**Sessão / revogação**
Token de sessão replayado depois do `sign-out` ainda entra? A troca de tenant
(`switch-tenant`) revalida o `Membership` ativo, ou confia no que o cliente mandou?

**Ataque de timing**
Comparação de token ou segredo com `==` em vez de `Plug.Crypto.secure_compare/2`.

## Injeção e renderização

**XSS** — stored, refletido e DOM-based
No SvelteKit o vetor é `{@html …}` com dado do usuário; `href`/`src` recebendo `javascript:`;
`bind`/atributo montado com entrada não-escapada. **Inclui os e-mails transacionais**
(`api/lib/api/accounts/emails.ex`): transacional é HTML e recebe dado do usuário — nome de
clínica, nome de membro e assunto são entrada renderizada.
> Sonda: grepe o diff do `web/` por `{@html`; para e-mail, injete `<script>`/`"><img>` no
> nome e veja o HTML no dev mailbox.

**SQL injection**
`Ecto.Adapters.SQL.query`, `fragment/1` com interpolação, qualquer SQL montado com `<>` ou
`#{}`. O Ecto/Ash protege por padrão — o furo mora exatamente onde alguém saiu dele (inclusive
no `set_config` da GUC, se algum dia receber valor não-validado).

**SSRF**
O servidor faz `Req`/`fetch` para uma URL que **veio da request**: avatar por URL, webhook,
callback. No BFF (`web/src/lib/server/*`) e em qualquer client Elixir do diff.

**Open redirect**
Parâmetro de destino (`?next=`, `?redirect=`, `?return_to=`) que aceita URL absoluta
(`https://evil.com`) ou protocol-relative (`//evil.com`) — tanto no callback de auth quanto no
BFF do SvelteKit.

**Path traversal**
`../` em nome de arquivo, upload, download, template.

## Exposição e infra

**Vazamento de `clinic_id`** — o identificador de tenant não é público
`clinic_id` é o tenant interno; ele **não** deve ser escolhido pelo cliente (ver "Tenant vindo
do cliente") nem vazar onde não precisa. Confira serializers, responses e logs no diff: o que
o cliente recebe é o necessário do escopo dele, não o mapa de tenancy.
> Sonda: grepe o diff por `clinic_id` em todo response/serializer/log; `curl` numa rota e veja
> o corpo devolvido.

**Vazamento em log / em erro**
`Logger` com token, PII (CPF, e-mail em claro onde não deve), ou o próprio token de magic link.
Stacktrace vazando em resposta. Args de job (se houver Oban) ficam em texto puro no Postgres.
> Sonda: `docker compose logs api --tail=200` durante o fluxo — leia o que a app loga de fato
> **agora**, não o que você acha que ela loga.

**Secrets em código**
Chave, token ou senha hardcoded no diff. Confira `api/lib/api/secrets.ex` e os `config/*.exs`:
segredo real deve vir de env/runtime, não do fonte.

**Headers de segurança**
CSP, HSTS, `X-Content-Type-Options`, `X-Frame-Options` — no Endpoint do Phoenix e no
`handle`/response do BFF SvelteKit.

**DoS**
Payload sem limite de tamanho. Paginação ausente numa listagem AshJsonApi. Amplificação: uma
request que dispara N queries ou N e-mails. ReDoS: regex com backtracking catastrófico sobre
entrada do usuário.

**Dependência vulnerável**
Se o diff tocou `mix.exs`/`mix.lock`: `docker compose exec api mix hex.audit`. Se tocou
`web/package.json`/`package-lock.json`: `docker compose exec web npm audit`.
