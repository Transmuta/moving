# Testes: TDD e gate de cobertura

Regra própria do projeto (não é usage_rules de pacote). Vale para `api/` e `web/`.

## TDD é o método padrão

Escreva o teste **antes** do código de produção: red → green → refactor.

- Vale principalmente para **lógica de domínio, regras de negócio, policies/autorização e correção de bug** (todo bug vira primeiro um teste que falha, reproduzindo-o).
- Exploração/spike sem teste é permitido enquanto é rascunho, mas **o commit que entra na branch já vem com teste**. Não existe "depois eu cubro".
- TDD aqui é convenção, não algo que ferramenta força — o backstop automático é o gate de cobertura abaixo.
- Prefira as versões `!` do Ash e teste as ações pela code interface do domínio (ver `.claude/rules/ash.md`).

## Gate de cobertura (o CI aplica, o build quebra)

Existe um piso de cobertura que o CI verifica e **falha o build** abaixo dele. A **fonte de verdade dos números** é o código, não esta prosa (para não desatualizar):

- **Backend:** [`api/coveralls.json`](../../api/coveralls.json) (`minimum_coverage`), rodado por `mix coveralls`.
- **Web:** [`web/vite.config.ts`](../../web/vite.config.ts) (`test.coverage.thresholds`), rodado por `npm run coverage`.
- **CI:** [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) roda os dois e é o gate real.

Regras sobre o gate:

- Cobertura é **piso, não meta**. Passar do mínimo não significa "testado o suficiente" — julgue os caminhos de fato exercitados.
- **Nunca baixe o threshold nem adicione arquivo à ignore-list só para o gate passar.** Se um mínimo precisar mudar, é **decisão humana explícita**, com justificativa — não um atalho para verde.
- Ignore da cobertura (`skip_files` no backend, `exclude` no web) é para superfícies sem lógica a testar; não para esconder código não coberto.

### Rodar localmente antes de abrir PR

```bash
# backend (dentro do container / api/)
mix coveralls          # suíte + gate; falha abaixo do mínimo

# web (web/)
npm run coverage       # Vitest + thresholds
```

## Referências

- `docs/07-estrategia-de-testes.md` — estratégia geral / pirâmide
- `docs/15-gate-de-cobertura-e-ci.md` — o gate e o CI
- `docs/16-testes-frontend.md` — pirâmide do `web/` (BFF)
