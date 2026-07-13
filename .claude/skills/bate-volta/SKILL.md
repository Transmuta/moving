---
name: bate-volta
description: Use para auditar código recém-escrito (o diff da sessão ou de um branch) em 5 rodadas — duas de caça, duas de conserto e uma de verificação — provando cada achado contra a stack rodando (psql no container, mix test, curl na API, logs, Playwright no web) e entregando relatório do que ficou para decisão humana. Cobre segurança por classe de ataque, performance de query e indexação, e refatoração pelas rules do projeto com foco em DRY. Invoque quando pedirem revisão, auditoria, "passa o pente", ou antes de abrir PR de mudança não-trivial — em especial ao entregar uma feature nova.
compatibility: Claude Code ou qualquer agente compatível com Agent Skills, no monorepo Movimento (api/ Elixir/Ash/Phoenix + web/ SvelteKit) rodando 100% em container via docker compose, com o MCP do Playwright conectado.
metadata:
  version: "3.0.0"
  domain: "review"
  project: "movimento"
---

# Bate-volta

Auditoria em rodadas, contra a **stack rodando** — não contra a leitura do diff.

A diferença entre isto e uma revisão comum é uma só: aqui **nenhum achado existe sem o
output de uma sonda**. A app do Movimento sobe inteira em container (`docker compose up`:
`db` + `api` + `web`), então dá pra parar de supor e ir ver: `EXPLAIN (ANALYZE, BUFFERS)` de
verdade no plano da query via `psql`, o pipeline do `ApiWeb.Router` respondendo a um
`%Plug.Conn{}` forjado num `ConnCase`, a RLS bloqueando de fato quando você conecta como o
role restrito `movimento_app`, os `docker compose logs api` mostrando o que a app loga agora.

Não há Tidewave aqui. As sondas são o ferramental do próprio projeto — está tudo na seção
**As sondas deste projeto**, no fim deste arquivo.

## A forma

**Caça tudo primeiro. Só depois conserta.**

| Rodada | Fase | O que faz |
|---|---|---|
| **1** | Caça | Checklist: as três listas, item a item, contra o diff. |
| **2** | Caça | Adversarial: **sem** checklist, seguindo os fluxos reais. |
| — | **Consolidação** | Agrupa os achados por **causa-raiz** e prioriza. Não é rodada. |
| **3** | Conserto | Conserta, na ordem decidida. TDD: vermelho primeiro. |
| **4** | Conserto | Só se a 3 não deu conta. |
| **5** | Verificação | Re-sonda tudo **+ audita o diff dos consertos**. Não conserta. |

Nas rodadas 1 e 2 **você não encosta no código**. Auditar um alvo em movimento é o que faz a
varredura ficar rasa: cada conserto muda o que você já auditou, e você acaba reauditando seu
próprio código — que é justamente onde seu ponto cego está.

## Delegar às especialidades (opcional, recomendado)

Este repo tem subagentes especializados. Cada eixo de caça tem um dono natural — despache-os
**em paralelo** nas rodadas de caça, com o alvo delimitado e a ordem de **provar com sonda**:

- **Segurança** → `quality-specialist`
- **Performance / query / índice** → `data-engineer`
- **Refatoração / DRY / rules** → `test-engineer`

E nos consertos: backend Elixir/Ash → `backend-developer`; web SvelteKit → `frontend-developer`;
teste vermelho → `test-engineer`. A regra do achado não muda ao delegar: **sem output de sonda
colado, o achado não existe** — um subagente que devolve "considere revisar" devolve nada.

Rodar tudo no loop principal também é válido; a delegação é para ganhar profundidade e
paralelismo, não obrigação.

## Delimite o alvo

`git diff main...HEAD --stat` + `git status`. Só o que está aí é o alvo — auditoria que
escorrega pro código vizinho não termina nunca.

