# Divergências: interface (protótipo) × regras geradas

> Análise linha a linha do protótipo `interface/Movimento.dc.html` (a "especificação de
> origem", ADR‑001) contra os documentos de regras/domínio (`00`, `01`, `02`, `09`, `10`, `11`).
> Cada divergência foi **confirmada por verificação adversarial** relendo as linhas reais dos dois lados.
> Gerado em 2026‑07‑11.

## Sumário executivo

Foram levantadas **86 divergências candidatas**; após verificação adversarial independente,
**80 sobreviveram** (6 descartadas como falso‑positivo — ver Parte C).

| Classe | Qtd | O que é |
|---|---|---|
| **Erros a corrigir** (CONFIRMED) | **61** | O doc descreve/modela algo em desacordo com o protótipo |
| — alto impacto (viram bug se implementados) | 4 | Enum/modelo incompleto ou filtro de agregado errado |
| — contradições factuais | 15 | O doc afirma um comportamento que o protótipo não tem |
| — omissões de regra/campo | 23 | O protótipo faz, o doc não documenta/modela |
| — referências de linha `[:NNN]` erradas | 19 | Âncora off‑by‑N (a regra está certa, o número não) |
| **Divergências deliberadas** (assumidas nos docs) | **19** | Diferença real, mas intencional e reconhecida — **não é erro** |
| **Falso‑positivo** (descartado) | 6 | A verificação adversarial refutou |

**Os 4 críticos** (corrigir antes de gerar código a partir dos docs):

1. **`Waitlist.Priority` está sem o valor `:baixa`** — `01:186` declara `[:urgente, :alta, :normal]`, mas a própria linha `[:2230]` citada como prova tem **4 opções** (o `<select>` inclui `Baixa`) e o filtro lateral `[:1457]` também. Um `Ash.Type.Enum` sem `:baixa` **rejeitaria** um item de fila que o formulário permite criar.
2. **`SessionState` está sem o valor `:agendada`** — `01:175` lista 5 valores; `pkgSessions [:391]` produz `:agendada` como estado de **toda sessão futura depois da próxima** (renderizado em `pkgDot [:400]` e na legenda `[:642]`). Estado comuníssimo, faltando no enum.
3. **O recurso `Professional` sub‑modela o formulário real** — `01 §4.2` ignora quase toda a identidade/contato/dados bancários que `renderProfForm [:3007‑3140]` coleta e persiste: identidade pessoal (`cpf`, `rg`, `nasc`, `estadoCivil`, `nomeExib`), contato/endereço (`tel`, `email`, `cep`, `endereco`…), contato de emergência (`emNome`/`emTel`), `profissao`, dados PJ (`razaoSocial`, `cnpj`, `contaTipo`) e o índice de cor `ci` (editável). Ver A3.
4. **Agregado `count :usadas` sem o fallback do default da clínica** — `01:788` filtra por `parent(falta_punitiva) == true` e ignora o ramo `nil ⇒ default da clínica` que o próprio doc promete (`:769`) e que `pkgPunitivo [:1103]` implementa. Com `falta_punitiva=nil` numa clínica punitiva, `usadas` é **subcontado** e `restantes` supercontado.

---

## Metodologia

- **Fonte da verdade:** o protótipo (`interface/Movimento.dc.html`, 3501 linhas; lógica em `<script data-dc-script>`). Confirmado que a notação `[:NNN]` dos docs = linha `NNN` real do arquivo.
- **Comparação:** 16 unidades de conferência doc→protótipo (cada afirmação e cada `[:NNN]` relidos no protótipo) + 4 varreduras reversas protótipo→doc (caça a omissões).
- **Verificação adversarial:** cada divergência candidata passou por um verificador independente e cético, que releu as linhas reais e classificou em **CONFIRMED** (erro), **DELIBERATE** (diferença intencional reconhecida nos docs) ou **REJECTED** (falso‑positivo).
- Execução: workflow multi‑agente (106 subagentes, ~6,2M tokens).

Legenda de severidade: **alta** = enganaria quem for implementar; **média** = impreciso/desatualizado; **baixa** = citação/precisão sem impacto de conteúdo.

---

## Parte A — Erros a corrigir nos docs

### A.1 Alto impacto

| # | Doc | Divergência | Correção |
|---|-----|-------------|----------|
| A1 | `01:186` | `Priority` sem `:baixa` (proto `[:2230]` `<select>` + `[:1457]` filtro) | `values: [:urgente, :alta, :normal, :baixa]` |
| A2 | `01:175` | `SessionState` sem `:agendada` (proto `pkgSessions [:391]`, legenda `[:642]`) | Adicionar `:agendada`; anotar que é **derivado**, não semente |
| A3 | `01 §4.2` | `Professional` ignora identidade/contato/PJ/`ci` do form `[:3007‑3140]` | Acrescentar os atributos (ver detalhe abaixo) |
| A4 | `01:788` | Agregado `count :usadas` sem fallback `nil ⇒ default da clínica` (`pkgPunitivo [:1103]`) | Incluir o ramo `is_nil(falta_punitiva) and clinica.falta_consome_padrao` |

**Detalhe de A3 — o que o `Professional` deixa de modelar** (todos presentes no formulário e/ou no seed `[:52‑57]`):
- Identidade pessoal: `nomeExib`, `nasc`, `cpf`, `rg`, `estadoCivil` (seção "Identificação pessoal" `[:3007]`, inputs `[:3076‑3084]`).
- Contato/endereço: `tel`, `email` (login), `cep`, `endereco`, `numero`, `complemento`, `bairro`, `cidade`, `uf` (`[:3008]`, `[:3090‑3104]`).
- Contato de emergência do profissional: `emNome`, `emTel` (`[:3106‑3107]`).
- `profissao` (Profissão/formação, semeado em todos e coletado por select `[:3114]`).
- Dados PJ / bancários: `razaoSocial`, `cnpj`, `contaTipo` (`[:3010]`, `[:3127‑3137]`, persistidos `[:3055]`) — `contaTipo`/`cnpj` já são catalogados como **segredo** em `06 §1.4` mas **não** protegidos pelo `field_policy` de `01 [:1189]`.
- `ci` (índice de cor) — editável e persistido na seção "Cor & status" via `savePayload`, mas não modelado (enquanto `ativo`, irmão na mesma seção, foi).

### A.2 Contradições factuais (o doc descreve algo que o protótipo não faz)

**Renovação de pacote** (3 achados convergentes — o ponto mais confuso do conjunto):
- `ADR‑011:172` (Contexto) e `RN‑22 (02:238‑244)` afirmam que "o protótipo faz renovação como **pacote‑sucessor**" (novo pacote com `renovadoDe`, anterior vira `renovado`). Mas o **único** fluxo de "Renovar" alcançável pela UI — `openRenovar [:336]` → `modalRenovar [:606]` → `confirmRenovar [:590]` — **adiciona sessões ao mesmo pacote** (`[:600]`: `total+=gen.length`, `status:'ativo'`). O ramo sucessor é **código morto** (nenhum opener seta `renovadoDe`).
- Consequência: `01:1330` (e `01:1330`/Apêndice) atribuem o `status:'renovado'` a `confirmRenovar`, mas quem seta `renovado` é `createPacote [:362]`; `confirmRenovar` seta `ativo [:600]`. **Corrigir o nome da função.**

**Contrato de API (`09`)** — 6 achados:
- `09:404‑410` diz que **`concluido` nunca é status persistido de pacote**, só derivado — falso: o protótipo persiste `status:'concluido'` no seed (`[:108]/[:123]/[:124]`), em `archivePkg [:576]` e o lê em `addSession [:541]` para reativar. `pkgDone [:329]` ramifica sobre esse valor persistido.
- `09:405/410` diz **"quatro valores persistidos"** mas enumera **três** (`ativo/pausado/cancelado`) após remover `renovado` — o número está errado nos dois pontos.
- `09:326` atribui o join/push de `pkgOf` a `createAppt`, mas `[:350]` está em **`createPacote`**; o merge de grupo do `createAppt [:1056]` seta só `patientIds`, nunca `pkgOf`.
- `09:261/§2.2` liga a fusão de participantes de grupo (`createAppt [:1053‑1056]`) a uma checagem de capacidade — mas essa fusão é **incondicional** (nunca lê `cap`); a capacidade só é checada na pré‑visualização `occIssue [:703]` e no drawer da turma `[:1826]`. Além disso `cap = tp.cap||settings.capPilates||4` está em `createPacote [:341]`, não em `createAppt`, e é um teto **soft** (contornável via encaixe).
- `09:287` diz que `apptPkg` retorna "`{pk,patient,ownerId,pkgId}` **por participante**" — mas `apptPkg [:1113]` faz `return` **dentro** do laço: devolve **uma** tupla (o 1º participante cujo `pkgId` casa).
- `09:268` mapeia "turma cheia" para **`409`** em `:add_participant`, contradizendo o resto do doc que trata capacidade excedida como **`422`** (§5.2/§5.3). Reservar `409` para concorrência.

**Fila:**
- `P‑11 (02:772)` afirma que "`prio` existe mas não ordena" — **falso**: `renderFila [:2836‑2838]` e `modalQuemCabe [:2252]` ordenam por prioridade (`{urgente:0,alta:1,normal:2,baixa:3}`). Só o motor `filaVagas [:2591]` ignora `prio` (ordena por vaga‑liberada/data/hora). (2 achados convergentes.)

**Relatórios:**
- `01:1107` atribui o cálculo dos KPIs/preço a `renderRelatorios`, mas `[:3339]` está em **`reports2()`** (3334‑3365); `renderRelatorios` começa em `[:3367]` e só renderiza.

**Gaps:**
- `GAP‑07 (02:516)` descreve `apptPkgDebitado` como derivado de `massaAffected`, mas `apptPkgDebitado [:1119]` chama `apptPkg` direto; as duas são **irmãs** (base comum = `apptPkg`, que só lê o 1º `info.pk`).
- `GAP‑01 (02:423)` lista `futureConflicts [:865]` entre os lugares onde "`NOW=702` é copiada à mão" — mas `[:865]` é `const today='2026-06-25'` (congela por **data**, não usa 702).

**Resumo consolidado (`11`) — contradições internas:**
- `11:16/29/51` + tabela `D15/D16` (`:104/:105`) + `:117/:121` ainda tratam D15/D16 como **conflitos abertos**, enquanto a §6 (`:197`) e `ADR‑012`/`ADR‑013` (ambos "Aceita 2026‑07‑10") já os reconciliaram. Sincronizar. **Atualização 2026‑07‑11:** D15 foi **revertida** por `ADR‑014` (profissional multi‑clínica = SIM na v1, modelo Vercel); o `11` já reflete isso na §1.4 e nas tabelas.
- `11:73‑75` diz que a "correção i" do `01` propunha adicionar `validade_ate` e que D6 a cancela — mas a correção i vigente (`01:1142`) já diz "produção também sem validade"; `validade_ate` pertence ao "desenho anterior" descartado (`01:758`). D6 **confirma**, não cancela.

### A.3 Omissões de regra/comportamento (protótipo faz, doc não documenta)

**Agenda / disponibilidade:**
- `RN‑16 (02:189)` lista só 2 dos 3 consumidores de `futureConflicts` (`hourConflicts`, `saveProf`) e **omite `addHoliday [:1220]`** (guarda ao criar exceção de data da clínica) + a precedência de `simulate [:1214]` (exceção pré‑existente do profissional vence a nova exceção da clínica).
- `RN‑33/§1.3` descrevem a turma como "um agendamento com `patientIds`" mas **omitem o merge idempotente**: criar turma/pacote de grupo num slot com bloco coincidente (mesmo `profId`+`date`+`start`+`typeId`) **funde** o paciente no `patientIds` (`createAppt [:1056]`, `createPacote [:350]`) em vez de criar 2º bloco; e para grupo o modal **nunca chama `checkConflict`** (`[:1978]` gate `!isGroup`) — sobreposição vira merge, não conflito.

**Pacotes:**
- `RN‑18/§1.5` descreve só `computeSerie` e omite que a criação roda **`occIssue` por ocorrência [:703]** (fora/cheia/join/conflito), bloqueia o save salvo `!issues.length||d.forcar [:754]` e grava sessões forçadas como **encaixe** (checkbox `[:750]`).
- `RN‑26 (02:257)` descreve o ajuste de grade como "altera `dows/horarios/profId`", mas `pkgSaveGrade [:578‑588]` **remarca a série**: remove as sessões futuras não resolvidas e **regenera** `nCount` novas a partir de hoje, pulando feriados e preservando `pkgHold`.
- O **código do pacote `SIGLA‑AAMM`** (`pkgSigla [:378]`→`pkgBaseCode [:379]`→`pkgCode` com desambiguação `·N` `[:380]`), usado em toda a UI e como **chave de busca de pacientes `[:2677]`**, não é modelado; nem o campo `criado` que o alimenta (atenção: `criado` é a data da 1ª sessão `[:358]`, não `inserted_at`).
- `archivePkg [:576]` (concluir/arquivar, no menu quando `pkgDone`) transiciona `→ concluido` mas **não consta** da lista de ações do `Package` (`01 §4.4`). Inversamente, `add_session [:541]` **reativa** um pacote concluído (`concluido → ativo`) — transição não documentada.

**Fila / relatórios / RBAC:**
- O protótipo impõe **"1 item de fila por paciente"** (`addFila` faz upsert por paciente `[:1190]`), mas `WaitlistEntry` modela `:enqueue` como create simples, **sem identity `[:patient_id]` nem upsert**.
- `modalQuemCabe [:2252]` (candidatos da vaga liberada) filtra **só por profissional preferido**, ignorando janela/regras/horário — um 2º match **mais frouxo** que `filaVagas [:2591]`; nenhum doc cita `[:2252]`.
- `RN‑48/GAP‑11` dizem que a ocupação tem **3** definições, mas há uma **4ª**: `profLoad [:916‑923]` (minutos reais de expediente, exibida na sidebar de Profissionais `[:1424]/[:1431]`), que **diverge** do `colLoad` (9 h fixas) do cabeçalho de coluna `[:1627]`.
- `RN‑46 (02:377)` enumera os agregados do relatório mas omite o **ticket médio** (`fat/concl [:3347]`, calculado mas **não exibido**) e o **Pico/busiest** (`[:3363]`, este **é exibido** em `[:3452]`).
- `RN‑44 (02:362)` atribui o contador `patient.faltas` só a `justificarFalta` + seed, mas o **gravador principal é `setStatus [:1038‑1041]`** (marcar `faltou` → +1; reverter falta não justificada → −1). O "Impacto" de `GAP‑09:552` também está errado nisso.

**Ficha / dados:**
- `Patient` modela `medico`/`crm` mas omite o 3º campo da seção "Atendimento": **`comoConheceu`** (canal de aquisição, semente `[:88]`, form editável) — não é dado sensível.
- O campo **`acesso`** (último login) do membro (seed `[:203‑207]`, init em `saveMembro [:2504]`) não é mapeado nem em `User` nem em `Membership` (é vestigial/não renderizado — omissão de baixo impacto).
- `RN‑01 (02:35)` define o agendamento como 6 campos `{profId,typeId,start,dur,date,status}` mas os próprios objetos‑semente carregam também `id`, `patientId`/`patientIds` e **`encaixe`** (load‑bearing no conflito `[:835]`).

### A.4 Referências de linha `[:NNN]` desatualizadas (off‑by‑N)

A regra descrita está correta; só a âncora aterrissa na linha errada (às vezes em outra função). Correção mecânica:

| Doc | Cita | Deveria ser | O quê |
|-----|------|-------------|-------|
| `01:164` | `[:117]` | `[:117]`,`[:120]`,`[:123]` | status pacote: âncora única só cobre `ativo` |
| `01:172` | `[:117]-[:120]` | `[:117]-[:121]` | `SessionState` `:segurada` está em 121 |
| `01:211` | `[:66]-[:67]` | `[:66]-[:68]` | `prof.exc` `tipo:'horario'` está em 68 |
| `01:242` | `[:198]` | `[:201]` | Thiago/Carla sem acesso |
| `01:386` | `[:69]-[:73]` | `[:69]-[:74]` | tipo `t5` (Reavaliação) omitido |
| `01:556` | `[:1122]` | `[:1123]` | `faltaJustificada` |
| `01:701` | `[:2598]` | `[:2596]` | `offerVaga` (2598 é `filaDispCell`) |
| `01:826` | `[:1091]` | `[:1090]` | check de feriado |
| `01:884` | `[:2598]` | `[:2596]` | `offerVaga` |
| `01:894` | `[:2589]` | `[:2591]` | `out.sort` (freed primeiro) |
| `01:929` | `[:1124]` | `[:1126]` | expr de `faltas` |
| `01:931` | `[:113]` | `[:112]` | seed `faltas` (113 é `usadas`) |
| `01:1135` | `[:113]` | `[:112]` | seed `faltas` |
| `01:1143` | `[:2598]` | `[:2596]` | `offerVaga` |
| `01:1264` | `[:1115]` | `[:1116]` | ramo `a.pkgId` de `apptPkg` |
| `01:1267` | `[:72]` | `[:73]` | tipo `t4` (grupo/cap) |
| `01:1350` | `[:163]` | `[:164]` | `profIds:['p4','p1']` (163 tem só `['p1']`) |
| `01:1372` | `[:832]` | nomear `conflictOf` (832) ou citar `[:834]` p/ `checkConflict` |
| `02:423` | `[:865]` | — | `[:865]` é literal de data, não `NOW=702` |

---

## Parte B — Divergências deliberadas (assumidas nos docs — **não são erros**)

O protótipo faz de um jeito; os docs, conscientemente, modelam de outro e **registram a decisão**. Listadas para o implementador não confundir a presença no protótipo com regra a implementar.

| Tema | Protótipo | Produção (doc) | Onde é reconhecida |
|------|-----------|----------------|--------------------|
| **Renovação de pacote** | status `renovado` `[:362]`, campo `renovadoDe`, fluxo `openRenovar/confirmRenovar` | Sem renovação; total editável a qualquer momento | ADR‑011; RN‑22; enum `01:165`/`:1329` |
| **Presença por participante** | 1 `status` por bloco + mapa `pkgOf` | Recurso filho `Attendance` (status + `package_id` por participante) | "correção d + e", `01:463` |
| **Tempo do agendamento** | `start` (min do dia) + `dur` + `date` | `starts_at`/`ends_at` (`:utc_datetime`) p/ `tstzrange` | "correção d", `01:472` |
| **Disponibilidade do prof** | `prof.avail` + `followClinic` (`profWeek [:840]`) | `ProfessionalHours` com modo `:herda/:custom/:fechado` | "correção g", `01:620` |
| **Exceções de data** | 2 arrays: `holidays` + `prof.exc` | 1 recurso polimórfico `ScheduleException` | "correção f", `01:657` |
| **Reserva de vaga** | `offerVaga [:2596]` só abre o modal (sem hold) | `SlotHold` com TTL (recurso novo) | ADR‑004; `01:698` |
| **`dias` na fila** | valor estático digitado no seed | calculation `date_diff(inserted_at)` | "correção h", `01:848` |
| **Retomar pacote** | `pkgResume [:561]` só tira `pkgHold` (datas originais) | `:resume` reprojeta a série p/ o futuro | "nota 3", `01:803`/`:1337` |
| **Profissional multi‑clínica** | protótipo é clínica‑única (singletons globais) | **v1 SIM** (modelo Vercel): `User` global → N `Membership` → N `Professional` por schema | **ADR‑014** (reverte ADR‑012; RN‑52 volta p/ v1) |
| **Prontuário / dados clínicos** | tags de diagnóstico, anexos, médico/CRM | adiado p/ v2; v1 só a ficha | ADR‑013 (restringe ADR‑007) |
| **Autenticação** | login mock; seed `membros` sem senha/token | `User` + AshAuthentication **Google OAuth + Magic Link** (sem senha) | **ADR‑015**, `01:§Accounts` |
| **Papéis / owner** | `roleMeta` = 3 rótulos sem enforcement | `owner·admin·profissional·recepcao`, capabilities embarcadas, ≥1 owner/tenant | **ADR‑016**, `01:§3/§7` |
| **D6/D7/D11** | (retomada / renovação / pacote de turma) | decisões de produto que redefinem os GAPs | `10` (produto v1) |

> Nota de acompanhamento apontada pelos próprios docs: `01:1335` sinaliza que `09 §3.4` **ainda lista `renovado`** e "precisa ser alinhado" — o que se confirma nas contradições de A.2 sobre o `09`.

---

## Parte C — Falso‑positivos descartados pela verificação adversarial (6)

Registrados para transparência — **não** são divergências:

1. `01:1108` — "Reporting não menciona `ocup`": a lista de KPIs é explicitamente **ilustrativa** e `:summary` retorna `:map` sem enumerar campos.
2. `02:282` — "RN‑30 omite o guard `a &&`": a ref `[:1106]` está correta; o trecho entre crases é só paráfrase.
3. `10:33` — "D3 contradiz o tipo carregar duração": D3 **afirma** que o tipo carrega a duração — bate com o protótipo.
4. `11:97` — "TTL do SlotHold 10 vs 5 min": `11` está correto (D8=10 min); o "5 min" é registro do desenho anterior.
5. `01:641` — "invariante `custom ⊆ clínica` ausente": **está** documentada na §8 (`01:1261`).
6. `02:44` — "arrasto reatribui profissional, sub‑documentado": a ação `:reschedule` já lista `professional_id?` como editável.

---

## Recomendações priorizadas

1. **Corrigir os 4 críticos de A.1** — são os únicos que viram bug se o código for gerado a partir dos docs (enums `Priority`/`SessionState`, atributos do `Professional`, filtro do agregado `usadas`).
2. **Reconciliar o `09` (contrato de API)** com o `01`/ADR‑011: `renovado`, "quatro→três valores", `concluido` persistido, `apptPkg` (uma tupla), `409→422` em turma cheia, atribuições `createAppt`/`createPacote`.
3. **Alinhar `P‑11` e `RN‑44`/`GAP‑09`** ao comportamento real (prio ordena; `setStatus` grava `faltas`).
4. **Fechar as omissões de A.3** que representam regra de negócio real (merge de turma, remarcação em `pkgSaveGrade`, `occIssue` na criação, unicidade da fila, 4ª ocupação, código do pacote).
5. **Sincronizar o resumo `11`** (D15/D16 já reconciliados; correção i).
6. **Aplicar a tabela A.4** (busca‑e‑substitui de âncoras `[:NNN]`) — mecânico, mas evita que auditorias futuras percam a trilha.
7. **Divergências deliberadas (Parte B):** nenhuma ação de correção; se quiser rigor, catalogar as "correções f/g/h" e as decisões D6/D7/D11 numa lista central de divergências intencionais para rastreabilidade.

---

*Gerado por análise multi‑agente com verificação adversarial linha a linha. 80 divergências mantidas de 86 candidatas.*
