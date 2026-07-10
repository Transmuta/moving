# Estratégia de Testes

Como provamos que o port do protótipo para produção preserva as regras, e como impedimos que
uma alteração futura as quebre em silêncio. As decisões que enquadram este documento estão em
[00-decisoes.md](00-decisoes.md); a arquitetura que estamos testando, em [04-arquitetura.md](04-arquitetura.md).

> **Nota de verificação.** Este documento passou por reparo crítico de proveniência. **Cada** citação
> de linha do protótipo (`interface/Movimento.dc.html`) abaixo foi re-derivada do zero — localizada com
> `grep -n`, confirmada com `sed -n 'Np'` — antes de ser escrita. A auditoria anterior encontrou 19 de
> 41 citações falsas (números escritos de memória); o registro do que mudou está na
> [seção final](#correções-desta-revisão). Snippets de API de bibliotecas que ainda não podem ser
> confirmados contra o hexdocs (não há projeto Elixir neste repo ainda) estão marcados com
> `# NAO-VERIFICADO`.

O ponto de partida é uma sorte que a maioria dos projetos não tem: o protótipo
(`interface/Movimento.dc.html`) contém motores de regra **puros e determinísticos** e o
tempo já vem congelado (`hoje()` retorna a string `'2026-06-25'` em [`:1098`](../interface/Movimento.dc.html#L1098)).
Isso significa que cada motor já é, hoje, um oráculo executável: dá para rodar a função original no
navegador com uma entrada e anotar a saída exata, e essa saída vira o caso de teste do código
Elixir/Svelte. Não estamos escrevendo testes a partir de uma especificação em prosa que pode estar
errada; estamos escrevendo testes contra uma implementação de referência que roda.

> **Nota de proveniência.** A [ADR-001](00-decisoes.md) falava em "86 screenshots"; o diretório
> `interface/screenshots/` tem, na verdade, **79 arquivos PNG** (verificado por `ls | wc -l`). A
> [§7](#7-front-vitest-playwright-e-a-verdade-sobre-os-screenshots) trata o baseline visual com esse
> número real. (00-decisoes.md já foi corrigido; registramos aqui por completude.)

---

## 1. A pirâmide, nos dois runtimes

Temos dois runtimes independentes (Elixir/Ash e SvelteKit/Svelte) e um contrato de rede entre eles.
A pirâmide não é uma só; são duas, com uma faixa de contrato costurando as pontas.

```
                        ▲  e2e (Playwright, poucos, caros)
                       ╱ ╲    fluxos completos no navegador contra a stack real
                      ╱   ╲
                     ╱─────╲  contrato (BFF ↔ API): schema JSON:API + casos-espelho
                    ╱       ╲
                   ╱ integr. ╲  Elixir: ExUnit + AshPostgres (banco real, sandbox)
                  ╱  (Ash)    ╲   policies, exclusion constraints, tenancy, notifiers
                 ╱─────────────╲
                ╱   unitário     ╲  os motores puros — a base larga, barata, exaustiva
               ╱  (ExUnit+Vitest) ╲   dayPeriods, futureConflicts, filaVagas, computeSerie,
              ╱___________________ ╲   wouldConsume, apptPkg · layoutAppts (só Vitest, é cliente)
```

**O que é unitário puro.** Tudo que não toca banco, rede nem relógio do sistema. Os motores do
servidor (`Movimento.Scheduling.Availability`, `Movimento.Scheduling.ImpactAnalysis`,
`Movimento.Waitlist.SlotFinder`, `Movimento.Packages.Series` — nomes de [04-arquitetura.md](04-arquitetura.md) §2)
são funções que recebem dados e o relógio como argumentos e devolvem um valor. São a base larga da
pirâmide: rápidos, sem setup, e onde mora a maior densidade de casos. A eles somam-se os predicados de
pacote (`wouldConsume`, `apptPkg`), igualmente puros. `layoutAppts` é o motor que vive no cliente
(§2.5) e só existe em Vitest.

**O que é integração.** O ponto em que o motor puro vira uma *action* do Ash dentro de uma
transação, com policy, tenant, criptografia de campo e constraint de banco. Aqui o teste precisa de
Postgres real (a sandbox do Ecto, uma transação por teste). É onde se prova que a exclusion constraint
de sobreposição realmente dispara, que a policy realmente barra, que o tenant realmente isola. Menos
casos, mais caros, cada um valendo por dez unitários.

**O que é e2e.** Um punhado de jornadas que só fazem sentido no navegador com a stack inteira de pé:
arrastar um agendamento e ver a raia recolorir, oferecer uma vaga da fila e ela sumir para o outro
atendente via Channel, remarcar em cima de uma remarcação alheia e receber o aviso de conflito. São
caros e frágeis por natureza; ficam contados nos dedos e cobrem o encanamento, não as regras — as
regras já foram exauridas embaixo.

A regra de ouro: **cada bug de regra é provado no nível mais baixo em que ele pode existir.** Um erro
de precedência de disponibilidade é um teste unitário de `dayPeriods`, nunca um e2e de Playwright que
clica em quinze telas para chegar lá.

---

## 2. Os motores de regra — o coração

Cada motor abaixo tem uma implementação de referência no protótipo, com linha citada e verificada. A
estratégia é a mesma para todos: **extrair a tabela de verdade da referência, transformá-la em teste
table-driven, e, onde o espaço de entrada for grande, cercar com property-based test.** O protótipo
gera o gabarito; o Elixir precisa reproduzi-lo bit a bit.

### 2.1 `dayPeriods` — precedência de disponibilidade em 4 camadas

Referência: [`:854`](../interface/Movimento.dc.html#L854), com `profWeek` em [`:840`](../interface/Movimento.dc.html#L840),
`dateException` em [`:850`](../interface/Movimento.dc.html#L850) e `profException` em [`:852`](../interface/Movimento.dc.html#L852).

O código, lido linha a linha, resolve nesta ordem (a **primeira** que decide, vence):

```
dayPeriods(prof, date, hoursOverride):
  ex = dateException(date)                    # feriado/exceção da CLÍNICA na data
  se ex existe e ex.tipo != 'horario':        (A) → null   # clínica fechada
  pex = profException(prof, date)             # folga/horário pontual do PROFISSIONAL
  se pex existe:                              (B) → pex.tipo=='horario' ? pex.periods : null
  se ex existe:                              (C) → ex.periods            # horário especial da clínica
  senão:                                     (D) → profWeek(prof, dow, hoursOverride)  # semanal
```

E a quarta camada, `profWeek`, tem sub-ramos que são o segundo ponto cego mais provável do port:

```
profWeek(prof, dow, hoursOverride):
  se prof.followClinic != false:              # segue a clínica
     se avail TEM a chave dow:  → avail[dow]  # override do prof (array OU null=fechado)
     senão:                     → (hoursOverride || hours)[dow] || null   # herda a clínica
  senão:                                       # NÃO segue a clínica
     → avail[dow] || null                      # só o próprio horário conta
```

Duas assimetrias importam e são exatamente o que um reimplementador erra:

1. **Fechamento da clínica (A) vence até o horário pontual do profissional (B); mas o horário
   *especial* da clínica (C) NÃO vence o horário pontual do profissional.** Feriado fecha para todos,
   inclusive quem tinha um atendimento pontual marcado; já um dia de horário estendido da clínica
   cede ao pontual do profissional. É a diferença entre a linha `if(ex && ex.tipo!=='horario') return null`
   ([`:856`](../interface/Movimento.dc.html#L856)) vir *antes* do `pex`, e o `if(ex) return ex.periods||[]`
   ([`:859`](../interface/Movimento.dc.html#L859)) vir *depois*.

2. **`avail[dow] = null` presente vence `avail[dow]` ausente.** O `hasOwnProperty` de [`:844`](../interface/Movimento.dc.html#L844)
   distingue "o profissional declarou explicitamente que não atende nesta terça" (chave presente com
   `null`) de "o profissional não disse nada sobre terça, então herda a clínica" (chave ausente). Em
   Elixir isso é a diferença entre `%{2 => nil}` e `%{}` — e `Map.get(av, dow)` devolve `nil` nos dois
   casos. Reproduzir a referência exige `Map.has_key?/2`, não `Map.get/2`. **# NAO-VERIFICADO ao
   scaffoldar: garantir que a modelagem Ash preserve a distinção "fechado explícito" vs "não
   configurado" — provavelmente um campo por dia que aceita `:fecha` como valor distinto de `nil`.**

#### Tabela de verdade

Colunas: **A** = exceção da clínica na data (`—` ausente · `fecha` feriado/tipo≠horario · `esp` horário
especial tipo=horario). **B** = exceção do profissional (`—` · `folga` tipo≠horario · `pont` horário
pontual). **fc** = `followClinic`. **av[dow]** = override semanal do prof (`—` ausente · `null` chave
presente com null · `[..]` array). **h[dow]** = horário semanal da clínica. Resultado e a camada que decidiu.

| # | A | B | fc | av[dow] | h[dow] | → resultado | decide |
|---|---|---|----|---------|--------|-------------|--------|
| 1 | fecha | — | — | — | [08–18] | `null` (fechado) | A |
| 2 | fecha | pont [08–12] | — | — | — | `null` (fechado) | A — **feriado vence pontual do prof** |
| 3 | — | folga | true | [09–12] | [08–18] | `null` | B |
| 4 | esp [14–18] | folga | true | — | [08–18] | `null` | B — **folga vence horário especial** |
| 5 | — | pont [08–12] | true | — | [08–18] | `[08–12]` | B |
| 6 | esp [14–18] | pont [08–12] | true | [09–12] | [08–18] | `[08–12]` | B — **pontual vence especial** |
| 7 | esp [14–18] | — | true | [09–12] | [08–18] | `[14–18]` | C — **especial vence semanal** |
| 8 | esp [14–18] | — | false | [09–12] | [08–18] | `[14–18]` | C — especial vence até `fc=false` |
| 9 | — | — | true | [09–12] | [08–18] | `[09–12]` | D — override do prof |
| 10 | — | — | true | `null` | [08–18] | `null` | D — **prof fecha o dia mesmo seguindo a clínica** |
| 11 | — | — | true | — | [08–18] | `[08–18]` | D — herda a clínica |
| 12 | — | — | true | — | `null` | `null` | D — clínica fechada nesse dia da semana |
| 13 | — | — | false | [08–12] | [08–18] | `[08–12]` | D — ignora a clínica |
| 14 | — | — | false | — | [08–18] | `null` | D — **não segue e não configurou → sem atendimento** |
| 15 | — | — | false | `null` | [08–18] | `null` | D — idem 14 (null e ausente coincidem quando `fc=false`) |

Note que as linhas 14 e 15 dão o mesmo resultado por caminhos diferentes (`av[dow] || null`), enquanto
as linhas 10 e 11 divergem só pela presença da chave — é o par que valida o `hasOwnProperty` ([`:844`](../interface/Movimento.dc.html#L844)).

#### Como isso vira teste

**Table-driven em ExUnit** é o formato natural: a tabela acima é literalmente uma lista de tuplas
`{cenário, entrada, esperado}` e um `for` gera um teste por linha. **# NAO-VERIFICADO (ExUnit é
biblioteca padrão, mas confirmar sintaxe ao escrever):**

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
@casos [
  {"feriado vence pontual", %{clinica: :fecha, prof: {:pont, [{8,12}]}}, :fechado},
  {"folga vence especial", %{clinica: {:esp, [{14,18}]}, prof: :folga}, :fechado},
  {"pontual vence especial", %{clinica: {:esp, [{14,18}]}, prof: {:pont, [{8,12}]}}, [{8,12}]},
  # ... as 15 linhas
]
for {nome, entrada, esperado} <- @casos do
  test "dayPeriods: #{nome}" do
    assert Availability.day_periods(unquote(Macro.escape(entrada)), @clock) == unquote(Macro.escape(esperado))
  end
end
```

**Property-based (StreamData) por cima**, para o que a tabela não enumera: a propriedade estrutural é
*monotonia da precedência*. Gerando aleatoriamente as quatro camadas, valem invariantes verificáveis
sem reimplementar o motor no teste:

- Se A = `fecha`, o resultado é sempre `:fechado`, **independente** de B, fc, av, h. (a camada A é absorvente)
- Se B = `folga`, o resultado é `:fechado` sempre que A ≠ `fecha`.
- Se B = `pont p`, o resultado é `p` sempre que A ≠ `fecha`.
- O resultado nunca contém um período fora da união dos períodos declarados nas camadas — o motor
  seleciona, nunca inventa horário.

**# NAO-VERIFICADO: StreamData é a lib usual de property testing em Elixir (`use ExUnitProperties`,
`property/1`, `check all`); confirmar API ao adicionar a dependência.** A propriedade mais valiosa,
quando o motor Elixir e a referência JS coexistirem, é o **teste diferencial**: gerar N entradas
aleatórias, rodar as duas implementações, exigir saídas idênticas. Enquanto o protótipo existir, ele é
o oráculo; depois de aposentado, a suíte table-driven congela o comportamento.

### 2.2 `futureConflicts` — impacto retroativo de mudança de horário

Referência: [`:864`](../interface/Movimento.dc.html#L864). Lê `today='2026-06-25'` como constante local em
[`:865`](../interface/Movimento.dc.html#L865).

A regra é cirúrgica e o teste tem que ser cirúrgico junto: o motor devolve **apenas os agendamentos
que *cabiam* no horário atual e *deixariam* de caber após a mudança**. A condição decisiva é
`fits(before,a) && !fits(after,a)` ([`:877`](../interface/Movimento.dc.html#L877)), onde `fits`
([`:866`](../interface/Movimento.dc.html#L866)) exige que o agendamento inteiro (`a.start` até
`a.start+a.dur`) caiba dentro de algum período. Filtros que precedem: descarta
`cancelado`/`concluido`/`faltou` ([`:869`](../interface/Movimento.dc.html#L869)), descarta datas
passadas `a.date < today` ([`:870`](../interface/Movimento.dc.html#L870)), descarta profissional
inexistente ([`:872`](../interface/Movimento.dc.html#L872)).

Os casos de borda que a tabela precisa cobrir, cada um uma armadilha distinta:

| Situação | `before` | `after` | Entra na lista? |
|---|---|---|---|
| Já não cabia antes (encaixe fora do expediente) | não cabe | não cabe | **Não** — só pega quem "cabia e deixou" |
| Cabia e continua cabendo (mudança não o afeta) | cabe | cabe | Não |
| Cabia; depois da mudança o dia fica fechado | cabe | `null`/`[]` | **Sim** — motivo "Sem atendimento após a mudança" |
| Cabia; encolheu e agora ele fica de fora | cabe | cabe parcial, ele não | **Sim** — motivo "Fora do novo expediente (…)" |
| Encosta exatamente na borda (`a.start+a.dur == fim`) | cabe (`<=`) | — | limite fechado à direita — testar o `==` |
| Agendamento hoje mesmo (`a.date == today`) | — | — | incluído (`< today` é estrito) |
| Agendamento ontem | — | — | excluído |
| Status já resolvido (concluído/faltou/cancelado) | — | — | excluído sempre |

A borda de igualdade (`>=` em `a.start >= t2m(p[0])` e `<=` em `a.start+a.dur <= t2m(p[1])`, ambas em
`fits`, [`:866`](../interface/Movimento.dc.html#L866)) é onde erros de "off-by-one de minuto" se
escondem: um agendamento que termina exatamente às 18:00 num expediente que fecha 18:00 **cabe**. Um
caso de teste dedicado a cada lado do `<=` é obrigatório.

A ordenação da saída ([`:881`](../interface/Movimento.dc.html#L881)) é por data e depois por
`start` — também é comportamento observável e vale um caso que embaralha a entrada e verifica a ordem.

Note que `futureConflicts` **compõe** `dayPeriods`: `before = dayPeriods(prof, a.date, hours)`
([`:874`](../interface/Movimento.dc.html#L874)) e `after = afterFn(...)` ([`:875`](../interface/Movimento.dc.html#L875)),
onde a `afterFn` mais comum é a de `hourConflicts`, que por sua vez chama `dayPeriods` com o rascunho
([`:884`](../interface/Movimento.dc.html#L884)). Isso implica testes em camadas: `dayPeriods` provado
isolado primeiro (§2.1), e `futureConflicts` testado com `dayPeriods` real (não mockado) — o mock aqui
esconderia justamente o acoplamento que interessa. É teste de integração *entre motores puros*, ainda
sem banco.

### 2.3 `filaVagas` — busca de vagas na fila de espera

Referência: [`:2531`](../interface/Movimento.dc.html#L2531). Constantes na primeira linha do corpo
([`:2533`](../interface/Movimento.dc.html#L2533)): `TODAY='2026-06-25', NOW=702, DUR=50, DAYS=14, STEP=30, CAP=50`.

Este é o motor mais denso e o de maior superfície de teste, porque combina três eixos: **janela**
(manhã/tarde/qualquer), **regras** (por data ou por dia-da-semana, com períodos), e **duas passadas de
descoberta** com semânticas diferentes. Varre 14 dias × profissionais.

As duas passadas ([`:2568`](../interface/Movimento.dc.html#L2568) e [`:2576`](../interface/Movimento.dc.html#L2576))
são o cerne e precisam de testes separados:

- **Passada 1 — vagas que abriram** (`freed:true`, laço a partir de [`:2568`](../interface/Movimento.dc.html#L2568)):
  itera os agendamentos `cancelado`/`faltou` do profissional. Cada um vira uma vaga no **horário exato**
  que ficou livre — desde que caiba no expediente (`inPeriod`), esteja de fato livre (`isFree`, sem outro
  agendamento por cima) e passe na janela+regras (`fitsWin`). Nunca é escondida atrás de outra brecha. É
  o que a UI destaca em teal.
- **Passada 2 — disponibilidade geral** (`freed:false`, laço a partir de [`:2576`](../interface/Movimento.dc.html#L2576)):
  para cada período do expediente, caminha de `STEP` em `STEP` (30 min) e emite **só a primeira brecha
  livre** do período (`break` após o primeiro `add`, [`:2584`](../interface/Movimento.dc.html#L2584)). É a
  sugestão "genérica", uma por período.

Casos de borda verificados na referência que a tabela precisa cobrir:

| Caso | Linha ref. | Comportamento a fixar |
|---|---|---|
| Hoje, antes de agora (`dOff==0 && start<NOW`) | [`:2570`](../interface/Movimento.dc.html#L2570) (passada 1), [`:2580`](../interface/Movimento.dc.html#L2580) (passada 2) | vaga no passado do dia é descartada (NOW=702=11:42) |
| Amanhã em diante, mesmo horário | — | `start<NOW` não se aplica (só `dOff==0`) |
| Regra por data expirada | `filaRegraExpirada` [`:2515`](../interface/Movimento.dc.html#L2515) | `r.tipo=='data' && r.data<'2026-06-25'` é filtrada fora |
| Janela manhã | [`:2542`](../interface/Movimento.dc.html#L2542) | `start>=720` (12:00) → rejeitado |
| Janela tarde | [`:2543`](../interface/Movimento.dc.html#L2543) | `start<720` → rejeitado |
| Sem regras | [`:2544`](../interface/Movimento.dc.html#L2544) | `fitsWin` devolve `-1` (passa livre), não `null` |
| Profissional não atende no dia | [`:2563`](../interface/Movimento.dc.html#L2563) | `dayPeriods` vazio → `continue`, prof pulado |
| Deduplicação | `seen` [`:2553`](../interface/Movimento.dc.html#L2553) declarado, usado no `add` [`:2554`](../interface/Movimento.dc.html#L2554) | chave `date\|start\|profId`; vaga que abriu não duplica com a geral |
| Teto de resultados | `CAP=50` [`:2533`](../interface/Movimento.dc.html#L2533); corte em [`:2588`](../interface/Movimento.dc.html#L2588) | `if(out.length>=CAP) break` corta o laço externo ao atingir 50 |
| Ordenação | [`:2591`](../interface/Movimento.dc.html#L2591) | `freed` primeiro, depois data, start, profId |

O ponto que mais engana: uma vaga que abriu (passada 1) e a primeira brecha geral (passada 2) podem
recair no **mesmo** `date|start|profId`; o `seen` garante que a versão `freed:true` (emitida primeiro)
vence e a geral é descartada. Um teste tem que montar exatamente essa colisão e verificar que só sai
uma vaga, com `freed:true`.

`filaVagas` também **compõe `dayPeriods`** ([`:2562`](../interface/Movimento.dc.html#L2562)). Mesma
disciplina de §2.2: `dayPeriods` real, não mockado. E, como toda a lógica depende de `TODAY`/`NOW`,
esse motor é o exemplo canônico da [§3](#3-tempo-determinístico-é-o-que-torna-tudo-isto-possível) — sem
relógio injetável, ele é literalmente impossível de testar de forma reproduzível.

Property-based útil aqui: **nenhuma vaga emitida colide com um agendamento ocupado** (invariante de
`isFree`, [`:2566`](../interface/Movimento.dc.html#L2566)), e **toda vaga emitida cabe num período do
expediente** (invariante de `inPeriod`, [`:2565`](../interface/Movimento.dc.html#L2565)) — gerando
agendas aleatórias e verificando as duas propriedades sem reimplementar o buscador.

### 2.4 `computeSerie` — feriado pula e ESTENDE a série

Referência: [`:1081`](../interface/Movimento.dc.html#L1081).

A regra que define o teste: o laço roda `while(count<d.n && guard<400)` ([`:1086`](../interface/Movimento.dc.html#L1086))
e, num dia que bate com `d.dows`, **empurra o slot para a saída sempre** (`out.push`,
[`:1091`](../interface/Movimento.dc.html#L1091)) **mas só incrementa `count` se não for feriado**
(`if(!fer) count++`, [`:1092`](../interface/Movimento.dc.html#L1092)). Feriado é
`holidays.some(h => h.data===ds && h.tipo!=='horario')` ([`:1090`](../interface/Movimento.dc.html#L1090))
— repare no `tipo!=='horario'`: um dia de horário *especial* da clínica **não** é feriado e conta como
sessão normal. Consequência: a série de N sessões "úteis" se **estende** no calendário para acomodar os
feriados, e a saída inclui os feriados marcados (`feriado:true`) intercalados, para a UI mostrar o pulo.

O segundo eixo é o âncora: `if(!d.inclusive) cur.setDate(cur.getDate()+1)` ([`:1083`](../interface/Movimento.dc.html#L1083))
— séries "que começam depois" (renovação) **pulam o dia âncora**; pacotes novos incluem a data de
início. E o `guard<400` ([`:1086`](../interface/Movimento.dc.html#L1086)) é a válvula de segurança
contra `dows` vazio ou datas patológicas.

Tabela de casos:

| Caso | Fixar |
|---|---|
| N sessões, zero feriados, `inclusive` | saída tem N itens, todos `feriado:false`, começa no âncora |
| Um feriado no meio da série | saída tem N+1 itens; o feriado sai `feriado:true` e a série vai um slot além |
| Feriado que é `tipo:'horario'` (horário especial) | **conta** como sessão (não é feriado) |
| `inclusive:false` (renovação) | primeiro slot é *depois* do âncora, âncora não aparece |
| `dows` = dia único vs múltiplos dias | cadência semanal correta |
| Feriado cai exatamente num `dow` da série | pulado e estende; feriado fora dos `dows` é irrelevante |
| `guard` — `dows` vazio | laço termina em 400 sem loop infinito; saída vazia |
| Dois feriados consecutivos na cadência | estende dois slots |

O caso "feriado `tipo:'horario'` conta como sessão" é o que amarra `computeSerie` a `dayPeriods` e à
mesma noção de feriado — e é onde uma reimplementação desatenta trataria *qualquer* registro em
`holidays` como pulo, gerando séries longas demais.

### 2.5 `layoutAppts` — coloração de grafo de intervalos (cliente, Vitest)

Referência: [`:1576`](../interface/Movimento.dc.html#L1576). É o único motor que **não** vem para o
servidor ([04-arquitetura.md](04-arquitetura.md) §2): é layout visual, roda no navegador, e vira uma
função pura em TypeScript testada com **Vitest**.

O algoritmo é *greedy interval partitioning*: ordena por `start` depois `end`, agrupa em *clusters*
(um cluster é uma sequência maximal de intervalos que se sobrepõem — o `flush` dispara quando
`it.start >= clusterEnd`, [`:1582`](../interface/Movimento.dc.html#L1582)), e dentro do cluster atribui
cada intervalo à primeira raia livre (`laneEnds.findIndex(e => e <= it.start)`, [`:1580`](../interface/Movimento.dc.html#L1580)),
abrindo raia nova se nenhuma servir. O `lanes` reportado por item é a **largura do cluster** (número de
raias), que equivale ao *maior número de agendamentos simultâneos* naquele cluster.

Sobre a otimalidade, vale enunciar o teorema corretamente porque ele é a propriedade de teste. Um grafo
de intervalos é **perfeito**; num grafo perfeito o número cromático χ (mínimo de raias) é igual ao
tamanho da clique máxima ω (maior número de intervalos mutuamente sobrepostos, i.e., o pico de
simultaneidade). O guloso por ordem de início atinge exatamente esse mínimo. Logo, para qualquer
entrada, **`maxLanes` do cluster = pico de simultaneidade daquele cluster** — não "≥", é igualdade. Essa
é a asserção forte que a property-based deve exigir; um port que produzisse mais raias que o pico estaria
errado, não apenas subótimo.

Casos de teste (todos determinísticos, sem tempo, sem DOM):

| Caso | Esperado |
|---|---|
| Intervalos disjuntos | todos `lane:0`, `lanes:1`, um cluster cada |
| Dois sobrepostos | `lanes:2`, lanes 0 e 1 |
| Encosta na borda (`a.end == b.start`) | **não** sobrepõe (`e <= it.start`) — mesma raia, clusters separados |
| Três em cadeia A∩B, B∩C, A∌C | um cluster de 3, mas `lanes:2` se A e C não colidem (A libera a raia para C) |
| Aninhado (um curto dentro de um longo) | `lanes:2` |
| Ordem de entrada embaralhada | resultado idêntico (a ordenação interna normaliza) |
| Mesmíssimo horário, 4 agendamentos | `lanes:4` |

Como é função pura de `Array<{id,start,dur}> → {byId, maxLanes}`, o teste é direto e casa 1-para-1 com
a saída da referência. Properties: **duas raias nunca contêm intervalos que se sobrepõem** (coloração
válida) e **`maxLanes` = pico de simultaneidade** (otimalidade exata do guloso em grafo de intervalos,
justificada acima).

### 2.6 `wouldConsume` — quando a falta debita o pacote (tabela de verdade)

Referência: [`:1104`](../interface/Movimento.dc.html#L1104), apoiada em `pkgPunitivo`
([`:1103`](../interface/Movimento.dc.html#L1103)). Este predicado é pequeno, puro, e decide dinheiro/saldo
de pacote — é exatamente o tipo de regra que um bug silencioso corrói sem alarme, então ganha tabela de
verdade própria. O conjunto de testes anterior o ignorava.

A lógica lida:

```
wouldConsume(a, statusVal, pk):
  se statusVal == 'concluido'          → true                       # concluído SEMPRE debita
  se statusVal == 'faltou':
     se a.faltaJustificada             → false                      # falta justificada nunca debita
     senão                             → pkgPunitivo(pk)            # só debita se o pacote é punitivo
  senão                                → false                      # agendado/confirmado/cancelado não debitam

pkgPunitivo(pk):
  se pk.faltaPunitiva != null          → !!pk.faltaPunitiva         # override do pacote vence
  senão                                → !!settings.noShowConsome   # fallback pro ajuste global
```

O ponto que a redação "falta só debita se o pacote for punitivo E a falta não for justificada" resume,
mas que só a tabela fixa sem ambiguidade — atenção à precedência entre `faltaJustificada` e
`faltaPunitiva`, e ao **fallback** de `pkgPunitivo` quando o pacote não declara `faltaPunitiva`:

| # | status | `faltaJustificada` | `pk.faltaPunitiva` | `settings.noShowConsome` | → debita? | por quê |
|---|---|---|---|---|---|---|
| 1 | concluido | — | — | — | **sim** | concluído sempre debita, independe do resto |
| 2 | faltou | false | `true` | — | **sim** | punitivo e não justificada |
| 3 | faltou | false | `false` | — | **não** | pacote explicitamente não-punitivo |
| 4 | faltou | **true** | `true` | — | **não** | justificada vence o punitivo |
| 5 | faltou | true | `false` | — | não | justificada e não-punitivo |
| 6 | faltou | false | `null` (não declarado) | `true` | **sim** | fallback global punitivo |
| 7 | faltou | false | `null` (não declarado) | `false` | **não** | fallback global não-punitivo |
| 8 | agendado | — | — | — | não | status não resolvido |
| 9 | confirmado | — | — | — | não | idem |
| 10 | cancelado | — | — | — | não | cancelado nunca debita |

As linhas 6 e 7 são as que pegam o erro clássico: tratar `pk.faltaPunitiva == null` como `false` em vez
de cair no ajuste global da clínica. As linhas 2↔4 fixam a precedência de `faltaJustificada`. Property
útil: para qualquer `pk`, `wouldConsume(a, 'concluido', pk)` é sempre `true` e
`wouldConsume(a, 'agendado'|'cancelado', pk)` é sempre `false` — o eixo de status domina antes de olhar
punitividade.

### 2.7 `apptPkg` em turma multi-pacote — armadilha do "primeiro dono" (regressão)

Referência: [`:1110`](../interface/Movimento.dc.html#L1110). `apptPkg` localiza o pacote e o dono a que
um agendamento pertence. Para uma **turma** (agendamento com `patientIds`), ela lê o mapa `a.pkgOf`
(paciente → pacote) e itera as chaves; no primeiro par que resolve um pacote válido, **retorna e para**
(`for(...) { ...; if(pk) return {pk, patient, ownerId, pkgId}; }`). `apptPkgDebitado`
([`:1119`](../interface/Movimento.dc.html#L1119)) chama `apptPkg` e, portanto, herda esse retorno único.

Consequência: numa turma cujos participantes estão em **pacotes diferentes**, `apptPkg` enxerga só o
primeiro. Um débito ou um ajuste em massa dirigido por `apptPkg` afeta **um** dono e ignora
silenciosamente os demais — cada outro participante deveria ter o seu próprio pacote debitado/reajustado
e não tem. É um bug latente do protótipo (aceitável num mock de UI, inaceitável em produção com saldo
real de pacote).

O teste de regressão pinça exatamente isso:

1. Montar uma turma com `patientIds = [pidA, pidB, pidC]` e `pkgOf = {pidA: pkgA, pidB: pkgB, pidC: pkgC}`,
   os três pacotes distintos e punitivos.
2. Marcar a turma como `faltou` (sem justificar) e disparar o débito.
3. Afirmar que **os três** pacotes foram debitados — não apenas o de `pidA`. O port **não** pode
   replicar o retorno-único de `apptPkg`; a operação de pacote sobre turma tem que iterar todos os donos.
4. Espelho para ajuste em massa (mudança de horário/cadência de um pacote dentro da turma): a mudança
   dirigida a `pkgA` não pode arrastar sessões de `pkgB`/`pkgC`, e vice-versa.

Este teste existe porque a asserção "afeta um dono e ignora os demais" é precisamente o comportamento
que queremos que o port **quebre** — o teste falha contra a tradução ingênua e passa contra a correta.

---

## 3. Tempo determinístico é o que torna tudo isto possível

A [ADR-009](00-decisoes.md) decide que nenhum módulo de domínio lê o relógio do sistema; o tempo entra
como dependência. Esta seção existe para deixar explícito **por que os testes acima são impossíveis
sem isso**, e o protótipo já prova o ponto por acidente.

Os motores dependem, todos, de "quando é agora":

- `futureConflicts` filtra por `a.date < today` ([`:870`](../interface/Movimento.dc.html#L870)) — a
  fronteira passado/futuro.
- `filaVagas` ancora 14 dias em `TODAY` e corta o passado do dia com `NOW=702` ([`:2570`](../interface/Movimento.dc.html#L2570)
  na passada 1, [`:2580`](../interface/Movimento.dc.html#L2580) na passada 2).
- `filaRegraExpirada` compara com `'2026-06-25'` ([`:2515`](../interface/Movimento.dc.html#L2515)).
- `computeSerie` parte de `d.fromDate || state.date` ([`:1082`](../interface/Movimento.dc.html#L1082)).
- O botão Concluir/Faltou destrava com `a.date < hoje() || (a.date===hoje() && a.start<=702)` ([`:1804`](../interface/Movimento.dc.html#L1804)).

O protótipo **congelou o tempo na marra**: `hoje()` é a string literal `'2026-06-25'` ([`:1098`](../interface/Movimento.dc.html#L1098))
e o número mágico `702` (11:42) aparece **literalmente 8 vezes** no arquivo — verificado por
`grep -n "702"`: linhas 130, 285, 828, 1046, 1586, 1600, 1804 e 2533. Delas, **duas** são a definição da
constante `NOW=702` (uma no gerador de seed em [`:130`](../interface/Movimento.dc.html#L130), outra dentro
de `filaVagas` em [`:2533`](../interface/Movimento.dc.html#L2533)); **três** são o cálculo de scroll até a
linha do "agora" na grade ([`:285`](../interface/Movimento.dc.html#L285), [`:1586`](../interface/Movimento.dc.html#L1586),
[`:1600`](../interface/Movimento.dc.html#L1600)); e **três** são comparações de decisão de negócio contra o
horário atual ([`:828`](../interface/Movimento.dc.html#L828) `needsAction`, [`:1046`](../interface/Movimento.dc.html#L1046)
que destrava o "quem cabe", [`:1804`](../interface/Movimento.dc.html#L1804) que destrava Concluir/Faltou). O
mesmo horário duplicado em oito pontos é uma dívida (o número mágico está espalhado), mas é também a razão
de os motores serem testáveis hoje: rodando a referência no navegador, a saída é sempre a mesma, então dá
para transcrever gabaritos.

Em produção fazemos a versão limpa da mesma ideia: o "agora" é um argumento. Cada motor recebe um
`clock` (um `DateTime` mais o timezone da clínica), e a action do Ash o injeta a partir do
`Ash.Scope`/contexto. **# NAO-VERIFICADO: a forma exata de passar o relógio numa action do Ash — via
`context`/`Ash.Scope` no changeset — deve ser confirmada contra hexdocs ao scaffoldar; o comportamento
pretendido é que o domínio jamais chame `DateTime.utc_now/0` diretamente.** No teste, o relógio é um
valor fixo (`~U[2026-06-25 11:42:00-03:00]` no fuso `America/Sao_Paulo`), e é isso que torna cada caso
das tabelas de §2 **reproduzível e independente da data em que o CI roda**.

O anti-padrão a proibir por lint/revisão: qualquer `DateTime.utc_now`, `Date.utc_today`, `System.os_time`
dentro de `lib/movimento/scheduling`, `.../waitlist`, `.../packages`. Se aparecer, o teste vira uma
bomba-relógio que passa hoje e falha em 2027. No cliente, a mesma proibição vale: o front nunca deriva
"hoje" de `new Date()` para decisão de negócio (só para exibição) — a data-âncora vem do servidor.

Timezone por clínica ([ADR-009](00-decisoes.md)) adiciona uma classe de teste própria: uma clínica em
`America/Sao_Paulo` e outra em `America/Manaus` (uma hora de diferença, sem horário de verão) devem
resolver "hoje" e "já começou" em fusos distintos para o **mesmo** instante UTC. Um caso dedicado com
duas clínicas e um agendamento na virada da meia-noite local prova que a fronteira do dia respeita o
fuso e não o UTC nem o do servidor.

---

## 4. Testes no Elixir (ExUnit + Ash)

### 4.1 Fixtures com `Ash.Generator`

A regra do repo ([`.claude/rules/ash.md`](../.claude/rules/ash.md), seção "Testing") é explícita:
gerar dados com `Ash.Generator`, testar pelo code interface do domínio, preferir as versões `!` que
levantam, e usar `authorize?: false` quando a autorização não é o foco do teste. Criamos um módulo de
geradores (`Movimento.TestGenerators`, **# NAO-VERIFICADO: assinatura de `Ash.Generator`/`changeset_generator`
a confirmar ao scaffoldar**) com um gerador por recurso: `patient/1`, `professional/1`, `appointment/1`,
`package/1`, `waitlist_item/1`, `clinic/1`.

O seed de desenvolvimento sai do próprio protótipo, que tem um PRNG determinístico gerando um dataset
sintético e legalmente inerte ([04-arquitetura.md](04-arquitetura.md) §12, `interface/Movimento.dc.html`
de [`:43`](../interface/Movimento.dc.html#L43), `let s=987654321`, a [`:263`](../interface/Movimento.dc.html#L263),
fecho do IIFE de seed). Esse dataset é ouro para fixtures de integração realistas — ele já tem pacotes,
faltas, feriados e exceções de profissional montados de forma coerente.

### 4.2 A regra crítica: deadlock em testes concorrentes

`.claude/rules/ash.md` dedica uma seção inteira a isto e ela **não é opcional** neste domínio. ExUnit
roda testes `async: true` em paralelo; se dois testes tentam inserir registros com o mesmo valor num
atributo de identidade, o Postgres serializa e, sob concorrência, dá deadlock intermitente — o pior
tipo de falha de CI, que passa localmente e quebra sem padrão no pipeline.

Os atributos de identidade **deste** domínio são precisamente os dados sensíveis e os documentos
únicos: **CPF** do paciente, **CREFITO** do profissional, **e-mail** de membro/login. Cada fixture que
preenche um desses campos **tem** que usar valor globalmente único:

```elixir
# NAO-VERIFICADO: confirmar API de Ash.Generator ao scaffoldar
def patient(opts \\ []) do
  changeset_generator(Patient, :create,
    defaults: [
      cpf:   gerar_cpf_valido_unico(),                              # dígito verificador correto + unicidade
      email: "pac-#{System.unique_integer([:positive])}@example.com",
      nome:  "Paciente #{System.unique_integer([:positive])}"
    ],
    overrides: opts)
end
```

`System.unique_integer([:positive])` é a ferramenta certa: barato, monotônico, sem colisão dentro do
mesmo nó de teste. Para CPF e CREFITO há uma sutileza a mais — eles têm **dígito verificador**; o
gerador precisa produzir documentos *válidos* e *únicos* ao mesmo tempo, senão a própria validação do
recurso rejeita a fixture. Vale um pequeno gerador de CPF/CREFITO com DV correto parametrizado pelo
inteiro único. **Nunca** literais fixos como `"111.111.111-11"` compartilhados entre testes.

### 4.3 Policies com `Ash.can?`

`.claude/rules/ash.md` recomenda testar autorização com `Ash.can?`. Cada policy de cada recurso ganha
um par de testes: um ator que **pode** e um que **não pode**. O domínio tem RBAC real ([ADR-002](00-decisoes.md),
[ADR-007](00-decisoes.md)) e `field_policies` sobre dado de saúde, então os testes de policy se dividem em dois níveis:

- **Ação inteira:** um atendente pode `:schedule`, um profissional só vê a própria agenda, um paciente
  (se houver portal) não pode `:mark_no_show`. `assert Movimento.Scheduling.can_schedule?(ator, ...)`
  e o `refute` correspondente. **# NAO-VERIFICADO: nome exato da função `can_*?` gerada pelo code
  interface a confirmar.**
- **Campo (`field_policies`):** o campo `patient.tags` (que contém diagnóstico — dado sensível), `medico`,
  `crm`, `banco`/`pix` do profissional só são legíveis por papéis autorizados ([ADR-007](00-decisoes.md)).
  O teste carrega o recurso com um ator não autorizado e verifica que o campo volta **filtrado/oculto**,
  não vazado. Este é o teste que impede um vazamento de LGPD passar despercebido num refactor de policy.
  **# NAO-VERIFICADO: o mecanismo `field_policies` do `Ash.Policy.Authorizer` e como o campo oculto se
  apresenta (nil vs erro vs ausência) a confirmar contra hexdocs ao scaffoldar.**

### 4.4 Notifiers / tempo real

O `Ash.Notifier` que alimenta o `Phoenix.PubSub` ([04-arquitetura.md](04-arquitetura.md) §6) é testado
por integração: executa a action, e assina o tópico esperado (`clinic:<id>:agenda:<data>`), afirmando
que a mensagem semântica chega com o recurso serializado e o `version` correto. **# NAO-VERIFICADO:
usar `Phoenix.PubSub.subscribe` + `assert_receive` no teste; confirmar o formato da notificação Ash e
que o `Ash.Notifier.PubSub` publica em toda mutação.** O caso negativo importa igual: uma mutação numa
clínica **não** publica no tópico de outra (ver [§6](#6-multi-tenant-isolamento-é-obrigatório-para-cada-recurso)).

---

## 5. Testes de concorrência: as duas corridas reais

[04-arquitetura.md](04-arquitetura.md) §7 nomeia as duas condições de corrida que só aparecem com mais
de um usuário, e ambas são requisito de v1. Testá-las exige sair do reino puro e provar comportamento
do **Postgres sob concorrência real** — não dá para simular com uma lista em memória (é justamente o
que o protótipo faz e por isso a corrida existe: `offerVaga` só pré-preenche um modal, [`:2596`](../interface/Movimento.dc.html#L2596),
e `createAppt`, [`:1048`](../interface/Movimento.dc.html#L1048), não reserva nada entre oferecer e confirmar).

### 5.1 Hold de vaga na fila (exclusion constraint + expiração via DML)

A correção ([04-arquitetura.md](04-arquitetura.md) §7.2) é um recurso `SlotHold` com TTL e uma
**exclusion constraint** no Postgres sobre `(professional_id, tstzrange(starts_at, ends_at, '[)'))`.
**Ponto crítico corrigido:** essa constraint **não** tem predicado de tempo. A versão anterior deste
documento afirmava que ela "filtra por `expires_at > now()`" — isso é **DDL inválido**: o predicado de
uma exclusion constraint precisa ser `IMMUTABLE`, e `now()` é `STABLE`; o Postgres **recusa a criação
da constraint**. Além disso, mesmo que aceitasse, o predicado é avaliado no `INSERT`, não continuamente,
então "expirou sozinho" nunca se propagaria. O desenho correto (04 §7.2) põe a expiração na **DML**:

1. A constraint cobre **todos** os holds vivos, sem cláusula de tempo:

   ```sql
   -- NAO-VERIFICADO: em Ash/AshPostgres isto entra via custom_statements/índice customizado;
   -- confirmar a forma exata contra a doc do AshPostgres ao scaffoldar.
   CREATE EXTENSION IF NOT EXISTS btree_gist;
   ALTER TABLE slot_holds
     ADD CONSTRAINT slot_holds_no_overlap
     EXCLUDE USING gist (
       professional_id                     WITH =,
       tstzrange(starts_at, ends_at, '[)') WITH &&
     );
   ```

2. A ação `:offer`, **dentro da mesma transação e antes do insert**, apaga os holds já vencidos do
   profissional: `DELETE FROM slot_holds WHERE professional_id = $1 AND expires_at <= now()` (em DML,
   `now()` é válido). Isso fecha deterministicamente a janela entre "expirou" e "o coletor apagou".
3. Um job Oban (cron, 1 min) é só backstop de higiene, não é o que garante correção.

Como se **testa** essa correção (o alvo dos testes muda junto com o desenho):

- **A constraint rejeita dois holds vivos sobrepostos** (garantia é do banco, não da validação Ash):
  inserir dois holds do mesmo profissional com intervalos que se tocam e afirmar que o segundo `INSERT`
  falha com violação de exclusão. Um par adjacente meio-aberto (um termina 10:00, outro começa 10:00)
  **não** conflita — testar os dois lados do `[)`.
- **Hold vencido NÃO bloqueia — porque a ação o apaga, não porque a constraint o ignora.** Este é o
  teste que amarra concorrência a tempo determinístico ([§3](#3-tempo-determinístico-é-o-que-torna-tudo-isto-possível)):
  com relógio injetado, criar um hold cujo `expires_at` já passou, então chamar `:offer` para o mesmo
  `(professional_id, horário)`. Afirmar que **sucede** — e afirmar *por que*: que o `DELETE`
  in-transaction do passo (2) removeu o hold vencido antes da checagem da constraint. Um teste
  complementar prova a negativa do desenho antigo: se o hold vencido **não** fosse apagado, a constraint
  (sem predicado de tempo) o trataria como vivo e bloquearia — ou seja, a correção **depende** do
  `DELETE`, não de nenhuma filtragem na constraint.
- **Teste de corrida:** dois `Task.async` chamando `:offer` para o **mesmo** `(professional_id, horário)`
  ao mesmo tempo; afirmar que **exatamente um** vence e o outro recebe o `409`/`Ash.Error` de conflito.
  Rodar N vezes para pegar a janela.

**# NAO-VERIFICADO: o `DELETE` de holds vencidos deve rodar na transação da ação `:offer`, via
`before_action` que executa um bulk destroy filtrado por `expires_at <= now()` ou uma instrução SQL
crua no repo; confirmar a API de bulk destroy do Ash 3.x e que ela participa da transação.**

Um detalhe de sandbox: testes concorrentes de verdade não podem rodar na sandbox transacional padrão
do Ecto (cada processo veria sua própria transação isolada e a constraint nunca colidiria). Esses
poucos testes precisam de modo **compartilhado/`async: false`** com limpeza explícita. **# NAO-VERIFICADO:
configurar `Ecto.Adapters.SQL.Sandbox` em modo `{:shared, ...}` ou `:manual` para esses casos;
confirmar ao scaffoldar.**

### 5.2 Remarcação simultânea (locking otimista) e a exclusion constraint com exceção do encaixe

Cada `Appointment` carrega `version` inteiro; `PATCH .../reschedule` exige a versão lida e devolve `409`
se divergiu ([04-arquitetura.md](04-arquitetura.md) §7.3). O teste:

- Ler um agendamento (version=7), simular dois `reschedule` partindo de version=7; o primeiro sobe para
  8, o segundo — ainda mandando 7 — é rejeitado com o estado atual, e o payload de erro traz "quem
  moveu" para a UI mostrar "Aline moveu este agendamento enquanto você editava".

- **Não-sobreposição por profissional, com exceção do `encaixe`:** a garantia final é outra exclusion
  constraint (`btree_gist` sobre `professional_id` + intervalo, com predicado
  `WHERE (encaixe = false AND status <> 'cancelado')`, [04-arquitetura.md](04-arquitetura.md) §7.1), o
  análogo servidor do `conflictOf` do protótipo ([`:829`](../interface/Movimento.dc.html#L829)) e de
  `checkConflict` ([`:834`](../interface/Movimento.dc.html#L834)), que hoje rodam em memória sobre uma
  lista local. Ambos ignoram `encaixe` e `cancelado` — `conflictOf` retorna `null` de cara se o próprio
  agendamento é encaixe/cancelado ([`:830`](../interface/Movimento.dc.html#L830)) e filtra `!b.encaixe`
  na busca ([`:832`](../interface/Movimento.dc.html#L832)); `checkConflict` faz o mesmo com
  `if(encaixe) return null` ([`:835`](../interface/Movimento.dc.html#L835)) e `!b.encaixe` ([`:837`](../interface/Movimento.dc.html#L837)).
  A constraint tem que refletir **exatamente** esse predicado.

**Como se testa uma exclusion constraint que tem exceção?** A exceção não é uma regra à parte — é a
cláusula `WHERE` que deixa as linhas de encaixe (e as canceladas) **fora do índice**: elas não disparam
a exclusão nem são excluídas por ninguém. O teste cobre os dois lados da fronteira do predicado:

| Cenário | Ambos no índice? | Resultado esperado |
|---|---|---|
| Dois agendamentos sobrepostos, ambos `encaixe=false`, status ativo, mesmo prof | sim | segundo `INSERT`/`reschedule` **falha** na constraint |
| Um deles `encaixe=true` | não (o encaixe está fora do `WHERE`) | **permitido** — sobreposição deliberada |
| Ambos `encaixe=true` | não | **permitido** — ambos fora do índice |
| Um deles `status='cancelado'`, sobrepondo um ativo | não | **permitido** — cancelado está fora do `WHERE` |
| Dois ativos adjacentes meio-abertos (10:00 fim / 10:00 início) | sim, mas `&&` não toca em `[)` | **permitido** — não há sobreposição |

**Encaixe também fura a capacidade de turma — e isso é regra de ação, não constraint de banco.** O
protótipo suprime o aviso de "turma cheia" quando o agendamento é encaixe: a UI só acende o alerta de
excedente com `overCap && !d.encaixe` ([`:1997`](../interface/Movimento.dc.html#L1997)), e `createAppt`
([`:1048`](../interface/Movimento.dc.html#L1048)) grava sem checar capacidade. No servidor, a validação
de capacidade de turma vive na action (não há coluna simples para uma exclusion constraint de "N por
turma"), então o teste é de nível de action: agendar numa turma **cheia** sem encaixe → recusa por
"turma cheia"; a mesma tentativa com `encaixe:true` → aceita, excedendo a capacidade. É a mesma forma de
exceção da constraint, agora expressa como bypass condicional na regra de negócio, e merece o par
pode/não-pode explícito.

---

## 6. Multi-tenant: isolamento é obrigatório para cada recurso

[ADR-003](00-decisoes.md) trava SaaS multi-clínica desde o primeiro commit, e o corolário de teste é
inegociável: **para cada recurso, existe um teste de isolamento entre tenants (IDOR).** Não é um teste
por camada de segurança genérica; é um teste por recurso, porque um recurso novo com policy esquecida é
exatamente como o vazamento acontece.

O padrão do teste é sempre o mesmo, e vale para **todo** recurso — `Patient`, `Appointment`, `Package`,
`WaitlistItem`, `SlotHold`, `Professional`, anexos, e qualquer novo:

1. Criar clínica A e clínica B, cada uma com o seu dado (paciente, agendamento, pacote…), usando
   fixtures com identidade única ([§4.2](#42-a-regra-crítica-deadlock-em-testes-concorrentes)) para não deadlockar.
2. Como ator da clínica A, tentar **ler** o recurso da clínica B por ID direto → deve voltar
   `not found` (não `forbidden` — o tenant nem deve enxergar a existência do registro alheio).
3. Como ator de A, tentar **mutar** o recurso de B → recusa.
4. Confirmar que um `clinic_id` no corpo da requisição é **ignorado**: o tenant vem da sessão/escopo,
   nunca do cliente ([04-arquitetura.md](04-arquitetura.md) §4). Mandar `clinic_id` de B numa criação
   autenticada como A **não** cria dado em B.

O caso 4 é o que pega o erro mais perigoso — confiar num campo controlado pelo cliente. Também há o
espelho no tempo real ([§4.4](#44-notifiers--tempo-real)): assinar o tópico de B e provar que uma
mutação em A **não** publica lá. E `filaVagas`/`futureConflicts` rodando com escopo de A jamais podem
enxergar agendamentos de B — como eles compõem `dayPeriods` sobre `state.appts`/`state.profs`, um
vazamento de tenant no carregamento se propaga silenciosamente para as vagas oferecidas. Um teste de
motor com dados de duas clínicas no banco e escopo de uma só fecha essa porta — é o caso onde
isolamento de tenant e correção de motor se encontram.

Estruturalmente, vale um `describe` reutilizável (uma macro ou função geradora de testes) parametrizado
pelo recurso e pela fixture, para que adicionar um recurso novo **force** o teste de isolamento por
construção — se não há como registrar o recurso sem passar a fixture ao gerador de testes de tenancy, é
difícil esquecer.

---

## 7. Front: Vitest, Playwright, e a verdade sobre os screenshots

### 7.1 Domínio puro no cliente (Vitest)

`layoutAppts` ([§2.5](#25-layoutappts--coloração-de-grafo-de-intervalos-cliente-vitest)) e os espelhos
de validação para feedback imediato ([04-arquitetura.md](04-arquitetura.md) §10, "exceção pragmática")
são funções TypeScript puras e vivem em **Vitest**, com a mesma disciplina table-driven dos motores do
servidor. Onde uma regra é espelhada dos dois lados (ex.: "fora do expediente acende vermelho antes do
round-trip"), ela é **compartilhada por contrato de teste, nunca por cópia** — os mesmos casos de
entrada/saída rodam contra a função Elixir e a função TS, garantindo que o espelho não divirja da
autoridade. É a [§8](#8-contract-testing-entre-bff-e-api) aplicada ao par cliente/servidor.

Componentes Svelte com lógica de estado (runes) ganham testes de componente com Vitest + Testing
Library. **# NAO-VERIFICADO: `@testing-library/svelte` com Svelte 5 runes — confirmar compatibilidade e
API ao montar o projeto; runes mudam a forma de montar/atualizar componentes em teste.**

### 7.2 e2e com Playwright — drag-and-drop e a alternativa por teclado

O protótipo tem interações ricas que só se provam no navegador: arrastar um agendamento entre horários e
colunas com *ghost*, pan da grade, e a recoloração das raias (`layoutAppts`) quando um bloco entra num
cluster. Playwright cobre um punhado dessas jornadas contra a stack real.

**Drag-and-drop é notoriamente frágil em e2e.** Duas frentes:

- O drag do protótipo é baseado em `PointerEvent` (`onPointerDown`/pan em `startPan`, ghost em `state.ghost`),
  não HTML5 nativo. Playwright arrasta com uma sequência `mouse.move`/`down`/`up` (ou `dragTo`), e o
  teste afirma o **resultado observável** — o agendamento passou para o novo horário/coluna e a raia
  recoloriu — não o meio do gesto. Verificar estado final, não pixels do arrasto.
- **A alternativa por teclado não é opcional, é o que torna o drag testável de forma estável e
  acessível ao mesmo tempo.** A recomendação é implementar mover-agendamento também por teclado (foco no
  bloco, setas para mudar horário/coluna, Enter confirma) e ter o e2e primário exercendo **essa** via —
  determinística, sem coordenadas de pixel, e que de brinde satisfaz o requisito de acessibilidade. O
  drag por ponteiro ganha um ou dois testes de "caminho feliz"; a lógica de mover mora no teclado, que é
  robusto. Isso inverte a fragilidade a nosso favor: a jornada crítica não depende de arrastar pixels.

Os fluxos e2e mínimos: agendar da fila (a vaga some, o item sai da fila via Channel para uma segunda
aba), remarcar com conflito (o aviso aparece), concluir/faltar destravando pelo relógio, e o
drag-por-teclado com recoloração de raia.

### 7.3 Regressão visual contra os 79 screenshots — avaliação honesta

Os 79 PNGs em `interface/screenshots/` são baseline de QA por [ADR-001](00-decisoes.md). A pergunta
honesta é: **vale fazer diff de pixel contra eles?** A resposta é **não, não diretamente**, e é
importante dizer por quê em vez de fingir que sim:

- Eles vêm de **outro framework e outro CSS**. O protótipo é React/htm — carrega `htm.umd.js` em
  [`:15`](../interface/Movimento.dc.html#L15) e liga `this.html = window.htm.bind(React.createElement)`
  em [`:295`](../interface/Movimento.dc.html#L295) — com milhares de objetos de estilo inline computados
  a partir de `theme()` ([ADR-006](00-decisoes.md) descreve exatamente essa dívida). A produção é
  Svelte 5 com utilitários Tailwind v4 sobre custom properties
  ([ADR-010](00-decisoes.md#adr-010--css-utilitário-com-tailwind-v4)) — o preflight do Tailwind
  sozinho já reseta margens e tipografia de um jeito que o protótipo não faz. Fontes,
  antialiasing, arredondamento sub-pixel e reflow serão
  **diferentes por construção** — um diff de pixel acusaria "regressão" em 100% das telas no primeiro
  dia, e um baseline que sempre falha é um baseline que se ignora.
- Vários screenshots são variações do mesmo estado (`01-final`, `02-final`, `03-final`; `fila`,
  `fila2`, `fila8`, `fila-abriu`, `fila-fix`, `fila-final`) — são o registro de uma sessão de
  prototipagem, não um conjunto curado de estados canônicos.

O uso **certo** dos 79 PNGs é como **oráculo de aceitação humana, não como assert automático**: são a
referência visual contra a qual uma pessoa confere, tela a tela, que o port do Svelte reproduz o layout
e o comportamento pretendidos. Vale montar um checklist de aceitação por tela ancorado neles (agenda,
drawer, ficha, fila, pacote, formulários, tema escuro — os prefixos dos arquivos já mapeiam as telas).

A regressão visual **automática** que vale a pena é a que **re-baseia a partir do próprio Svelte**:
assim que o build Svelte renderiza cada tela, tira-se o screenshot com o Playwright, revisa-se
manualmente contra o PNG do protótipo (aceitação humana, uma vez), e **esse** screenshot Svelte vira o
baseline. Dali em diante o diff de pixel é Svelte-contra-Svelte — comparando iguais — e pega regressão
real de CSS num PR. O tema escuro (`*-dark.png`) e os estados de fila são bons primeiros alvos por serem
visualmente densos. Em suma: os 79 PNGs entram no processo como **gabarito de tradução**, e a
ferramenta de regressão visual nasce depois, com baseline nativo.

---

## 8. Contract testing entre BFF e API

O BFF (SvelteKit) e a API (Phoenix/AshJsonApi) evoluem em repositórios/deploys separados
([ADR-005](00-decisoes.md), [ADR-008](00-decisoes.md)); o risco clássico é a API mudar a forma de uma
resposta e o BFF quebrar em produção sem que nenhum teste unitário de nenhum dos dois acuse. O contrato
JSON:API é a costura, e ela precisa de teste próprio.

Duas metades:

- **Do lado da API**, o schema JSON:API é derivado dos recursos Ash. Um teste afirma que as rotas
  publicadas ([04-arquitetura.md](04-arquitetura.md) §4 — `/api/appointments`, `/reschedule`, `/complete`,
  `/no_show`, `/packages`, `/waitlist/:id/offer`, `/availability`) respondem com o shape esperado,
  incluindo `include` de relacionamentos e o formato de erro com `source.pointer`. **# NAO-VERIFICADO:
  AshJsonApi expõe uma OpenAPI/JSON:API spec, e que ele serializa `Ash.Error.Invalid` populando
  `source.pointer` a partir do `field` do erro — validar respostas contra a spec é o caminho; confirmar
  o mecanismo (`open_api_spex`/geração do AshJsonApi) ao scaffoldar.**
- **Do lado do BFF**, os `load`/form actions são testados contra um **dublê da API que responde com
  fixtures gravadas dessas mesmas respostas reais**. Se a API mudar o contrato, o teste de contrato do
  lado da API quebra primeiro (guarda a produção); as fixtures do BFF são regeneradas a partir das
  respostas reais, mantendo os dois lados em sincronia por um artefato compartilhado, não por
  suposição. O erro que este arranjo previne é o mais caro: forma de resposta divergente entre os
  serviços, invisível para ambos isoladamente.

O caso de erro é parte do contrato tanto quanto o caso feliz: a armadilha de
[`.claude/rules/ash_phoenix.md`](../.claude/rules/ash_phoenix.md) — erros sem `field` não aparecem no
formulário — vale igual aqui. Um conflito de agenda ou turma cheia não pertence a nenhum input; o
contrato tem que carregar esses erros num canal global, e o teste de contrato verifica que o BFF os
recebe e os expõe (flash/aviso), em vez de engoli-los.

---

## 9. Cobertura: onde exigir, onde não, e o critério de "pronto"

Cobertura de linha é uma métrica ruim como meta e uma métrica útil como alarme. A política é
diferenciada por camada, não um número único para o repositório:

| Camada | Exigência | Racional |
|---|---|---|
| Os motores de regra (`dayPeriods`, `futureConflicts`, `filaVagas`, `computeSerie`, `wouldConsume`, `apptPkg`, `layoutAppts`) | **Cobertura de casos exaustiva** — toda linha da tabela de verdade, toda borda de `<=`, todo ramo. Cobertura de linha ≈100% como *consequência*, não como alvo. | São o coração; um bug aqui é silencioso e corrói dado clínico/saldo de pacote. Aqui property-based paga. |
| Policies e `field_policies` | **Par pode/não-pode por policy**, sem exceção. Todo recurso com dado LGPD tem teste de campo oculto. | Vazamento de dado sensível é o pior modo de falha do domínio ([ADR-007](00-decisoes.md)). |
| Isolamento multi-tenant | **Um teste de IDOR por recurso**, obrigatório ([§6](#6-multi-tenant-isolamento-é-obrigatório-para-cada-recurso)). | Regressão de tenancy é catastrófica e fácil de introduzir. |
| Concorrência (holds, locking, exclusion constraint) | **As duas corridas cobertas** ([§5](#5-testes-de-concorrência-as-duas-corridas-reais)), incluindo o caminho da exclusion constraint no banco e a expiração de hold via DML. | O protótipo não as trata; são requisito novo de v1. |
| Actions do Ash (orquestração) | Caminho feliz + erros de domínio nomeados. Não perseguir cobertura de branches de framework. | O Ash já é testado pelo Ash; testamos a nossa regra, não a biblioteca. |
| Componentes Svelte / UI | Lógica de estado e interações-chave (drag-por-teclado). **Não** exigir cobertura alta de marcação. | Testar `<div>` não previne bug; testar o comportamento previne. |
| e2e | Jornadas contadas, não cobertura. | Caros e frágeis por natureza; cobrem o encanamento. |
| Estilo/layout visual | Sem meta de cobertura; aceitação humana + regressão Svelte-contra-Svelte ([§7.3](#73-regressão-visual-contra-os-79-screenshots--avaliação-honesta)). | Pixel não é unidade de correção. |

**Não** exigir cobertura de: código gerado (migrations, resources declarativos onde não há lógica
custom), serialização do AshJsonApi (é a biblioteca), e marcação de componente sem lógica.

### Critério de "pronto" por fatia

Uma fatia (uma tela + suas regras) só está pronta quando, cumulativamente:

1. Os motores que ela toca têm a tabela de verdade correspondente verde, com os casos derivados da
   referência do protótipo (linha citada e verificada).
2. Toda action nova tem par de policy (pode/não-pode) e, se toca dado sensível, teste de `field_policy`.
3. Existe o teste de isolamento de tenant para todo recurso que a fatia introduz ou modifica ([§6](#6-multi-tenant-isolamento-é-obrigatório-para-cada-recurso)).
4. Se a fatia tem corrida (fila, remarcação), a corrida está coberta com teste concorrente real ([§5](#5-testes-de-concorrência-as-duas-corridas-reais)).
5. Todo motor/regra que depende de tempo recebe o relógio injetado e tem um caso com data fixa ([§3](#3-tempo-determinístico-é-o-que-torna-tudo-isto-possível));
   zero chamadas a relógio de sistema no domínio.
6. O contrato BFF↔API para as rotas da fatia tem fixture gravada de resposta real, feliz e de erro ([§8](#8-contract-testing-entre-bff-e-api)).
7. Uma jornada e2e cobre o caminho crítico da fatia, preferindo a via por teclado onde há drag.
8. A tela passou pela aceitação visual humana contra o(s) screenshot(s) correspondente(s) e tem
   baseline Svelte gravado para regressão futura ([§7.3](#73-regressão-visual-contra-os-79-screenshots--avaliação-honesta)).

Segurança e isolamento **não são uma fase do roadmap**; são critério de aceitação de cada fatia que
toca prontuário ([ADR-007](00-decisoes.md)). Uma fatia sem os itens 2, 3 e 5 não está atrasada — está
incompleta.

---

## Correções desta revisão

Reparo crítico após veredito de auditoria adversarial (**19 de 41 citações de linha eram falsas** —
números escritos de memória). Cada citação foi re-derivada do zero (`grep -n` para localizar o símbolo,
`sed -n 'Np'` para confirmar o conteúdo) antes de reescrita. O que mudou:

**Citações de linha corrigidas (número errado → número verificado):**

- `hasOwnProperty` do `profWeek`: `:843` → **`:844`** (`:843` é `if(prof.followClinic!==false){`).
- `futureConflicts`, constante `today='2026-06-25'`: `:866` → **`:865`** (`:866` é a definição de `fits`).
- `futureConflicts`, definição de `fits`: `:867` → **`:866`** (`:867` é `const out=[];`).
- `futureConflicts`, condição decisiva `fits(before)&&!fits(after)`: `:879` → **`:877`** (`:879` é `}`).
- `futureConflicts`, filtros que precedem: de um intervalo `:870–:877` para as linhas exatas —
  status **`:869`**, `a.date<today` **`:870`**, profissional inexistente **`:872`**.
- `futureConflicts`, ordenação da saída: `:882` → **`:881`** (`:882` é `}`).
- `futureConflicts`, composição com `dayPeriods`: `(:884, :886)` → **`:874`** (`before`), **`:875`**
  (`after=afterFn`) e **`:884`** (`hourConflicts`, a `afterFn` típica). `:886` (interno de `saveHours`)
  removido.
- `filaVagas`, as duas passadas: `:2571`/`:2581` → **`:2568`** (passada 1) / **`:2576`** (passada 2).
- `filaVagas`, composição com `dayPeriods`: `:2568` → **`:2562`**.
- `filaVagas`, corte por `NOW`: `:2575`/`:2586` → **`:2570`** (passada 1) / **`:2580`** (passada 2).
- `filaVagas`, janela manhã: `:2564` → **`:2542`**; janela tarde: `:2565` → **`:2543`**; sem regras
  (`-1`): `:2566` → **`:2544`**; profissional não atende: `:2569` → **`:2563`**.
- `filaVagas`, deduplicação `seen`: `:2559` → **`:2553`** (declarado) / **`:2554`** (usado no `add`). O
  `seen` de `:247` é outro, do gerador de seed, não este.
- `filaVagas`, teto `CAP=50`: `:2596` → constante em **`:2533`**, corte `if(out.length>=CAP) break` em
  **`:2588`** (`:2596` é, na verdade, `offerVaga`, que está corretamente citado em [§5](#5-testes-de-concorrência-as-duas-corridas-reais)).
- `filaVagas`, ordenação final: `:2599` → **`:2591`** (`:2599` é interno de `filaDispCell`).
- `computeSerie`, teste de feriado `holidays.some(...tipo!=='horario')`: `:1092` → **`:1090`** (`:1092`
  é `if(!fer) count++`).
- `computeSerie`, pulo do âncora `if(!d.inclusive)`: `:1084` → **`:1083`** (`:1084` é
  `let count=0; let guard=0;`).
- `§3`, `futureConflicts filtra por a.date < today`: `:872` → **`:870`**.

**Citações reconferidas e mantidas (estavam corretas):** `dayPeriods` `:854`, `profWeek` `:840`,
`dateException` `:850`, `profException` `:852`, `if(ex&&ex.tipo!=='horario') return null` `:856`,
`if(ex) return ex.periods` `:859`, `futureConflicts` `:864`, `filaVagas` `:2531`, `filaRegraExpirada`
`:2515`, `computeSerie` `:1081`, `layoutAppts` `:1576`, `flush` em `:1582`, `hoje()` `:1098`, `:1804`,
`conflictOf` `:829`, `checkConflict` `:834`, `createAppt` `:1048`, `offerVaga` `:2596`, `wouldConsume`
`:1104`, `apptPkg` `:1110`, e o intervalo de seed `:43–:263`.

**DDL corrigido — `SlotHold` ([§5.1](#51-hold-de-vaga-na-fila-exclusion-constraint--expiração-via-dml)).**
A afirmação de que a exclusion constraint "filtra por `expires_at > now()`" era **DDL inválido**:
`now()` é `STABLE`, não `IMMUTABLE`, e o Postgres recusa o predicado. Alinhado a 04 §7.2: constraint
**sem** cláusula de tempo + `DELETE ... WHERE expires_at <= now()` in-transaction antes do insert +
Oban só como backstop. Os testes foram reescritos para provar a correção pelo caminho certo — o hold
vencido não bloqueia **porque a ação o apaga**, não porque a constraint o ignora.

**Referências de seção para 04-arquitetura.md corrigidas.** Concorrência é a **§7** (não §5): ajustadas
as três menções ([§5](#5-testes-de-concorrência-as-duas-corridas-reais) intro → 04 §7; hold → 04 §7.2;
locking → 04 §7.3). Também: notifier/PubSub `§4 → §6`; tenant fora do cliente `§3 → §4`; rotas do
contrato `§3 → §4`; "exceção pragmática" `§2 → §10`; seed do PRNG `§7 → §12`.

**Afirmações sem proveniência resolvidas.**

- **`702`:** contado com `grep -n`. Aparece **literalmente 8 vezes** (`:130, :285, :828, :1046, :1586,
  :1600, :1804, :2533`), não "pelo menos quatro" — a [§3](#3-tempo-determinístico-é-o-que-torna-tudo-isto-possível)
  agora dá o número exato e classifica cada ocorrência (2 definições de `NOW`, 3 de scroll, 3 de decisão
  de negócio).
- **React/htm:** confirmado e citado — `htm.umd.js` carregado em `:15`, ligado a `React.createElement`
  em `:295` ([§7.3](#73-regressão-visual-contra-os-79-screenshots--avaliação-honesta)).
- **Número cromático:** reescrito como teorema correto ([§2.5](#25-layoutappts--coloração-de-grafo-de-intervalos-cliente-vitest)) —
  grafos de intervalos são **perfeitos**, logo χ = ω (clique máxima = pico de simultaneidade); a property
  passa a exigir **igualdade** (`maxLanes` = pico), não apenas `≥`.
- **79 screenshots:** mantido; contado por `ls | wc -l`. (00-decisoes.md, que dizia 86, já corrigido.)

**Cobertura que faltava — seções novas.**

- **[§2.6](#26-wouldconsume--quando-a-falta-debita-o-pacote-tabela-de-verdade) `wouldConsume` (`:1104`)** —
  tabela de verdade de 10 linhas cobrindo status × `faltaJustificada` × `faltaPunitiva` do pacote × ajuste
  global, incluindo o fallback `pkgPunitivo` quando o pacote não declara `faltaPunitiva`.
- **[§2.7](#27-apptpkg-em-turma-multi-pacote--armadilha-do-primeiro-dono-regressão) `apptPkg` (`:1110`)** —
  teste de regressão para turma multi-pacote: `apptPkg` devolve **só o primeiro** dono; o débito/ajuste
  em massa precisa iterar todos, e o teste falha contra o port ingênuo.
- **Encaixe como exceção de exclusion constraint ([§5.2](#52-remarcação-simultânea-locking-otimista-e-a-exclusion-constraint-com-exceção-do-encaixe))** —
  como se testa uma constraint com `WHERE`: tabela de 5 cenários nos dois lados do predicado, mais o
  bypass de capacidade de turma (regra de action, `overCap && !d.encaixe` em `:1997`).
- **IDOR multi-tenant por recurso ([§6](#6-multi-tenant-isolamento-é-obrigatório-para-cada-recurso))** —
  reforçado como obrigatório para **cada** recurso (lista explícita), com o cruzamento motor×tenant.

**Mantido o que estava certo:** a pirâmide nos dois runtimes, a matemática dos motores, a estratégia de
tempo determinístico, as tabelas de verdade conceituais de `dayPeriods`/`computeSerie`/`layoutAppts`, e a
política de cobertura por camada — o problema da revisão anterior era proveniência, não raciocínio.
