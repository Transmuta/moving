# Performance — query e indexação

**Meça, não estime.** As sondas do projeto pagam o próprio preço aqui:
`docker compose exec db psql -U postgres -d movimento_dev` roda `EXPLAIN (ANALYZE, BUFFERS)`
de verdade, e `docker compose exec api mix ...` / `docker compose logs api` mostram as queries
que a app emite agora. Um plano de query colado vale mais que qualquer parágrafo de suspeita.

## Query

**N+1** — a query dentro do loop
Em Ash: `load` faltando, relacionamento acessado item a item, `calculation` que faz I/O por
linha.
> Sonda: `docker compose logs api -f` durante o fluxo e **conte** as queries. Se o número
> cresce com o número de linhas, é N+1. Esse é o teste — não "parece um N+1".

**Seq scan onde devia haver índice**
Rode `EXPLAIN (ANALYZE, BUFFERS)` em **toda query nova ou alterada** do diff. Cole o plano.
`Seq Scan` em tabela que cresce é CONFIRMADO. (Em tabela de 12 linhas o Postgres escolhe seq
scan de propósito e está certo — considere o tamanho projetado, não o atual.)
> Nota RLS: a RLS por GUC (ADR-018) adiciona um predicado `clinic_id = current_setting(...)` a
> toda query do tenant. Rode o `EXPLAIN` **como `movimento_app`** para ver o plano real, com o
> filtro da policy; o plano como `postgres` (bypass) mente sobre o que a app vive.

**Query sem `LIMIT` / paginação ausente**
Listagem AshJsonApi que devolve a tabela inteira. Cresce em silêncio até o dia em que não
cresce mais. Confira se os `read` novos têm paginação.

**`SELECT *` desnecessário**
Carregar coluna pesada (texto grande, JSON, binário) que a resposta descarta. Prefira `load`
com `strict?`/seleção enxuta.

**Aggregate / calculation caro**
`aggregate` do Ash que vira subquery correlacionada por linha; `calculation` que faz I/O.
Prefira `aggregate`/`calculation` a Ecto na mão (`.claude/rules/ash.md`) — mas confira o SQL
que sai, via `EXPLAIN`.

## Indexação

**Índice faltando em FK**
O Postgres **não** indexa foreign key automaticamente — só a PK. Toda FK nova no diff (incluindo
`clinic_id`, `user_id`, `membership_id` etc.) tem índice? Sem ele, o `DELETE` no pai vira seq
scan no filho, e o join fica caro. Em recurso multitenant, `clinic_id` entra em quase todo
predicado — índice nele (ou composto começando por ele) raramente é opcional.
> Sonda: `psql` cruzando `information_schema.table_constraints` (tipo `FOREIGN KEY`) com
> `pg_indexes`. Confira também o que o `mix ash.codegen` gerou na migration do diff.

**Índice faltando no predicado de filtro**
As colunas que aparecem em `WHERE` e `ORDER BY` das queries novas estão cobertas?
- **Composto**: a ordem importa — a de igualdade/mais seletiva primeiro (`clinic_id`), a de
  range por último.
- **Parcial**: quando o predicado é seletivo e estável (`WHERE deleted_at IS NULL`,
  `WHERE confirmed_at IS NULL`), o índice parcial é uma fração do tamanho.

**Índice redundante ou não usado**
Índice novo que duplica o prefixo de outro já existente (um índice em `(clinic_id, x)` já serve
consultas por `clinic_id`). Índice com `idx_scan = 0` é custo de escrita puro.
> Sonda: `psql` em `pg_stat_user_indexes` e `pg_indexes`.

## Concorrência e recursos

**Pool de conexões**
Trabalho concorrente novo — worker, `Task.async_stream` — segurando conexão do Repo durante
I/O externo. Confronte a concorrência declarada com `Api.Repo.config()[:pool_size]` (via
`iex`). Uma fila de 10 tarefas contra um pool de 10 deixa a web esperando por conexão, e isso
aparece como **latência de API**, não como problema do worker — o que torna caro de diagnosticar.

**Transação longa segurando a GUC**
Lembre que o Movimento **abre uma transação por ação** para escopar a GUC da RLS (ADR-018). Uma
chamada HTTP externa **dentro** dessa transação segura conexão e locks pelo tempo da rede
alheia — pior aqui do que no normal, porque a transação existe por design. I/O externo vai em
`before_transaction`/`after_transaction`, não no meio da ação.

**Crescimento sem poda**
Tabela nova escrita a cada request ou job (evento, log de auditoria, tokens) sem política de
expurgo. Token de auth expirado que nunca é limpo é crescimento silencioso.

## Front (`web/` — SvelteKit, sem sonda de backend)

- Waterfall de `fetch` em série no `load` onde caberia paralelo (`Promise.all`).
- Trabalho que deveria estar no `+page.server.ts` (server `load`, no BFF) escorregando para o
  cliente — ou o inverso, dado sensível indo ao cliente à toa.
- `hooks.server.ts` (`handle`) rodando lógica cara em request que não precisa dela.
- Bundle inflado por importar a lib inteira em vez do símbolo (`@lucide/svelte`, etc.).
> Sonda: Playwright MCP em `localhost:5173` — aba de network para ver waterfall e payloads;
> `docker compose exec web npm run check` para o typecheck.
