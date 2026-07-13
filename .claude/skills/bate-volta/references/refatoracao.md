# Refatoração — DRY primeiro, depois as rules do projeto

As "rules do projeto" aqui são concretas: os arquivos em [.claude/rules/](../../../rules/)
(`usage_rules_elixir.md`, `ash.md`, `ash_postgres.md`, `ash_phoenix.md`, `usage_rules_otp.md`)
mais o [CLAUDE.md](../../../../CLAUDE.md). Passe cada item **contra o diff**, não contra o
codebase inteiro.

## DRY

O critério não é "esses dois trechos parecem parecidos". É:

> **Existe uma segunda fonte da mesma verdade?**

Duplicação que dói não é a que se repete — é a que **diverge**, calada, meses depois, quando
alguém corrige um dos dois lados e não sabe do outro.

**Lógica duplicada entre módulos ou componentes**
Extraia para função/módulo compartilhado. É o caso fácil.

**Duas funções com o mesmo papel e contratos divergentes**
Dois parsers do mesmo formato, duas validações da mesma regra — e cada uma decidindo o caso de
borda do seu jeito. É o caso mais caro, e o mais fácil de não ver, porque os nomes são
diferentes. Sintoma: um docstring que afirma ser "o único lugar que faz X" enquanto outro
arquivo também faz X.

**Constante ou literal repetida**
Nome de cookie (`_api_key`), nome da GUC (`movimento.clinic_id`), rota, papel de membership,
código de erro — escrito à mão em mais de um lugar. Vira module attribute / constante única.

**Regra de negócio ou authz fora da Ash action / policy**
Se a regra vive na action **e** no controller, ou na action **e** no BFF do SvelteKit, já são
duas fontes da verdade — e a do front é a que vai ficar para trás. Regra de negócio vive em
**actions**; autorização vive em **policies** (`.claude/rules/ash.md`). O BFF orquestra e
apresenta; ele não é o dono da regra.

**Duplicação em teste**
Setup copiado entre testes. Extraia para `DataCase`/`ConnCase` ou um helper/generator nomeado
(`Ash.Generator`). Vale a mesma regra.

**Comentário que duplica — e contradiz — o código**
Comentário que descreve o passado como se fosse o presente. Um comentário mentiroso é
duplicação que apodreceu, e custa mais que a ausência dele. (Muitos comentários deste repo
carregam a proveniência — o ADR que motivou a linha; corrija o que ficou errado, não varra o
que ainda vale.)

## Elixir — `.claude/rules/usage_rules_elixir.md`, item a item contra o diff

**Pattern matching, não condicional**
- Prefira casar na **cabeça da função** a `if`/`else`/`case` no corpo.
- `%{}` casa **qualquer** mapa, não o vazio — use `map_size(m) == 0` para o vazio de verdade.
- Sem `case`/`if` aninhado: refatore para um único `with`, um `case`, ou funções separadas.

**Erros como valor**
- `{:ok, _}` / `{:error, _}` para o que pode falhar; `with` para encadear o happy-path.
- Não levante exceção para controle de fluxo. Não existe `return`/early-return em Elixir — a
  última expressão é o retorno.

**Armadilhas**
- **Nunca** `String.to_atom/1` em entrada de usuário (memory leak). Suspeito clássico em params
  de API e no BFF.
- Sem indexar lista com `lista[i]` — pattern match ou `Enum`.
- Prefira `Enum`/`Stream` a recursão na mão; `Stream` quando a coleção é grande.
- Sem process dictionary; sem macro a não ser que tenha sido pedido explicitamente.

**Design de função e nomes**
- Guard clauses: `when is_binary(name) and byte_size(name) > 0`.
- Nomes descritivos: `resolve_membership/2`, não `handle/2`. Heurística: prefira nome que dá
  **menos de 5 hits** no grep.
- Predicado termina em `?` e **não** começa com `is_` (`is_` é para guard).

**Dados**
- Struct quando a forma é conhecida; keyword list para opções; prepende com `[x | xs]`, não
  `xs ++ [x]`.

## Ash — `.claude/rules/ash.md` e `ash_postgres.md`

- Lógica de negócio e autorização em **actions** e **policies** — nunca em controller nem em
  changeset solto. Em policy, o **primeiro check que decide** manda (sequência de `authorize_if`
  é OR); para AND use `forbid_unless` + `authorize_if`.
- Chame ações por **code interface** no domain, não `Ash.get!`/`Ash.read!` cru no web.
- Prefira **calculations/aggregates** a query Ecto na mão; só desça pro Ecto quando não houver
  ação Ash que resolva.
- Multitenancy pelo mecanismo do Ash (`:context`/atributo `clinic_id`) — nunca isolamento na
  mão no controller. A RLS é **defesa-em-profundidade** (ADR-018), não a fonte da regra.
- Change/validation/preparation com lógica não-trivial vai em **módulo próprio**, não em função
  anônima inline.
- `actor` setado na query/changeset, **não** na chamada de `Ash.read!`/`Ash.create!`.

## OTP — `.claude/rules/usage_rules_otp.md`

- Estado de GenServer simples e serializável; trate todas as mensagens esperadas.
- `call` sobre `cast` quando em dúvida (back-pressure); timeout adequado.
- `Task.Supervisor` + `Task.async_stream/3` para concorrência com back-pressure.

## Frontend — `web/` (SvelteKit + Svelte 5)

Referência: [docs/03-frontend-sveltekit.md](../../../../docs/03-frontend-sveltekit.md) e o
design system em [.claude/rules/mcp.md](../../../rules/mcp.md) (assets do Figma, sem pacote de
ícone novo).

- TypeScript tipado de ponta a ponta; sem `any`; sem função pública sem tipo. `npm run check`
  (`svelte-check`) deve ficar limpo.
- Runes do Svelte 5 (`$state`/`$derived`/`$props`) idiomáticos; não reintroduzir padrão de
  store legado onde a rune resolve.
- Fronteira server/cliente respeitada: segredo e chamada à API server-to-server vivem no
  `+page.server.ts`/`hooks.server.ts`/`lib/server/*`, nunca no componente cliente.
- Dependências injetadas por prop/parâmetro, não por singleton global; lib de terceiro atrás de
  uma interface fina do projeto (`lib/server/api.ts` já é esse tipo de casca).

## Docs e saída — CLAUDE.md

- Toda documentação/relatório é **arquivo local no repo** (`docs/*.md`), seguindo a convenção
  existente. **Nunca** Artifact/cloud. Isso vale para o próprio relatório do bate-volta.
- Função nova ganha teste (F.I.R.S.T.); docstring em função pública com intenção + exemplo
  (doctest no back).