As sondas de container (`psql`, `mix test`, `iex`, `curl`, `logs`) **alcançam o `api/`**. O que
for `web/` você audita por leitura, `svelte-check` e o **Playwright MCP** (browser vivo em
`http://localhost:5173`) — e **diz** que a sonda de backend não era possível ali, em vez de
fingir que sondou. (Não há Vitest configurado no `web/`; o typecheck é `npm run check`.)

## Os três estados

Cada achado fecha em um destes, sempre com o **output da sonda colado**:

- **CONFIRMADO** — a sonda mostrou o problema.
- **REFUTADO** — a sonda mostrou o contrário. Siga.
- **NÃO SE APLICA** — não há superfície para isso neste diff. Uma linha dizendo por quê
  (ex.: "sem render de HTML dinâmico no diff") basta.

Sem output de sonda, o achado não existe. Proibido "pode ser que", "considere revisar",
"seria bom validar".

---

## Rodada 1 — caça por checklist

Passe as três listas, **nominalmente, item a item**. Não pule: um NÃO SE APLICA de uma linha é
resposta válida e rápida, e é o que prova que você passou por ali.

- Segurança → [references/seguranca.md](references/seguranca.md) — por classe de ataque.
- Performance → [references/performance.md](references/performance.md) — query e indexação.
- Refatoração → [references/refatoracao.md](references/refatoracao.md) — DRY primeiro, depois
  as rules do projeto (`.claude/rules/*` + CLAUDE.md).

Esta rodada garante **cobertura**. Ela acha o que está na lista.

## Rodada 2 — caça adversarial

**Feche as listas.** Passar a mesma checklist duas vezes no mesmo código não acha duas vezes
mais coisa — acha quase nada, e a rodada vira desperdício com cara de rigor. O que justifica
uma segunda caça é o **ângulo diferente**: a rodada 1 acha o que está na lista; esta acha o
que ninguém listou.

Em vez de conferir itens, **siga os fluxos de verdade e tente quebrá-los**:

- **Rode o fluxo e conte.** `docker compose logs api` durante um cadastro, um login por magic
  link, um switch-tenant. Quantas queries saem? O número cresce com o número de linhas?
- **Force a fronteira.** Monte o `%Plug.Conn{}` num `ConnCase` (ou dispare `curl` em
  `localhost:4010`) com o token de outra clínica, o `active_clinic_id` que não é seu, o ID que
  não é seu — e rode o pipeline do `ApiWeb.Router`. Veja o que sai do outro lado.
- **Prove a RLS de baixo.** Conecte no `psql` como `movimento_app` (NOBYPASSRLS), sete a GUC
  `movimento.clinic_id` para a clínica A e tente `SELECT` das linhas da clínica B. Zero linhas
  é a defesa funcionando; qualquer linha é CONFIRMADO.
- **Leia o plano, não o código.** `EXPLAIN (ANALYZE, BUFFERS)` nas queries que o fluxo emitiu
  de fato, e não só nas que você achou lendo o diff.
- **Reabra os REFUTADO fracos.** Um refutado por sonda rasa ("não achei chamada disso") não é
  o mesmo que um refutado por sonda que decidiu. Os primeiros voltam para a mesa.
- **Pergunte o que um atacante perguntaria.** Não "este campo é validado?", mas "o que eu
  ganho se eu mentir aqui?".

### Paradas antecipadas

- **A rodada 1 fechou sem nenhum CONFIRMADO?** Acabou. Escreva o relatório e pare — não há o
  que consertar, e uma segunda caça num diff limpo é trabalho procurando justificativa.
- **A rodada 2 não achou nada novo?** Ótimo sinal: a cobertura da 1 valeu. Vá direto para a
  consolidação.

---

## Consolidação — o passo que faz o resto valer

Não é rodada, é o que você faz com a lista completa na mão. É **por isso** que a caça vem toda
antes do conserto — e sem este passo, o modelo perde a razão de existir.

