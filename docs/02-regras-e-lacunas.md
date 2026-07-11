# Regras de Negócio e Lacunas

Este é o documento canônico das regras de negócio do Movimento e do catálogo de
divergências entre o protótipo e a produção. Ele existe porque a [ADR-001](00-decisoes.md)
define o protótipo (`interface/Movimento.dc.html`) como especificação executável: toda
regra de produção cita a linha de origem, e toda divergência deliberada vira um `GAP-nn`
**aqui**. O [08-roadmap.md](08-roadmap.md) já referencia esses gaps pela evidência concreta
(sem número), delegando a este documento o catálogo formal — a numeração `GAP-nn` abaixo é a
primeira a existir e é a que os demais documentos passam a citar.

> **Nota de proveniência.** Cada citação de linha do protótipo foi aberta e conferida com
> `sed`/`grep` antes de ser escrita. Snippets de API de bibliotecas (Ash, AshCloak,
> AshPaperTrail, Oban etc.) **não** podem ser confirmados contra o hexdocs — não há projeto
> Elixir neste repositório — e por isso a Parte 3 **referencia** as seções já escritas de
> [04-arquitetura.md](04-arquitetura.md) e [06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md),
> que carregam os marcadores `# NAO-VERIFICADO`, em vez de reescrever a API. Onde eu afirmo
> comportamento de biblioteca sem essa cobertura, marco `# NAO-VERIFICADO`. Fatos do
> protótipo (contagens, constantes, número de telas) são verificados: são **79** screenshots
> em `interface/screenshots/` (conferido por `ls`), não 86; a constante do "agora" é
> `NOW = 702` (11:42), aparecendo no seed em [`:130`](../interface/Movimento.dc.html#L130) e
> em `filaVagas` em [`:2533`](../interface/Movimento.dc.html#L2533).

---

## Parte 1 — Regras vigentes

Cada regra abaixo é enunciada como especificação normativa ("O sistema deve…"), com a linha
do protótipo entre parênteses como proveniência. **Não** é leitura de código: é o contrato
que a produção precisa reproduzir. As duas regras mais frágeis numa reimplementação —
`dayPeriods` (§1.2) e `futureConflicts` (§1.4) — recebem pseudocódigo determinístico e tabela
de casos, reconciliados com [07-estrategia-de-testes.md](07-estrategia-de-testes.md) §2.1 e §2.2.

### 1.1 Agenda e slots

- **RN-01.** Um agendamento carrega ao menos `{id, profId, typeId, start, dur, date, status}`,
  com `start` e `dur` em **minutos desde a meia-noite** e `date` como string `YYYY-MM-DD`
  ([`:150`](../interface/Movimento.dc.html#L150), [`:152`](../interface/Movimento.dc.html#L152)).
  Os mesmos objetos-semente carregam também a ligação com o paciente — `patientId` (individual,
  [`:152`](../interface/Movimento.dc.html#L152)) ou `patientIds` (turma,
  [`:150`](../interface/Movimento.dc.html#L150); ver RN-33) — e a marca `encaixe` (default
  `false`), que é *load-bearing* no conflito ([`:835`](../interface/Movimento.dc.html#L835),
  [`:837`](../interface/Movimento.dc.html#L837); ver RN-12). A enumeração de campos **não** é
  exaustiva. A produção troca `start`/`dur`/`date` por um intervalo com fuso (ver Parte 3), mas a
  unidade lógica de tempo permanece o minuto.
- **RN-02.** A duração padrão de um agendamento é a **duração do tipo de atendimento**
  (`type.dur`), não um valor da agenda: `t1..t3` e `t4` duram 50 min, `t5` (Reavaliação)
  dura 30 ([`:70`](../interface/Movimento.dc.html#L70)–[`:74`](../interface/Movimento.dc.html#L74)).
- **RN-03.** O horário da agenda visível vai das **08:00 (480) às 18:00 (1080)**, com o
  arrasto limitado a essa faixa ([`:1248`](../interface/Movimento.dc.html#L1248) —
  `Math.max(480,Math.min(1080-a.dur,…))`). Este é um limite de renderização do protótipo, não
  uma regra de negócio: a faixa real de atendimento é derivada da disponibilidade (§1.2).
- **RN-04.** O status de um agendamento pertence ao conjunto
  `{agendado, confirmado, em_atendimento, concluido, faltou, cancelado}`
  ([`:135`](../interface/Movimento.dc.html#L135), [`:144`](../interface/Movimento.dc.html#L144)–[`:146`](../interface/Movimento.dc.html#L146)).
  Cada transição tem efeito distinto (§1.6) — por isso a produção as expõe como **ações
  nomeadas**, não como um `PATCH` genérico ([04-arquitetura.md](04-arquitetura.md) §4).
- **RN-05.** Sessões de um pacote **pausado** carregam a marca `pkgHold` e ficam **fora da
  agenda e de todas as contagens**, mas permanecem vinculadas ao pacote
  ([`:825`](../interface/Movimento.dc.html#L825) — `dayAppts` filtra `!a.pkgHold`).
- **RN-06.** Criar um agendamento remove o item correspondente da fila de espera quando a
  criação veio de uma oferta de vaga (`_fromFila`)
  ([`:1062`](../interface/Movimento.dc.html#L1062)).

### 1.2 Disponibilidade e precedência — `dayPeriods` (4 camadas)

Referência: [`:854`](../interface/Movimento.dc.html#L854), com `profWeek`
([`:840`](../interface/Movimento.dc.html#L840)), `dateException`
([`:850`](../interface/Movimento.dc.html#L850)) e `profException`
([`:852`](../interface/Movimento.dc.html#L852)).

- **RN-07.** A disponibilidade de um profissional numa data é resolvida por **precedência de
  quatro camadas**, e a **primeira** camada que decide vence. O sistema deve reproduzir
  exatamente esta ordem:

```
dayPeriods(prof, date):
  ex  = exceção de data da CLÍNICA em `date`            # feriado ou horário especial
  (A) se ex existe e ex.tipo != 'horario':  → null      # clínica fechada — ninguém atende
  pex = exceção de data do PROFISSIONAL em `date`        # folga ou horário pontual
  (B) se pex existe:  → pex.tipo=='horario' ? pex.periods : null
  (C) se ex existe:   → ex.periods                       # horário especial da clínica
  (D) senão:          → profWeek(prof, dia_da_semana)    # horário semanal
```

```
profWeek(prof, dow):
  se prof.followClinic != false:                         # "segue a clínica"
     se avail TEM a chave dow:  → avail[dow]              # override do prof (array OU null=fechado)
     senão:                     → hours[dow] || null      # herda o horário da clínica
  senão:                                                  # NÃO segue a clínica
     → avail[dow] || null                                 # só o horário próprio conta
```

- **RN-08.** O **fechamento da clínica** (camada A, feriado/exceção com `tipo != 'horario'`)
  vence tudo, inclusive um atendimento pontual do profissional
  ([`:856`](../interface/Movimento.dc.html#L856) — o `return null` vem **antes** de `pex`).
- **RN-09.** A exceção de data do **profissional** (camada B) vence o **horário especial** da
  clínica (camada C) ([`:858`](../interface/Movimento.dc.html#L858) vem antes de
  [`:859`](../interface/Movimento.dc.html#L859)). Ou seja: feriado fecha para todos; um dia de
  horário estendido da clínica **cede** ao pontual do profissional.
- **RN-10.** No horário semanal (camada D), a distinção entre "o profissional declarou
  explicitamente que não atende neste dia" (`avail[dow] = null`, chave **presente**) e "o
  profissional não disse nada, então herda a clínica" (chave **ausente**) é **significativa** e
  é feita por `hasOwnProperty` ([`:844`](../interface/Movimento.dc.html#L844)). A produção
  precisa preservar essa diferença (em Elixir, `Map.has_key?/2`, não `Map.get/2`; provável
  modelagem: um valor `:fechado` distinto de `nil`).

**Tabela de verdade.** Colunas: **A** = exceção da clínica (`—`/`fecha`/`esp`); **B** =
exceção do prof (`—`/`folga`/`pont`); **fc** = `followClinic`; **av[dow]** = override semanal
do prof (`—` ausente · `null` presente-com-null · `[..]` array); **h[dow]** = horário semanal
da clínica; **decide** = camada decisória.

| # | A | B | fc | av[dow] | h[dow] | → resultado | decide |
|---|---|---|----|---------|--------|-------------|--------|
| 1 | fecha | — | — | — | [08–18] | `null` (fechado) | A |
| 2 | fecha | pont [08–12] | — | — | — | `null` (fechado) | A — feriado vence pontual do prof |
| 3 | — | folga | true | [09–12] | [08–18] | `null` | B |
| 4 | esp [14–18] | folga | true | — | [08–18] | `null` | B — folga vence horário especial |
| 5 | — | pont [08–12] | true | — | [08–18] | `[08–12]` | B |
| 6 | esp [14–18] | pont [08–12] | true | [09–12] | [08–18] | `[08–12]` | B — pontual vence especial |
| 7 | esp [14–18] | — | true | [09–12] | [08–18] | `[14–18]` | C — especial vence semanal |
| 8 | esp [14–18] | — | false | [09–12] | [08–18] | `[14–18]` | C — especial vence até `fc=false` |
| 9 | — | — | true | [09–12] | [08–18] | `[09–12]` | D — override do prof |
| 10 | — | — | true | `null` | [08–18] | `null` | D — prof fecha o dia mesmo seguindo a clínica |
| 11 | — | — | true | — | [08–18] | `[08–18]` | D — herda a clínica |
| 12 | — | — | true | — | `null` | `null` | D — clínica fechada nesse dia da semana |
| 13 | — | — | false | [08–12] | [08–18] | `[08–12]` | D — ignora a clínica |
| 14 | — | — | false | — | [08–18] | `null` | D — não segue e não configurou → sem atendimento |
| 15 | — | — | false | `null` | [08–18] | `null` | D — idem 14 (null e ausente coincidem quando `fc=false`) |

**Reconciliação com [07 §2.1](07-estrategia-de-testes.md).** Esta tabela é a **mesma** tabela de
verdade das 15 linhas do 07 §2.1, com os mesmos resultados e as mesmas camadas decisórias.
As duas assimetrias que o 07 destaca (RN-08 e RN-09 acima; e o par 10/11 que valida o
`hasOwnProperty`) estão idênticas. **Não há divergência**: o 07 é a fonte de teste e este
documento é a fonte normativa da mesma regra.

### 1.3 Conflito e encaixe

Referência: `checkConflict` ([`:834`](../interface/Movimento.dc.html#L834)), `conflictOf`
([`:829`](../interface/Movimento.dc.html#L829)).

- **RN-11.** Dois agendamentos **do mesmo profissional** conflitam quando seus intervalos se
  sobrepõem: `start < (b.start+b.dur) && b.start < end`
  ([`:837`](../interface/Movimento.dc.html#L837)). O conflito é **por profissional**, e apenas
  por profissional — não há noção de sala nem de equipamento (ver GAP-15).
- **RN-12.** Um agendamento marcado **`encaixe`** é uma sobreposição **deliberada** e é imune
  ao conflito nos dois sentidos: um encaixe nunca dispara conflito ao ser criado
  (`if(encaixe) return null`, [`:835`](../interface/Movimento.dc.html#L835)) **e** encaixes
  existentes são ignorados na busca por conflito (`!b.encaixe`,
  [`:837`](../interface/Movimento.dc.html#L837)). A intenção de produto é explícita na UI:
  "Marque 'Encaixe' para exceder a capacidade" ([`:1997`](../interface/Movimento.dc.html#L1997)).
- **RN-13.** Agendamentos **cancelados** não participam de conflito
  ([`:837`](../interface/Movimento.dc.html#L837) — `b.status!=='cancelado'`).
- **RN-14.** A garantia de disponibilidade (dentro do expediente) é separada da garantia de
  não-conflito: `checkAvail` ([`:894`](../interface/Movimento.dc.html#L894)) resolve
  `dayPeriods` (§1.2) e verifica se o agendamento **inteiro** cabe em algum período
  (`start>=p[0] && end<=p[1]`, [`:903`](../interface/Movimento.dc.html#L903)); `checkConflict`
  verifica sobreposição. As duas checagens são independentes e ambas são necessárias antes de
  aceitar um agendamento — o protótipo **não** aplica as duas em todo caminho de escrita (ver
  GAP-03).
- **Nota (grupo não passa por conflito).** Para tipos `grupo`, o fluxo de criação **não** chama
  `checkConflict` (o modal tem o gate `!isGroup`, [`:1978`](../interface/Movimento.dc.html#L1978)):
  a sobreposição no mesmo slot/tipo é resolvida por **merge** (RN-33), não por conflito, e a
  capacidade (RN-36) é a única barreira.

### 1.4 Impacto retroativo — `futureConflicts`

Referência: [`:864`](../interface/Movimento.dc.html#L864). Constante `today = '2026-06-25'`
([`:865`](../interface/Movimento.dc.html#L865)).

- **RN-15.** Ao mudar o horário de uma clínica ou de um profissional, o sistema deve calcular
  quais agendamentos **futuros e ativos** deixariam de caber. A regra é cirúrgica: entra na
  lista **apenas** quem "cabia no horário atual **e** deixa de caber no novo"
  (`fits(before,a) && !fits(after,a)`, [`:877`](../interface/Movimento.dc.html#L877)), onde
  `fits` exige que o agendamento inteiro caiba em algum período
  ([`:866`](../interface/Movimento.dc.html#L866)).

```
futureConflicts(afterFn, filterFn):
  today = data-âncora (hoje, no fuso da clínica)          # ver Parte 3
  para cada agendamento a:
    se a.status ∈ {cancelado, concluido, faltou}: pula     # já resolvido
    se a.date < today: pula                                # só hoje em diante (< é estrito)
    prof = profissional de a; se não existe: pula
    se filterFn e não filterFn(a,prof): pula               # ex.: só um profissional
    before = dayPeriods(prof, a.date)                      # períodos ANTES da mudança
    after  = afterFn(a, prof)                              # períodos DEPOIS (rascunho)
    se fits(before,a) e não fits(after,a):
       inclui a, com motivo:
         "Sem atendimento após a mudança"       se after vazio/null
         "Fora do novo expediente (…)"          caso contrário
  ordena por (data, start)
```

- **RN-16.** `futureConflicts` **compõe** `dayPeriods`: `before` vem de `dayPeriods` com o
  horário atual e `after` de `dayPeriods` com o rascunho
  ([`:874`](../interface/Movimento.dc.html#L874)–[`:875`](../interface/Movimento.dc.html#L875)).
  Tem **três** consumidores: `hourConflicts` ([`:884`](../interface/Movimento.dc.html#L884)), o
  guarda de `saveProf` ([`:1198`](../interface/Movimento.dc.html#L1198)) e `addHoliday`
  ([`:1220`](../interface/Movimento.dc.html#L1220)) — este último guarda a criação de uma
  **exceção de data da clínica** (abre o modal `horarioConflitos`, `scope:'excecao'`,
  [`:1221`](../interface/Movimento.dc.html#L1221)). O `simulate` de `addHoliday` carrega uma
  **precedência** própria: na data afetada, uma exceção de data já existente do **profissional**
  mantém prioridade sobre a nova exceção da clínica sendo simulada
  ([`:1216`](../interface/Movimento.dc.html#L1216)–[`:1217`](../interface/Movimento.dc.html#L1217))
  e, só na ausência dela, o tipo da nova exceção decide o `after`
  ([`:1218`](../interface/Movimento.dc.html#L1218)). Um erro em §1.2 propaga para cá.
- **RN-17.** A saída é ordenada por data e depois por `start`
  ([`:881`](../interface/Movimento.dc.html#L881)) — ordenação é comportamento observável.

**Tabela de casos de borda** (reconciliada com [07 §2.2](07-estrategia-de-testes.md)):

| Situação | `before` | `after` | Entra? |
|---|---|---|---|
| Já não cabia antes (encaixe fora do expediente) | não cabe | não cabe | **Não** — só pega "cabia e deixou" |
| Cabia e continua cabendo | cabe | cabe | Não |
| Cabia; depois o dia fica fechado | cabe | `null`/`[]` | **Sim** — "Sem atendimento após a mudança" |
| Cabia; expediente encolheu e ele fica de fora | cabe | cabe parcial (ele não) | **Sim** — "Fora do novo expediente (…)" |
| Termina exatamente na borda (`start+dur == fim`) | cabe (`<=`) | — | limite fechado à direita — o `<=` conta |
| Agendamento **hoje** (`a.date == today`) | — | — | incluído (`< today` é estrito) |
| Agendamento **ontem** | — | — | excluído |
| Status resolvido (concluído/faltou/cancelado) | — | — | excluído sempre |

**Reconciliação com [07 §2.2](07-estrategia-de-testes.md).** Idêntica: a condição decisiva
(`fits(before) && !fits(after)`), os filtros anteriores (status resolvido, `a.date < today`
estrito, profissional inexistente), a borda `<=` do fim de período e a ordenação por
`(data, start)` são exatamente os do 07. **Não há divergência.**

### 1.5 Pacotes

O pacote é a unidade central de uma clínica de fisioterapia. Cada sessão de pacote é um
**agendamento real** na agenda, vinculado por `pkgId` (individual) ou `pkgOf` (turma) — a
agenda, o contador de sessões e o histórico derivam desses agendamentos, que são a fonte única
de verdade ([`:210`](../interface/Movimento.dc.html#L210)–[`:212`](../interface/Movimento.dc.html#L212)).

- **RN-18. Criação e série.** Criar um pacote materializa uma **série de sessões** por
  `computeSerie` ([`:1081`](../interface/Movimento.dc.html#L1081)), a partir de uma grade
  `{dows, horarios, profId}` ([`:358`](../interface/Movimento.dc.html#L358)). Cada sessão vira
  um agendamento `agendado` com o `pkgId` do pacote
  ([`:355`](../interface/Movimento.dc.html#L355)). Antes de gravar, a criação **valida cada
  ocorrência** por `occIssue` ([`:703`](../interface/Movimento.dc.html#L703)), com os desfechos
  `fora`/`cheia`/`join`/`conflito`; o salvamento fica **bloqueado** salvo `!issues.length||d.forcar`
  ([`:754`](../interface/Movimento.dc.html#L754)) e o checkbox "Agendar mesmo assim (encaixe)"
  ([`:750`](../interface/Movimento.dc.html#L750)) grava as sessões conflitantes como `encaixe`.
  O tratamento de código diverge entre turma (`encaixe: bad && forcar`,
  [`:352`](../interface/Movimento.dc.html#L352)) e individual (`encaixe: bad`,
  [`:355`](../interface/Movimento.dc.html#L355)), mas o *save-gate* torna o efeito prático
  equivalente no fluxo da UI — inconsistência latente a corrigir na reimplementação.
- **RN-19. Feriado pula e ESTENDE a série.** `computeSerie` empurra um slot para a saída
  **sempre** que o dia bate com `dows`, mas só incrementa o contador de sessões úteis
  (`count`) se o dia **não** for feriado ([`:1088`](../interface/Movimento.dc.html#L1088)–[`:1092`](../interface/Movimento.dc.html#L1092)).
  Consequência: uma série de N sessões se **estende** no calendário para acomodar feriados, e a
  saída inclui os feriados marcados (`feriado:true`) para a UI mostrar o pulo.
- **RN-20. Feriado é `tipo != 'horario'`.** Um dia de **horário especial** da clínica
  (`tipo == 'horario'`) **não** é feriado e conta como sessão normal
  ([`:1090`](../interface/Movimento.dc.html#L1090) — `h.tipo!=='horario'`). É a mesma noção de
  feriado de §1.2 (RN-08), e uma reimplementação que trate *qualquer* registro em `holidays`
  como pulo gera séries longas demais.
- **RN-21. Âncora inclusiva ou não.** Séries **novas** incluem a data-âncora; séries "que
  começam depois" (renovação, `inclusive == false`) **pulam** o dia-âncora
  ([`:1083`](../interface/Movimento.dc.html#L1083)). A válvula `guard < 400`
  ([`:1086`](../interface/Movimento.dc.html#L1086)) impede laço infinito com `dows` vazio.
- **RN-22. Renovação (protótipo) → sem renovação (produção).** No protótipo, renovar marca o
  pacote anterior como `renovado` e cria um **sucessor** com `renovadoDe`
  ([`:362`](../interface/Movimento.dc.html#L362), [`:358`](../interface/Movimento.dc.html#L358)).
  **Divergência deliberada da produção ([ADR-011](00-decisoes.md), 2026-07-10):** não há
  renovação nem sucessor — o `total` de sessões é **editável (+/−) a qualquer momento** no mesmo
  pacote (via `add_session`/`remove_session`). A produção **não** reproduz o `renovadoDe`, a ação
  `:renew` nem o status `:renovado`.
- **RN-23. Pausa.** Pausar um pacote marca suas sessões futuras (`date >= hoje`, `agendado` ou
  `confirmado`) com `pkgHold` — elas somem da agenda (RN-05) — e grava `status:'pausado'` com
  um `retomaEm` **fixo em +21 dias** ([`:554`](../interface/Movimento.dc.html#L554)–[`:557`](../interface/Movimento.dc.html#L557)).
  O +21 é hardcoded e `retomaEm` é apenas um rótulo (ver GAP-08).
- **RN-24. Retomada.** Retomar apenas remove o `pkgHold` das sessões e as devolve **nas datas
  originais**, muda o status para `ativo` e apaga `retomaEm`
  ([`:561`](../interface/Movimento.dc.html#L561)–[`:566`](../interface/Movimento.dc.html#L566)).
  **Não reprojeta datas** — após uma pausa longa, devolve sessões em datas já passadas (GAP-08).
- **RN-25. Cancelamento de pacote.** Cancelar marca as sessões futuras (`date >= hoje`,
  `agendado`/`confirmado`/`pkgHold`) como `cancelado`, liberando-as da agenda, e o pacote como
  `cancelado` ([`:568`](../interface/Movimento.dc.html#L568)–[`:574`](../interface/Movimento.dc.html#L574)).
  Sessões já passadas não são tocadas.
- **RN-26. Ajuste de grade.** Editar a grade de um pacote (`pkgSaveGrade`,
  [`:578`](../interface/Movimento.dc.html#L578)–[`:588`](../interface/Movimento.dc.html#L588);
  `openPkgGrade`, [`:577`](../interface/Movimento.dc.html#L577), só abre o modal) **não** é mera
  atualização de metadados: além de gravar `dows`/`horarios`/`profId` na grade, ele **remarca a
  série**. Coleta as sessões futuras não resolvidas (`date >= hoje`,
  `agendado`/`confirmado`/`pkgHold`, via `pkgAppts`), **remove-as** (`removeIds`,
  [`:586`](../interface/Movimento.dc.html#L586)) e **regenera** `nCount` novas sessões a partir de
  hoje conforme a nova grade, pulando feriados ([`:585`](../interface/Movimento.dc.html#L585)) e
  preservando `pkgHold` quando `anyHold`. O toast confirma "N sessões remarcadas na agenda"
  ([`:588`](../interface/Movimento.dc.html#L588)) e o modal avisa que trocar dia/horário/profissional
  remarca o paciente na agenda ([`:668`](../interface/Movimento.dc.html#L668)).
- **RN-27. Ajuste em massa.** `applyMassaPacote` ([`:1149`](../interface/Movimento.dc.html#L1149))
  reaplica profissional e/ou horário às sessões futuras de um pacote conforme um escopo
  (`esta` / `proximas` / todas, [`:1144`](../interface/Movimento.dc.html#L1144)), atualizando
  também a grade do pacote ([`:1163`](../interface/Movimento.dc.html#L1163)–[`:1167`](../interface/Movimento.dc.html#L1167)).
  O conjunto afetado (`massaAffected`, [`:1140`](../interface/Movimento.dc.html#L1140)) só
  considera sessões `date >= hoje` e não-resolvidas. **Este fluxo opera sobre um único pacote**
  — o retornado por `apptPkg` — e por isso é silenciosamente incompleto em turmas
  multi-pacote (ver GAP-07). O ponto de entrada do drawer para esse fluxo, `openMassaPacote`, é
  **código órfão** (ver GAP-04).
- **RN-28. Contador de sessões é derivado.** O número de sessões usadas é calculado ao vivo por
  `pkgUsadas` ([`:326`](../interface/Movimento.dc.html#L326)), somando `wouldConsume` (§1.6)
  sobre os agendamentos do pacote (`pkgAppts`, [`:330`](../interface/Movimento.dc.html#L330)) —
  **não** é um campo denormalizado. O `usadas` presente no objeto pacote é apenas semente.

### 1.6 Consumo de sessão e falta punitiva

Referência: `wouldConsume` ([`:1104`](../interface/Movimento.dc.html#L1104)), `pkgPunitivo`
([`:1103`](../interface/Movimento.dc.html#L1103)).

- **RN-29. Concluído sempre debita.** Uma sessão marcada `concluido` **sempre** consome uma
  sessão do pacote ([`:1105`](../interface/Movimento.dc.html#L1105)).
- **RN-30. Falta debita só se punitiva e não justificada.** Uma **falta** consome uma sessão
  **apenas** quando o pacote é punitivo **e** a falta não está justificada
  ([`:1106`](../interface/Movimento.dc.html#L1106) — `if(a.faltaJustificada) return false;
  return this.pkgPunitivo(pk)`).
- **RN-31. Punição por pacote, com fallback global.** "Punitiva" é uma propriedade **do
  pacote** (`faltaPunitiva`); quando ela não está definida, cai no padrão global
  `settings.noShowConsome` ([`:1103`](../interface/Movimento.dc.html#L1103)). Esse padrão global
  **é lido** (contraste com `settings.slot`, que não é — GAP-02): alimenta o valor inicial de
  `faltaPunitiva` ao criar um pacote ([`:335`](../interface/Movimento.dc.html#L335)) e é
  editável em Configurações ([`:3223`](../interface/Movimento.dc.html#L3223)).
- **RN-32. Justificar falta é reversível e tem efeito duplo.** Justificar uma falta
  (`justificarFalta`, [`:1121`](../interface/Movimento.dc.html#L1121)) faz a sessão deixar de
  debitar o pacote **e** deixar de contar para o paciente; desfazer reverte os dois. O efeito
  sobre o pacote é automático (via RN-30); o efeito sobre `patient.faltas` é um ajuste
  denormalizado `±1` ([`:1126`](../interface/Movimento.dc.html#L1126)) — ver GAP-09.

### 1.7 Grupo / turma

- **RN-33. Turma é um agendamento com muitos pacientes.** Um tipo `grupo` (ex.: Pilates,
  `cap:4`, [`:73`](../interface/Movimento.dc.html#L73)) gera **um** agendamento com um array
  `patientIds` ([`:1057`](../interface/Movimento.dc.html#L1057)), rotulado "…em grupo" na UI
  ([`:1815`](../interface/Movimento.dc.html#L1815)). Participantes entram/saem por
  `addParticipant`/`removeParticipant` ([`:1068`](../interface/Movimento.dc.html#L1068)–[`:1069`](../interface/Movimento.dc.html#L1069)).
  **Merge idempotente na criação:** criar um agendamento/pacote de grupo num slot onde já existe
  uma turma não-cancelada com o mesmo `profId`+`date`+`start`+`typeId` **ADICIONA** o(s)
  paciente(s) ao `patientIds` daquele bloco — não cria um segundo bloco (`createAppt`,
  [`:1055`](../interface/Movimento.dc.html#L1055)–[`:1056`](../interface/Movimento.dc.html#L1056);
  `createPacote`, que também grava `pkgOf[patientId]`,
  [`:349`](../interface/Movimento.dc.html#L349)–[`:350`](../interface/Movimento.dc.html#L350)). A
  citação [`:1057`](../interface/Movimento.dc.html#L1057) acima é o ramo de criação de bloco novo
  (quando não há coincidência).
- **RN-34. Presença é da turma, não do participante.** O agendamento de turma tem **um único
  `status`** compartilhado por todos os participantes. Marcar a turma como `concluido`/`faltou`
  aplica o estado ao bloco inteiro; não existe presença individual por participante (ver GAP-06).
- **RN-35. Turma pode ter pacotes distintos por participante.** Quando a turma é gerada por
  criação de pacote, cada participante carrega seu pacote em `pkgOf[patientId]`
  ([`:350`](../interface/Movimento.dc.html#L350), [`:352`](../interface/Movimento.dc.html#L352)).
  O contador `pkgUsadas` (RN-28) percorre corretamente cada pacote via `pkgOf`
  ([`:330`](../interface/Movimento.dc.html#L330)), mas `apptPkg`
  ([`:1113`](../interface/Movimento.dc.html#L1113)) devolve **só o primeiro** — a raiz do GAP-07.
  Turmas criadas por `createAppt` (não por pacote) não têm `pkgOf`, e para elas `apptPkg`
  devolve `null` ([`:1114`](../interface/Movimento.dc.html#L1114)).
- **RN-36. Capacidade da turma.** A capacidade é `type.cap` (ou `settings.capPilates`, padrão 4)
  ([`:341`](../interface/Movimento.dc.html#L341)). A UI descreve o encaixe (RN-12) como a via de
  exceder a capacidade.

### 1.8 Fila de espera e motor de vagas — `filaVagas`

Referência: [`:2531`](../interface/Movimento.dc.html#L2531). Constantes na primeira linha do
corpo: `TODAY='2026-06-25', NOW=702, DUR=50, DAYS=14, STEP=30, CAP=50`
([`:2533`](../interface/Movimento.dc.html#L2533)).

- **RN-37. Item de fila.** Um item traz `{patientId, prio, profIds, janela, dias, obs, regras}`
  ([`:163`](../interface/Movimento.dc.html#L163)). `profIds` são os profissionais preferidos
  (vazio ⇒ todos os ativos, [`:2536`](../interface/Movimento.dc.html#L2536)); `janela` é
  `manhã`/`tarde`/`qualquer`; `regras` são disponibilidades por **dia-da-semana** ou por **data
  específica**, cada uma com períodos.
- **RN-38. Regra por data expira.** Uma regra `tipo:'data'` com `data < TODAY` é filtrada fora
  (`filaRegraExpirada`, [`:2515`](../interface/Movimento.dc.html#L2515)).
- **RN-39. Janela.** `manhã` rejeita `start >= 720` (12:00); `tarde` rejeita `start < 720`
  ([`:2542`](../interface/Movimento.dc.html#L2542)–[`:2543`](../interface/Movimento.dc.html#L2543)).
  Sem regras, a checagem de regra passa livre (`fitsWin` devolve `-1`, não `null`,
  [`:2544`](../interface/Movimento.dc.html#L2544)).
- **RN-40. Varredura de 14 dias e duas passadas.** O motor varre `DAYS=14` dias a partir de
  `TODAY` × profissionais preferidos ([`:2555`](../interface/Movimento.dc.html#L2555)), pulando
  quem não atende no dia (`dayPeriods` vazio ⇒ `continue`,
  [`:2562`](../interface/Movimento.dc.html#L2562)–[`:2563`](../interface/Movimento.dc.html#L2563)),
  com **duas passadas de semânticas distintas**:
  - **Passada 1 — vagas que abriram** (`freed:true`): itera os agendamentos `cancelado`/`faltou`
    do profissional e emite uma vaga no **horário exato** liberado, desde que caiba no
    expediente (`inPeriod`), esteja livre (`isFree`) e passe janela+regras
    ([`:2568`](../interface/Movimento.dc.html#L2568)–[`:2573`](../interface/Movimento.dc.html#L2573)).
  - **Passada 2 — disponibilidade geral** (`freed:false`): caminha cada período de `STEP=30` em
    `STEP` e emite **só a primeira brecha livre** de cada período (`break` após o primeiro
    `add`) ([`:2576`](../interface/Movimento.dc.html#L2576)–[`:2584`](../interface/Movimento.dc.html#L2584)).
- **RN-41. Passado do dia é descartado.** Nas duas passadas, no dia de hoje (`dOff == 0`), uma
  vaga com `start < NOW` é descartada ([`:2570`](../interface/Movimento.dc.html#L2570),
  [`:2580`](../interface/Movimento.dc.html#L2580)). É o corte que só faz sentido com um relógio —
  o motivo canônico do relógio injetável (Parte 3, GAP-01).
- **RN-42. Deduplicação e teto.** Uma chave `date|start|profId` (`seen`,
  [`:2554`](../interface/Movimento.dc.html#L2554)) impede duplicar a mesma vaga; como a passada 1
  emite antes, a versão `freed:true` vence a geral colidente. O laço externo corta ao atingir
  `CAP=50` ([`:2588`](../interface/Movimento.dc.html#L2588)). A saída ordena `freed` primeiro,
  depois `(data, start, profId)` ([`:2591`](../interface/Movimento.dc.html#L2591)).
- **RN-43. Oferecer não reserva.** `offerVaga` ([`:2596`](../interface/Movimento.dc.html#L2596))
  apenas pré-preenche o modal de novo agendamento — **nada é reservado** entre oferecer e
  confirmar. Esta é a primeira das duas corridas reais do sistema (ver GAP-16 e Parte 3).

### 1.9 Faltas

- **RN-44. Contador do paciente.** `patient.faltas` é um contador **denormalizado** exibido na
  ficha. O **gravador principal** é `setStatus`: marcar uma sessão como `faltou` faz **+1** e sair
  de um `faltou` **não justificado** faz **−1** (via `delta=(isFalta?1:0)-(wasFalta?1:0)`, com
  `Math.max(0,…)`, [`:1038`](../interface/Movimento.dc.html#L1038)–[`:1041`](../interface/Movimento.dc.html#L1041)).
  `justificarFalta` apenas **ajusta por cima** (`±1`, [`:1126`](../interface/Movimento.dc.html#L1126))
  e o seed define os valores iniciais ([`:112`](../interface/Movimento.dc.html#L112)). Por ser
  denormalizado, ainda pode divergir do histórico real de sessões (GAP-09).
- **RN-45. "Faltou" abre o buscador de quem cabe.** Marcar falta numa sessão **já iniciada**
  abre o fluxo de oferta da vaga que se abriu (`quemCabe`,
  [`:1046`](../interface/Movimento.dc.html#L1046)) — conectando falta → fila. "Já iniciada" aqui
  usa `a.start <= 702` (ver Parte 3 para a definição precisa). **Casamento mais frouxo:** a seleção
  de candidatos de `modalQuemCabe` ([`:2252`](../interface/Movimento.dc.html#L2252)) filtra **SÓ**
  por profissional preferido (`!ids.length||ids.includes(d.profId)`), ignorando
  janela/regras/horário — um segundo match, mais frouxo que o motor `filaVagas`
  ([`:2531`](../interface/Movimento.dc.html#L2531), que os docs modelam como `find_slots`): pode
  oferecer a vaga liberada a pacientes da fila cuja janela/regras/horário **não** batem, apesar do
  rótulo "compatíveis" ([`:2254`](../interface/Movimento.dc.html#L2254)).

### 1.10 Relatórios

Referência: `reports2` ([`:3334`](../interface/Movimento.dc.html#L3334)); dispatch de tela em
[`:1316`](../interface/Movimento.dc.html#L1316); método diário `reports`
([`:924`](../interface/Movimento.dc.html#L924)).

- **RN-46. Métricas.** O relatório de período agrega total, concluídas, faltas, canceladas,
  futuras, **taxa de falta** (`falta/(concl+falta)`, [`:3345`](../interface/Movimento.dc.html#L3345)),
  distribuição por tipo, por profissional e por dia
  ([`:3352`](../interface/Movimento.dc.html#L3352)–[`:3361`](../interface/Movimento.dc.html#L3361)),
  o **dia mais movimentado** (`busiest`, [`:3363`](../interface/Movimento.dc.html#L3363)), exibido
  como "Pico" no cabeçalho ([`:3452`](../interface/Movimento.dc.html#L3452)), e o **ticket médio**
  (`fat/concl`, [`:3347`](../interface/Movimento.dc.html#L3347)) — este **computado mas NÃO
  exibido** na UI (valor morto no objeto de retorno, [`:3364`](../interface/Movimento.dc.html#L3364)).
- **RN-47. Faturamento é estimado por tabela hardcoded.** O faturamento usa um preço fixo por
  tipo embutido no código (`{t1:180,t2:120,t3:130,t4:70,t5:90}`, fallback 100,
  [`:3339`](../interface/Movimento.dc.html#L3339), [`:3346`](../interface/Movimento.dc.html#L3346)).
  Não há modelo de preço, convênio ou repasse (GAP-10; faturamento é v2, ver Parte 4).
- **RN-48. Ocupação tem definições divergentes.** O protótipo calcula ocupação de **quatro**
  formas incompatíveis: `occupancy` usa capacidade = soma dos **minutos reais de expediente**
  dos profissionais ativos (`profDayMinutes`, [`:908`](../interface/Movimento.dc.html#L908)–[`:915`](../interface/Movimento.dc.html#L915));
  `profLoad` usa os **minutos reais de expediente** de **um** profissional (`profDayMinutes`,
  [`:916`](../interface/Movimento.dc.html#L916)–[`:923`](../interface/Movimento.dc.html#L923)),
  exibida como % na sidebar de Profissionais ([`:1424`](../interface/Movimento.dc.html#L1424),
  [`:1431`](../interface/Movimento.dc.html#L1431)); `colLoad` usa **9 h fixas** por coluna
  (`used/(9*60)`, [`:1575`](../interface/Movimento.dc.html#L1575)), exibida no cabeçalho da coluna
  ([`:1627`](../interface/Movimento.dc.html#L1627)); e `reports2` usa **9 slots fixos** por
  profissional-dia (`openDays*activeProfs*9`, contando agendamentos, não minutos,
  [`:3350`](../interface/Movimento.dc.html#L3350)–[`:3351`](../interface/Movimento.dc.html#L3351)).
  Para o mesmo profissional no mesmo dia, `profLoad` (minutos reais) e `colLoad` (9 h fixas)
  mostram números diferentes. A produção precisa de **uma** definição canônica (GAP-11).

### 1.11 Papéis

- **RN-49. Três papéis, hoje sem enforcement.** Existem três papéis — `admin`, `profissional`,
  `membro` — definidos como rótulo e descrição em `roleMeta`
  ([`:2408`](../interface/Movimento.dc.html#L2408)–[`:2413`](../interface/Movimento.dc.html#L2413)),
  e atribuídos a membros da organização ([`:203`](../interface/Movimento.dc.html#L203)–[`:207`](../interface/Movimento.dc.html#L207)).
  A semântica **pretendida** é: `admin` = acesso total; `profissional` = a própria agenda e seus
  pacientes; `membro` = opera a agenda de todos, sem configurações sensíveis. No protótipo isso é
  puramente descritivo — nada impede um `membro` de fazer o que um `admin` faz (GAP-12; a política
  real está em [06 §6](06-seguranca-e-lgpd.md)).
- **RN-50. Vínculo membro↔profissional é opcional e único.** Um membro pode ter `profId` (é um
  profissional com login) ou não (recepção); e há profissionais **sem** login
  ([`:200`](../interface/Movimento.dc.html#L200)–[`:207`](../interface/Movimento.dc.html#L207) —
  Thiago e Carla atendem mas não acessam o sistema).

---

## Parte 2 — Lacunas (GAP-nn)

Cada lacuna tem sintoma, impacto em produção, correção proposta e onde mora. Estas são as
divergências deliberadas entre o protótipo e a produção que a [ADR-001](00-decisoes.md) manda
catalogar aqui.

### GAP-01 — Relógio congelado

- **Sintoma.** `hoje()` retorna a **string literal** `'2026-06-25'`
  ([`:1098`](../interface/Movimento.dc.html#L1098)) e o "agora" é a constante `NOW = 702`
  (11:42), copiada à mão no seed ([`:130`](../interface/Movimento.dc.html#L130)), em `filaVagas`
  ([`:2533`](../interface/Movimento.dc.html#L2533)) e no gate de ação
  ([`:828`](../interface/Movimento.dc.html#L828), [`:1804`](../interface/Movimento.dc.html#L1804)).
  `futureConflicts` congela o "hoje" pelo **mesmo mecanismo** de `hoje()` — o literal de data
  `'2026-06-25'` ([`:865`](../interface/Movimento.dc.html#L865)) — e **não** usa o valor 702.
- **Impacto.** Toda regra que depende de passado/futuro (destravar Concluir/Faltou, debitar
  sessão, expirar regra de fila, cortar o passado do dia nas vagas, filtrar `futureConflicts`)
  quebra fora de 25/06/2026. Portar literalmente leva a produção a um sistema que "funciona" só
  num dia.
- **Correção.** ADR-009: nenhum módulo de domínio lê o relógio do sistema; o tempo é injetado
  (no Ash, via contexto/`Ash.Scope`), resolvido no **timezone da clínica**. Ver Parte 3 e
  [04 §7](04-arquitetura.md).
- **Onde mora.** Backend (motores + actions) e frontend (nunca derivar "hoje" de `new Date()`
  para decisão de negócio).

### GAP-02 — `settings.slot` definido mas nunca lido; 15 min hardcoded

- **Sintoma.** `settings.slot = 15` é declarado ([`:270`](../interface/Movimento.dc.html#L270))
  e **nunca lido** (uma única ocorrência de `slot:` no arquivo inteiro — verificado por `grep`).
  O passo de arrasto é hardcoded em `Math.round(mins/15)*15`
  ([`:1248`](../interface/Movimento.dc.html#L1248)).
- **Impacto.** O passo da grade é uma configuração aparente que não configura nada. Uma clínica
  que queira slots de 10 ou 20 min não consegue.
- **Correção.** Derivar o passo de um campo real de configuração da clínica (ver também o
  `STEP=30` de `filaVagas`, [`:2533`](../interface/Movimento.dc.html#L2533), que é outra constante
  candidata a virar configuração). Decidir se o passo é por clínica ou por tipo de atendimento
  (Parte 4).
- **Onde mora.** Backend (schema de configuração) + frontend (grade e arrasto).

### GAP-03 — Arrasto valida conflito mas não valida disponibilidade

- **Sintoma.** No `drop` do arrasto, só `checkConflict` é chamado
  ([`:1257`](../interface/Movimento.dc.html#L1257)); em conflito, abre o modal de override
  ([`:1258`](../interface/Movimento.dc.html#L1258)); caso contrário, `commitMove` grava **sem
  chamar `checkAvail`** ([`:1259`](../interface/Movimento.dc.html#L1259)). O mesmo vale para
  `createAppt` ([`:1048`](../interface/Movimento.dc.html#L1048)), que grava sem validar — a
  validação vive só no botão do modal ([`:1977`](../interface/Movimento.dc.html#L1977),
  [`:2270`](../interface/Movimento.dc.html#L2270)).
- **Impacto.** É possível arrastar um agendamento para **fora do expediente** (fim de semana,
  feriado, folga do profissional) sem qualquer aviso. A regra de disponibilidade (§1.2) é
  contornável pela interação mais comum da agenda.
- **Correção.** No servidor, disponibilidade e não-sobreposição são ambas checadas em toda
  escrita; a não-sobreposição é garantida por exclusion constraint ([04 §7.1](04-arquitetura.md)),
  e a disponibilidade é validação de ação. O front pode espelhar `checkAvail` para feedback
  imediato ([04 §10](04-arquitetura.md)), mas a autoridade é do servidor.
- **Onde mora.** Backend (action de remarcar/criar) + frontend (espelho no drop).

### GAP-04 — `openMassaPacote` é fluxo órfão

- **Sintoma.** `openMassaPacote` ([`:1134`](../interface/Movimento.dc.html#L1134)) é definido e
  **nunca chamado** — uma única ocorrência no arquivo inteiro (verificado por `grep`). O modal
  de ajuste em massa (`applyMassaPacote`/`cancelarMassaPacote`,
  [`:1149`](../interface/Movimento.dc.html#L1149)/[`:1174`](../interface/Movimento.dc.html#L1174))
  existe, mas o ponto de entrada que o abriria a partir do drawer está desconectado.
- **Impacto.** Uma capacidade de produto real (mover/cancelar as próximas sessões de um pacote de
  uma vez) existe pela metade: a lógica está pronta, a porta não abre. Portar literalmente carrega
  código morto e uma feature invisível.
- **Correção.** Decidir de produto se o ajuste em massa entra na v1; se sim, ligar o ponto de
  entrada (e resolver GAP-07 antes, pois o fluxo opera sobre um único pacote). Se não, remover.
- **Onde mora.** Produto (decisão) + frontend (ligação) + backend (ação transacional).

### GAP-05 — Faixa de almoço 12–13h hardcoded na grade

- **Sintoma.** A grade da agenda desenha uma faixa de almoço fixa das **12:00 às 13:00**
  (`top:(…(720-480)*ppm)`, `height:(60*ppm)`, [`:1649`](../interface/Movimento.dc.html#L1649) e
  [`:1724`](../interface/Movimento.dc.html#L1724)) — não derivada do horário real da clínica. O
  horário real já modela o almoço como o **intervalo entre dois períodos** (`[08:00–12:00]` e
  `[13:00–18:00]`, [`:173`](../interface/Movimento.dc.html#L173)).
- **Impacto.** Uma clínica que almoce das 12:30 às 13:30, ou que não pare, vê uma faixa visual
  mentindo sobre a disponibilidade. Pior: a faixa é decorativa e não impede agendar no almoço —
  quem impede é `dayPeriods`. Divergência entre o que a tela mostra e o que a regra decide.
- **Correção.** Derivar a faixa de indisponibilidade dos **buracos entre períodos** de
  `dayPeriods`/`hours`, não de uma constante. É layout puro (cliente).
- **Onde mora.** Frontend (renderização da grade).

### GAP-06 — Presença por turma, não por participante

- **Sintoma.** A turma é um agendamento com um **único `status`** compartilhado
  ([`:1057`](../interface/Movimento.dc.html#L1057), rótulo em [`:1815`](../interface/Movimento.dc.html#L1815)).
  Marcar `concluido`/`faltou` aplica o estado ao bloco inteiro.
- **Impacto.** Se três pacientes vêm e um falta, não há como registrar isso: ou todos
  concluíram, ou todos faltaram. O débito de sessão (§1.6) fica errado para o participante cujo
  estado real difere do estado da turma, corrompendo a contagem de pacote de quem tem pacote.
- **Correção.** Presença individual por participante, com débito por participante. **É uma
  correção proposta, não um fato do protótipo** — depende de decisão de produto
  ([00-decisoes.md](00-decisoes.md) lista "presença individual em turma" como aberto; ver Parte 4
  e Fatia 5 do [08-roadmap.md](08-roadmap.md)).
- **Onde mora.** Produto (confirmar requisito) + backend (schema de presença) + frontend.

### GAP-07 — `pkgOf` em turma multi-pacote: `apptPkg` devolve só o primeiro; massa ignora os demais

*A lacuna mais séria — nenhum outro documento do conjunto a cobre hoje.*

- **Sintoma.** Numa turma, cada participante pode ter um pacote distinto em `pkgOf`
  ([`:350`](../interface/Movimento.dc.html#L350), [`:352`](../interface/Movimento.dc.html#L352)).
  Mas `apptPkg` ([`:1110`](../interface/Movimento.dc.html#L1110)) **itera e retorna só o primeiro
  pacote** (`info.pk`, [`:1113`](../interface/Movimento.dc.html#L1113)) — e dele leem, de forma
  **independente**, tanto `massaAffected` ([`:1145`](../interface/Movimento.dc.html#L1145)), base
  do ajuste em massa (RN-27), quanto `apptPkgDebitado` ([`:1119`](../interface/Movimento.dc.html#L1119)),
  a identificação de pacote no débito, que chama `apptPkg` direto (**não** deriva de
  `massaAffected`; são rotinas irmãs, com base comum em `apptPkg`). Os demais pacotes da mesma
  turma são **ignorados em silêncio**.
- **Impacto.** Um ajuste em massa disparado a partir de uma sessão de turma move/cancela as
  sessões do pacote de **um** participante e não toca os outros, sem aviso. A trilha e o débito de
  pacote dos demais participantes divergem da agenda. Como o contador `pkgUsadas` (RN-28)
  **percorre** todos os pacotes via `pkgOf`, o débito ao vivo pode até ficar certo, mas qualquer
  operação que passe por `apptPkg` (massa, cancelamento em massa, exibição do pacote no drawer)
  vê só um. É corrupção silenciosa de dado de pacote — que é como a clínica cobra.
- **Correção.** Modelar a relação turma↔pacote como **um-para-muitos explícito** (uma linha de
  participação por paciente, com seu pacote e sua presença — o que também resolve GAP-06), e
  fazer toda operação de pacote iterar sobre **todas** as participações, nunca a primeira.
- **Onde mora.** Backend (schema e ações de turma/pacote) — é decisão de modelagem, não de UI.

### GAP-08 — `pkgPause` +21 fixo e `pkgResume` que não reprojeta datas

- **Sintoma.** Pausar grava `retomaEm` **fixo em +21 dias** ([`:554`](../interface/Movimento.dc.html#L554))
  como mero rótulo. Retomar apenas remove o `pkgHold` e devolve as sessões **nas datas
  originais** ([`:561`](../interface/Movimento.dc.html#L561)–[`:566`](../interface/Movimento.dc.html#L566)),
  sem reprojetar.
- **Impacto.** Após uma pausa de mais de 21 dias (ou de qualquer duração que ultrapasse as datas
  originais), retomar devolve sessões **em datas já passadas** — que aparecem como atrasadas ou
  simplesmente perdidas. A pausa, que deveria proteger o pacote, o corrompe.
- **Correção.** Retomar **reprojeta** a série restante para o futuro, com relógio injetado,
  reusando `computeSerie` (§1.5). Roda via job Oban após a ação `:resume`
  ([04 §11](04-arquitetura.md)). O "+21" vira uma decisão de produto sobre extensão de validade
  (Parte 4).
- **Onde mora.** Backend (ação de retomada + job de reprojeção) + produto (validade/pausa).

### GAP-09 — `patient.faltas` denormalizado

- **Sintoma.** `patient.faltas` é um contador mutado à mão (`±1` em `justificarFalta`,
  [`:1126`](../interface/Movimento.dc.html#L1126)) e semeado direto
  ([`:112`](../interface/Movimento.dc.html#L112)), enquanto as faltas reais vivem no histórico de
  sessões/agendamentos.
- **Impacto.** Duas fontes de verdade para "quantas faltas o paciente tem". Os dois caminhos
  normais **mantêm** o contador em sincronia — `setStatus` (+1/−1 ao marcar/reverter `faltou`,
  [`:1038`](../interface/Movimento.dc.html#L1038)–[`:1041`](../interface/Movimento.dc.html#L1041))
  e `justificarFalta` (`±1`, [`:1126`](../interface/Movimento.dc.html#L1126)) —, mas o valor
  continua denormalizado: o seed inicial pode não bater com o histórico e qualquer caminho que
  altere uma falta por fora desses dois faz o contador divergir das sessões reais.
- **Correção.** Derivar faltas do histórico (agregado/`count` Ash empurrado ao SQL,
  [ADR-002](00-decisoes.md)), não guardar contador. Se por desempenho for preciso materializar,
  que seja um agregado mantido pelo servidor, nunca por escrita de UI.
- **Onde mora.** Backend (agregado em vez de campo).

### GAP-10 — Preço hardcoded no relatório

- **Sintoma.** O faturamento do relatório usa uma tabela de preço embutida no código
  (`{t1:180,t2:120,t3:130,t4:70,t5:90}`, [`:3339`](../interface/Movimento.dc.html#L3339),
  [`:3346`](../interface/Movimento.dc.html#L3346)). O formulário de profissional coleta uma
  **string livre** de remuneração que ninguém lê ([`:3140`](../interface/Movimento.dc.html#L3140)).
- **Impacto.** Nenhum número financeiro do relatório é confiável — é ilustração. Não há modelo de
  preço por convênio/particular/reembolso nem de repasse.
- **Correção.** Faturamento e repasse são **v2** (ADR e [08 §5](08-roadmap.md)). Na v1, ou o
  relatório não mostra faturamento, ou mostra um preço explicitamente configurável e assumidamente
  simplificado. **Decisão de produto pendente** sobre se algum preço mínimo entra na v1 (Parte 4;
  note a divergência de classificação com [00-decisoes.md](00-decisoes.md), discutida na Parte 4).
- **Onde mora.** Produto (v1 vs v2) + backend (modelo de preço, se v1).

### GAP-11 — Quatro definições divergentes de ocupação

- **Sintoma.** Ver RN-48: são **quatro** cálculos. `occupancy` usa expediente real em minutos de
  todos os ativos ([`:908`](../interface/Movimento.dc.html#L908)); `profLoad` usa expediente real
  em minutos de **um** profissional, na sidebar ([`:916`](../interface/Movimento.dc.html#L916),
  [`:1424`](../interface/Movimento.dc.html#L1424)/[`:1431`](../interface/Movimento.dc.html#L1431));
  `colLoad` usa 9 h fixas ([`:1575`](../interface/Movimento.dc.html#L1575)); `reports2` usa 9 slots
  fixos por profissional-dia ([`:3350`](../interface/Movimento.dc.html#L3350)).
- **Impacto.** "Ocupação" significa números diferentes em telas diferentes — e para o mesmo
  profissional/dia a % da sidebar (`profLoad`) diverge da barra de carga da coluna (`colLoad`,
  9 h fixas). A gestão não consegue confiar no indicador.
- **Correção.** Uma definição canônica única — ocupação = tempo agendado ÷ capacidade real de
  expediente (a de `occupancy`, que respeita a disponibilidade calculada) — usada em toda a UI. A
  definição precisa é uma decisão de produto (Parte 4).
- **Onde mora.** Produto (definição) + backend (cálculo canônico, snapshot noturno,
  [04 §11](04-arquitetura.md)).

### GAP-12 — RBAC não aplicado (papéis são rótulos)

- **Sintoma.** `roleMeta` ([`:2408`](../interface/Movimento.dc.html#L2408)) é `label`/`desc`/ícone,
  sem enforcement. Nada impede um `membro` de agir como `admin`.
- **Impacto.** Sem servidor não há controle de acesso; com dado de saúde, é inaceitável
  ([ADR-007](00-decisoes.md)).
- **Correção.** `Ash.Policy.Authorizer` com policies de recurso e `field_policies`, tenant antes
  de papel — inteiramente especificado em [06 §6](06-seguranca-e-lgpd.md). O texto de `roleMeta`
  vira o contrato das policies.
- **Onde mora.** Backend (policies) — ver [06](06-seguranca-e-lgpd.md).

### GAP-13 — Sem autenticação (o botão Entrar só navega)

- **Sintoma.** A tela de login (`renderLogin`, [`:3471`](../interface/Movimento.dc.html#L3471))
  tem campos de e-mail/senha decorativos e um botão **Entrar** que apenas navega
  (`onClick=${()=>this.go('agenda')}`, [`:3484`](../interface/Movimento.dc.html#L3484)). O convite
  de membro (`saveMembro`, [`:2497`](../interface/Movimento.dc.html#L2497)) só muda estado local.
- **Impacto.** Não há identidade, sessão nem ator — logo, nem tenant, nem RBAC, nem auditoria.
- **Correção.** `AshAuthentication` com sessão por cookie e token efêmero de WebSocket, convite de
  uso único, MFA de admin — especificado em [06 §5](06-seguranca-e-lgpd.md) e
  [04 §5](04-arquitetura.md).
- **Onde mora.** Backend (auth) + frontend (fluxo de login/convite).

### GAP-14 — Relatório sobre histórico sintético

- **Sintoma.** Todo o dataset (pacientes, pacotes, sessões, faltas, agendamentos passados) é
  gerado por um PRNG determinístico no seed ([`:43`](../interface/Movimento.dc.html#L43)–[`:263`](../interface/Movimento.dc.html#L263)),
  e `reports2` agrega sobre ele.
- **Impacto.** Os relatórios do protótipo demonstram forma, não verdade — não há histórico real
  por trás. Em produção, os números só passam a significar algo quando as fatias operacionais
  produzem os dados que o relatório agrega.
- **Correção.** O relatório é uma das **últimas** fatias ([08 Fatia 9](08-roadmap.md)),
  dependente de que as anteriores gerem dados reais; lê de um snapshot noturno, não faz varredura
  ao vivo ([04 §11](04-arquitetura.md)). O seed sintético continua útil como fixture
  ([04 §12](04-arquitetura.md)).
- **Onde mora.** Produto (quais métricas) + backend (snapshot).

### GAP-15 — Sem salas/recursos (conflito é só por profissional)

- **Sintoma.** `checkConflict`/`conflictOf` conflitam apenas por `profId`
  ([`:834`](../interface/Movimento.dc.html#L834), [`:837`](../interface/Movimento.dc.html#L837)).
  Não existe sala, maca ou equipamento com capacidade.
- **Impacto.** Duas sessões de profissionais diferentes podem ser marcadas na mesma sala física
  sem conflito. Para clínicas com poucas salas, é uma colisão real invisível ao sistema.
- **Correção.** Salas/recursos como entidade com capacidade — mas isso muda a exclusion
  constraint de "por profissional" para "por recurso", a **mudança de schema mais cara da lista**
  ([04 §13](04-arquitetura.md)). É **v2** e **não** deve ser decidida por palpite (Parte 4).
- **Onde mora.** Produto (v2, decisão de schema) + backend.

### GAP-16 — Sem reserva de vaga na fila (corrida entre atendentes)

- **Sintoma.** `offerVaga` só abre um modal ([`:2596`](../interface/Movimento.dc.html#L2596)) e
  `createAppt` não reserva nada entre oferecer e confirmar
  ([`:1048`](../interface/Movimento.dc.html#L1048)). Dois atendentes podem oferecer o mesmo
  horário ao mesmo tempo.
- **Impacto.** O segundo atendente colide sem aviso — ou sobrescreve. É a primeira das duas
  corridas reais ([04 §7.2](04-arquitetura.md)), invisível em teste single-user.
- **Correção.** Recurso `SlotHold` com TTL curto (5 min) e exclusion constraint, `409` imediato
  com o nome de quem segurou — desenho completo em [04 §7.2](04-arquitetura.md) (**atenção à
  correção do `now()`**, ver Parte 3). Depende do motor de disponibilidade da Fatia 1.
- **Onde mora.** Backend (recurso `SlotHold`, constraint, job Oban) + frontend (feedback de
  conflito).

---

## Parte 3 — Regras novas exigidas pelos ADRs

Estas regras **não** existem no protótipo; nascem das decisões travadas. Onde o desenho já foi
feito, este documento **referencia** a seção real de [04-arquitetura.md](04-arquitetura.md) (cuja
numeração foi conferida) e de [06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md), em vez de
reescrever a API — os marcadores `# NAO-VERIFICADO` vivem lá.

### 3.1 Isolamento por clínica; profissional em mais de uma clínica

- **RN-51.** Toda entidade nasce escopada a uma **clínica (tenant)** ([ADR-003](00-decisoes.md)).
  O protótipo é clínica única (`hours`/`holidays`/`settings` são singletons globais,
  [`:173`](../interface/Movimento.dc.html#L173), [`:270`](../interface/Movimento.dc.html#L270));
  a produção exige tenant em toda leitura e escrita. O tenant é resolvido **da sessão**, no
  `Ash.Scope`, e **nunca** vem do cliente ([04 §4](04-arquitetura.md); teste de isolamento por
  recurso em [07 §6](07-estrategia-de-testes.md)).
- **RN-52.** Um **profissional pode existir em mais de uma clínica** — regra nova, sem precedente
  no protótipo ([ADR-003](00-decisoes.md)). Consequências a decidir (Parte 4): o vínculo
  profissional↔clínica passa a ser um relacionamento, não um atributo; a agenda, a
  disponibilidade e o repasse são **por vínculo**, não por pessoa; e a exclusion constraint de
  não-sobreposição precisa ser por-(clínica, profissional) se a estratégia de tenancy for por
  atributo, para não confundir os horários de um mesmo profissional em clínicas distintas
  ([04 §7.1](04-arquitetura.md)).

### 3.2 Concorrência

- **RN-53. Não-sobreposição garantida pelo banco.** A garantia final de que dois agendamentos do
  mesmo profissional não se sobrepõem é uma **exclusion constraint** (`btree_gist`) no Postgres,
  parcial por `WHERE (encaixe = false AND status <> 'cancelado')` — reproduzindo RN-12/RN-13 com
  garantia transacional. O DDL exato e a interação com a tenancy estão em
  [04 §7.1](04-arquitetura.md). A validação Ash dá a mensagem por campo; a **constraint é a
  verdade**.
- **RN-54. Reserva de vaga (hold) com TTL.** A oferta de vaga passa a criar um `SlotHold` com TTL
  de 5 min ([04 §7.2](04-arquitetura.md)), fechando GAP-16. **Correção crítica do `now()`:** a
  exclusion constraint do hold **não** pode ter predicado `WHERE expires_at > now()` — `now()` é
  `STABLE`, não `IMMUTABLE`, e o Postgres **recusa** a constraint; além disso a semântica de
  "expirou sozinho" não existiria. O desenho correto (a constraint sem predicado de tempo + um
  `DELETE ... WHERE expires_at <= now()` **na DML**, dentro da transação da ação `:offer`, antes
  do insert; Oban só como backstop) é o de [04 §7.2](04-arquitetura.md). Este documento **não**
  afirma que a constraint filtra holds expirados — isso seria DDL inválido.
- **RN-55. Locking otimista em remarcação.** Cada `Appointment` carrega `version`; remarcar exige
  a versão lida e devolve `409` com o estado atual em divergência, em vez de sobrescrever — o
  análogo servidor da remarcação em memória do protótipo (`saveRemarcar`,
  [`:1133`](../interface/Movimento.dc.html#L1133); `commitMove` no drop,
  [`:1259`](../interface/Movimento.dc.html#L1259)). O mecanismo (change built-in de optimistic
  lock, **não** incremento à mão) está em [04 §7.3](04-arquitetura.md), marcado
  `# NAO-VERIFICADO` quanto ao nome exato. Esta corrida e a de RN-53 atacam problemas distintos e
  coexistem.

### 3.3 Granularidade de broadcast PubSub

- **RN-56.** As mutações de agenda propagam em tempo real por tópicos PubSub em **duas
  resoluções**, escolhidas pela visão ativa ([04 §6.1](04-arquitetura.md)):
  `clinic:<id>:agenda:<YYYY-MM-DD>` (dia/semana, payload cheio) e
  `clinic:<id>:agenda:month:<YYYY-MM>` (mês, sinal leve de invalidação). A **visão dia** assina 1
  tópico; a **visão semana** assina os 5–7 dias visíveis; a **visão mês** assina 1 tópico de mês e
  recebe apenas `{day, change: :count}`, recarregando a contagem da célula sem transportar
  agendamentos inteiros. O publicador faz **dois** broadcasts por escrita (dia + mês). A
  navegação entre visões (`navShift`, [`:1184`](../interface/Movimento.dc.html#L1184)) troca as
  assinaturas. Após reconexão, o cliente **não** assume store fresco: dispara `invalidate`/refetch
  do recorte visível ([04 §8](04-arquitetura.md)).

### 3.4 Timezone canônico, virada de dia e "já começou"

- **RN-57.** Cada clínica tem um **timezone canônico** persistido; "hoje" e "já começou" são
  resolvidos nesse fuso, não em UTC nem no fuso do servidor ([ADR-009](00-decisoes.md)). Datas
  trafegam pela API como ISO-8601 com offset explícito; o front nunca deriva "hoje" do relógio do
  browser para decisão de negócio.
- **RN-58. Definição precisa de "sessão já começou".** No protótipo, a liberação dos botões
  **Concluir/Faltou** (drawer) usa `a.date < hoje() || (a.date === hoje() && a.start <= 702)`
  ([`:1804`](../interface/Movimento.dc.html#L1804), verificado). **Subtileza a preservar:** este
  gate ("já **começou**", `start <= agora`) é **diferente** do gate do selo "precisa de ação" na
  agenda, `needsAction`, que usa `(a.start + a.dur) <= 702` — ou seja, "já **terminou**"
  ([`:828`](../interface/Movimento.dc.html#L828)). São duas fronteiras distintas: o botão destrava
  quando a sessão **inicia**; o selo aparece quando ela **termina**. A produção deve manter as
  duas, definidas como comparações contra o relógio injetado no fuso da clínica — o `702` (11:42)
  hardcoded é substituído pelo "agora" resolvido (GAP-01).
- **RN-59. Virada de dia por fuso.** A fronteira do dia respeita o fuso da clínica: duas clínicas
  em fusos distintos (ex.: `America/Sao_Paulo` e `America/Manaus`) resolvem "hoje" de formas
  diferentes para o mesmo instante UTC ([07 §3](07-estrategia-de-testes.md) exige um caso
  dedicado). Isso afeta toda regra ancorada em `TODAY`/`hoje()`: `filaVagas`,
  `filaRegraExpirada`, `computeSerie`, `futureConflicts`.

### 3.5 Auditoria

- **RN-60.** Acesso e mutação de dado de saúde são auditáveis — **leitura também, não só
  escrita**. Os eventos que geram registro (criar/editar prontuário, adicionar/remover `tags`,
  subir/baixar anexo, editar `obs` da fila, alterar dados bancários, abrir ficha completa, gerar
  dossiê, conceder/revogar consentimento, e toda **autorização negada** a dado sensível) estão
  catalogados em [06 §4](06-seguranca-e-lgpd.md). Este documento **não** duplica esse catálogo:
  aponta para ele. O "quem/quando/o quê/por quê" de cada registro, e o cuidado de nunca gravar
  valor sensível em claro no diff, são de [06 §4](06-seguranca-e-lgpd.md).

---

## Parte 4 — Perguntas abertas de produto

Organizadas por bloqueio. **"Muda tabelas"** é a marca que importa: uma resposta que altera
schema não pode ser adivinhada, porque corrigir depois custa migração de dado sensível. Esta lista
é a **canônica**; ela concilia a seção final de [00-decisoes.md](00-decisoes.md) e a tabela final
de [08 §8](08-roadmap.md), e as divergências entre os três estão apontadas ao fim.

### 4.1 Bloqueiam o schema (decidir antes de modelar — mudam tabelas)

| # | Pergunta | O que muda | Quando (fatia) |
|---|---|---|---|
| P-01 | Pacote tem **validade** real? Pausar estende a validade — por quanto? (hoje o `retomaEm` é +21 fixo e decorativo, [`:554`](../interface/Movimento.dc.html#L554)) | Tabela de pacote; reprojeção da série na retomada (GAP-08) | Antes da Fatia 3 |
| ~~P-02~~ | ✅ **RESOLVIDO ([ADR-011](00-decisoes.md)):** não há renovação — o `total` é editável (+/−) a qualquer momento; sem `renovado_de`, `:renew` ou `:renovado` | — | — |
| P-03 | **Presença individual em turma** confirma-se como requisito? | Schema de turma: participação um-para-muitos, presença e débito por participante (GAP-06, GAP-07) | Antes da Fatia 5 |
| P-04 | Quais **papéis leem quais campos** do prontuário? Retenção por tipo de dado? | `field_policies`, `AshCloak`, política de purga ([06](06-seguranca-e-lgpd.md)) | Antes da Fatia 6 (Gate G1) |
| P-05 | **Salas/equipamentos** como recurso com capacidade? | Forma da exclusion constraint: de "por profissional" para "por recurso" — a mudança mais cara (GAP-15, [04 §13](04-arquitetura.md)) | **v2 — não decidir por palpite** |
| P-06 | Um **profissional em mais de uma clínica**? (regra nova, [ADR-003](00-decisoes.md)) | Vínculo profissional↔clínica como relacionamento; agenda/disponibilidade/repasse por vínculo (RN-52) | Antes da Fatia 10 |
| P-07 | **Preço** varia por convênio/particular/reembolso? Há **repasse** ao profissional? (hoje preço hardcoded, [`:3339`](../interface/Movimento.dc.html#L3339); remuneração é string livre não lida, [`:3140`](../interface/Movimento.dc.html#L3140)) | Subdomínio de faturamento/repasse (GAP-10) | **v2** — mas ver divergência §4.4 |

### 4.2 Bloqueiam a v1 (não mudam schema, mas travam comportamento de fatia)

| # | Pergunta | O que trava | Quando (fatia) |
|---|---|---|---|
| P-08 | Quem enxerga a agenda de quem? `profissional` vê só a própria ou a da clínica? | Policy de leitura da agenda (RN-49; [06 §6](06-seguranca-e-lgpd.md)) | Antes da Fatia 1 |
| P-09 | Qual papel pode criar um **encaixe** (sobreposição deliberada, RN-12)? | Policy da ação de criar encaixe | Antes da Fatia 1 |
| P-10 | **Cancelamento** libera a vaga para a fila automaticamente? Cancelar exige motivo? Remarcar para o passado é permitido? | Fluxo entre transição e fila; ação de cancelar/remarcar | Antes da Fatia 2 (fila na Fatia 4) |
| P-11 | **TTL** e **prioridade** da fila de espera (o TTL de 5 min é chute de desenho; `prio` existe [`:163`](../interface/Movimento.dc.html#L163) e **já ordena** a exibição da fila — `renderFila` [`:2836`](../interface/Movimento.dc.html#L2836)/[`:2838`](../interface/Movimento.dc.html#L2838) — e a lista "quem cabe" — `modalQuemCabe` [`:2252`](../interface/Movimento.dc.html#L2252) —, MAS **não** influencia o motor de casamento de vagas `filaVagas` [`:2591`](../interface/Movimento.dc.html#L2591), que ordena por vaga-que-abriu/data/hora; falta regra de TTL/`SlotHold` e desempate documentados) | Regra do `SlotHold` e ordenação da fila (GAP-16) | Antes da Fatia 4 |
| P-12 | Ao mudar horário, agendamentos futuros conflitantes são **bloqueados, remarcados ou apenas sinalizados**? (hoje `saveProf` bloqueia o salvamento, [`:1198`](../interface/Movimento.dc.html#L1198)) | Comportamento de escrita de `futureConflicts` (RN-15) | Antes da Fatia 7 |
| P-13 | Definição **canônica de ocupação** (expediente real, 9 h fixas ou 9 slots)? (GAP-11) | Indicador de relatório e de carga por coluna | Antes da Fatia 9 |
| P-14 | Quais **métricas** de relatório importam, e em que granularidade? | Escopo do snapshot de métricas (GAP-14) | Antes da Fatia 9 |
| P-15 | **Passo da grade** (`slot`) e **duração padrão** são por clínica ou por tipo de atendimento? (GAP-02) | Schema de configuração da clínica/tipo | Antes da Fatia 8 (afeta a Fatia 1) |

### 4.3 Podem esperar

| # | Pergunta | Observação |
|---|---|---|
| P-16 | Timezone da clínica pode **mudar** depois de existirem agendamentos? Feriado admite exceção por profissional? | O motor `dayPeriods` já suporta a exceção por profissional (RN-09); a mudança de fuso pós-dados é operacional. Antes da Fatia 8 |
| P-17 | O convite de membro **expira**? Quem pode convidar — só `admin`? | Fluxo de equipe (Fatia 10); default seguro em [06 §5](06-seguranca-e-lgpd.md) |
| P-18 | **Faturamento, guias de convênio, nota fiscal** | v2 — subdomínio inteiro ([08 §5](08-roadmap.md)) |
| P-19 | **Multi-unidade** dentro da mesma clínica (filiais com horários/salas próprios) | v2 — distinto de multi-clínica |
| P-20 | Ajuste em massa de pacote entra na v1? (GAP-04, fluxo órfão) | Depende de P-03/GAP-07 estarem resolvidos |

### 4.4 Divergências entre os três documentos (a reconciliar)

Os três documentos que listam decisões abertas — [00-decisoes.md](00-decisoes.md) (seção final),
[08 §8](08-roadmap.md) (tabela final) e esta Parte 4 — **concordam** na maioria, com estas
divergências que precisam ser alinhadas:

1. **Classificação de preço/repasse (P-07).** [00-decisoes.md](00-decisoes.md) lista "Preço varia
   por convênio…? Há repasse?" sob **"Bloqueia: Schema"**, enquanto [08 §5 e §8](08-roadmap.md) e
   [04 §13](04-arquitetura.md) tratam faturamento/repasse como **v2**. Conciliação proposta:
   faturamento é **v2** e **não** bloqueia o schema da v1 — os campos bancários/remuneração são
   coletados e explicitamente não usados na v1 ([08 Fatia 7](08-roadmap.md)). O que **é** questão
   de v1 é apenas se o relatório mostra algum preço mínimo configurável (GAP-10); isso não é o
   subdomínio de faturamento. Recomenda-se corrigir a linha de [00-decisoes.md](00-decisoes.md)
   para refletir "v2", mantendo a nota de que o relatório da v1 pode precisar de um preço simples.
2. **"Cancelamento libera a vaga" (P-10).** Aparece em [08 §8](08-roadmap.md) mas **não** na lista
   de abertos de [00-decisoes.md](00-decisoes.md). Não é decisão de schema — é comportamento de
   fatia (v1). Fica aqui em §4.2; [00-decisoes.md](00-decisoes.md) não precisa listá-la como
   bloqueio de schema, mas convém mencioná-la como pergunta de fluxo.
3. **Definição de ocupação (P-13) e passo da grade (P-15).** Surgem deste documento (GAP-11,
   GAP-02) e de [08 §3/§8](08-roadmap.md), mas **não** constam da lista de
   [00-decisoes.md](00-decisoes.md). Como nenhuma delas muda tabela de forma cara (ocupação é
   cálculo; passo é um campo de configuração simples), a ausência em
   [00-decisoes.md](00-decisoes.md) é aceitável — são perguntas de v1, não ADRs em aberto.

Fora esses três pontos, a lista canônica desta Parte 4, a seção final de
[00-decisoes.md](00-decisoes.md) e a tabela de [08 §8](08-roadmap.md) estão de acordo: pacote
(validade/pausa/renovar), presença em turma, papéis×prontuário, salas, profissional multi-clínica,
faturamento e multi-unidade aparecem nos três com a mesma classificação de bloqueio.

---

### Referências cruzadas

- Decisões: [00-decisoes.md](00-decisoes.md) (ADR-001 define este catálogo; ADR-003, ADR-007,
  ADR-009).
- Arquitetura: [04-arquitetura.md](04-arquitetura.md) (§2 motores, §4 contrato, §5 auth, §6
  tempo real, §7 concorrência, §10 fronteira cliente/servidor, §11 Oban, §13 não desenhado).
- Testes: [07-estrategia-de-testes.md](07-estrategia-de-testes.md) (§2.1 `dayPeriods`, §2.2
  `futureConflicts`, §3 tempo determinístico, §6 isolamento).
- Segurança/LGPD: [06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md) (§4 auditoria, §5 auth, §6
  RBAC/field policies).
- Roadmap: [08-roadmap.md](08-roadmap.md) (fatias que fecham cada GAP; §8 decisões×bloqueio).