**1. Agrupe por causa-raiz.** Seis achados costumam ser duas causas. Um `clinic_id` vazando em
três serializers não é três achados: é um serializer-base sem a regra. Conserte a **causa**;
os sintomas caem juntos.

**2. Procure os achados que interagem.** Consertar A do jeito X pode ser errado sabendo que B
existe — e no meio de uma caça você ainda não sabia de B. Este é o ganho concreto de ter
esperado.

**3. Priorize e declare a ordem.** **Segurança → performance → refatoração**, e dentro de cada
eixo, causa antes de sintoma.

**4. Marque o que não vai ser consertado agora**, e por quê. Achado estrutural (a correção é
decisão de arquitetura) ou de custo de negócio (rate limit que exige infra que não existe)
**não entra na fila de conserto** — vai direto para o relatório de decisão humana. Melhor
reconhecer isso aqui do que descobrir na rodada 4, com meio patch escrito.

---

## Rodadas 3 e 4 — conserto

Só o que a consolidação pôs na fila, na ordem que ela decidiu.

**Teste vermelho primeiro** — o teste falha pela razão certa, e só então vem o código. Bug
encontrado aqui é bug como qualquer outro. No backend, `mix test` com `DataCase`/`ConnCase`;
no web, o fluxo no Playwright MCP. (A estratégia de testes do projeto está em
[docs/07-estrategia-de-testes.md](../../../docs/07-estrategia-de-testes.md) e as regras de
teste em [.claude/rules/usage_rules_elixir.md](../../rules/usage_rules_elixir.md).)

**A rodada 4 só existe se a 3 não deu conta** — um achado grande, um conserto que quebrou
teste alheio, uma causa-raiz que se abriu em mais trabalho do que parecia. Se a 3 fechou a
fila, pule direto para a 5. Rodada par não é cota.

**Se um conserto revelar um problema novo, anote e não conserte.** Ele é matéria da rodada 5,
que vai *sondá-lo* antes de qualquer um encostar nele. Consertar no impulso é como entra
correção sem teste vermelho.

---

## Rodada 5 — verificação

Duas tarefas. A segunda é a que quase todo modelo find-then-fix esquece.

**1. Re-sonde cada conserto** com a **mesma sonda que encontrou o achado**. O teste verde
prova a unidade; a sonda prova a app rodando. Quero os dois. E pergunte: o conserto
**regrediu** alguma coisa? O plano de query melhorou de fato, ou só mudou de forma?

**2. Audite o diff dos consertos.** As rodadas 3 e 4 escreveram **código novo — e código novo
é código não-auditado**. Ele nunca passou pelas listas. Passe agora, ao menos pelos itens que
a superfície nova acende: endpoint novo reabre a lista de fronteira da API; query nova pede
`EXPLAIN`; render novo acende XSS; migration nova pede conferir RLS + índice de FK. Vale também
reler os `NÃO SE APLICA` da rodada 1 que **deixaram de valer** por causa do conserto.

**A rodada 5 não conserta.** O que ela achar vai para o relatório, e a decisão é sua. Um
problema que aparece depois de duas rodadas de conserto raramente é descuido — é estrutural,
é briga entre correções, ou é escolha de negócio. Nenhuma dessas se resolve com uma sexta
volta do agente sozinho.

---

## As sondas deste projeto

A stack sobe com `docker compose up` (serviços `db`, `api`, `web`). Prefixe os comandos com
`docker compose exec <serviço>`. Portas no host: **api 4010**, **web 5173**, **db 5434**.

### Backend (`api/`) — a app viva

- **SQL de leitura / schema / plano** (equivale ao "execute_sql_query"):
  `docker compose exec db psql -U postgres -d movimento_dev -c "…"` — o `postgres` é o **dono**
  e **bypassa a RLS**; use-o para `EXPLAIN`, `information_schema`, `pg_indexes`, `pg_stat_*`.
- **Prova da RLS** (a sonda que só este projeto tem):
  `docker compose exec db psql -U movimento_app -d movimento_dev` — o role do app é
  **NOBYPASSRLS**. Dentro de uma transação, `SELECT set_config('movimento.clinic_id', '<A>', true);`
  e então tente ler linhas da clínica B. Zero linhas = RLS defendendo (ADR-018).
- **Forjar `%Plug.Conn{}` / rodar o Router**: escreva/rode um `ConnCase`
  (`docker compose exec api mix test test/…:LINHA`). É o jeito honesto de exercer o pipeline
  com header/token/tenant forjados.
- **Eval na app / contar comportamento**: `docker compose exec api iex -S mix` (ou
  `mix run -e "…"`) para chamar uma action com actor de A e id de B, inspecionar policies, etc.
- **Bater no endpoint real**: `curl -i http://localhost:4010/api/…` — a AshJsonApi está sob
  `/api/json` (pipeline `:authenticated`); health em `/api/health`.
- **Logs do que a app loga agora**: `docker compose logs api --tail=200` (ou `-f` durante o
  fluxo). É onde N+1 e vazamento em log aparecem de verdade.
- **E-mails transacionais** (magic link, convite): dev mailbox Swoosh em
  `http://localhost:4010/dev/mailbox` — veja o HTML renderizado e o que ele carrega na URL.

### Frontend (`web/`) — sem sonda de backend

- **Browser vivo**: Playwright MCP contra `http://localhost:5173` (navegar, snapshot,
  screenshot, network). É a sonda de fluxo real do web.
- **Typecheck**: `docker compose exec web npm run check` (`svelte-check`). Não há Vitest.
- O BFF do SvelteKit vive em `web/src/hooks.server.ts` e `web/src/lib/server/*` — auditoria
  por leitura, mais o que o Playwright/`curl` mostrarem na fronteira.

### Segurança do `psql` e do `iex` contra o banco de dev

- **Livre:** qualquer `SELECT`, `EXPLAIN` puro, `information_schema`, `pg_*`, `get`/`read` de
  action Ash, ler `docker compose logs`.
- **Avise antes, com o comando que vai rodar:** qualquer escrita — `DELETE`/`UPDATE`/`INSERT`,
  `Ash.destroy!`/`create!`, `Repo.delete_all`, migration, `mix ash.reset`, mutação de estado.
- `EXPLAIN ANALYZE` **executa** a query. Em `SELECT` é inofensivo; num `UPDATE`/`DELETE`, não —
  use `EXPLAIN` puro nesses casos.

---

## O relatório final

Entregue o relatório **no repositório**, como manda o CLAUDE.md: normalmente inline na sessão
para a decisão, e se for para persistir, um `.md` local (nunca cloud/Artifact).

**1. Onde parou, e por quê** — uma linha. "Parou na 1: a checklist não achou nada."

**2. A varredura** — tabela com os três eixos e o estado de cada item (CONFIRMADO / REFUTADO /
NÃO SE APLICA), das duas caças. Diga o que a rodada 2 achou que a 1 não tinha achado: é a
medida de quanto o ângulo adversarial pagou.

**3. As causas-raiz** — os achados agrupados como na consolidação, não a lista crua.

**4. O que foi corrigido** — por causa: a sonda que a encontrou, o teste que ficou vermelho, o
diff, e o output da **re-sonda** da rodada 5 provando o conserto na app rodando.

**5. O que ficou para você** — o que a consolidação marcou como estrutural/negócio, mais o que
a rodada 5 achou. Por item: **o que é**, **a sonda que prova**, **por que não foi corrigido**
(estrutural, briga entre correções, ou custo de negócio) e **qual seria a correção** — sem
aplicá-la. É um handoff, não um pedido de desculpas.

Sem seção de "sugestões gerais" no rodapé. O que não foi provado não entra no relatório.
