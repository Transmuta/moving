# Contrato de API

O contrato entre `movimento-web` (BFF SvelteKit) e `movimento-api` (Phoenix + Ash),
e entre o navegador e os Phoenix Channels. É a fronteira que o [ADR-002](00-decisoes.md#adr-002--backend-em-elixir--ash-exposto-como-api-rest)
e o [ADR-005](00-decisoes.md#adr-005--sveltekit-como-bff-nunca-como-cliente-de-banco) tornam
o único ponto de acordo entre os dois runtimes. Este documento expande e **corrige**
o esboço da [seção 4 de 04-arquitetura.md](04-arquitetura.md#4-contrato-de-api).

> **Nota de honestidade (obrigatória neste repo).** Não existe ainda projeto Elixir
> neste repositório; não é possível rodar `mix usage_rules.docs` nem verificar hexdocs.
> Todo trecho de código de biblioteca abaixo que foi escrito de memória está marcado com
> `# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar`. Quando não tenho certeza da
> assinatura, descrevo o comportamento em prosa em vez de fingir precisão. As afirmações
> sobre o protótipo citam a linha e foram verificadas com `grep`/`sed` contra
> `interface/Movimento.dc.html`.

---

## 0. O que muda em relação ao esboço da arquitetura

O §4 de `04-arquitetura.md` está certo no espírito e errado em três detalhes que, se
copiados literalmente para o código, quebram. As correções:

1. **"Erros carregam campo" é meia-verdade e precisa ser reescrito.** O próprio §4 se
   contradiz no último parágrafo, onde admite que conflito de agenda e turma cheia não
   pertencem a campo nenhum. A formulação correta é: *erros carregam **localização**
   `source.pointer` **quando** pertencem a um campo; para os que não pertencem, existe um
   segundo canal, documentado na [seção 5](#5-erros). Não é um detalhe de estilo — é a
   diferença entre o SvelteKit conseguir pintar o input vermelho ou engolir a falha em
   silêncio, exatamente a armadilha de `.claude/rules/ash_phoenix.md`.

2. **`PATCH /appointments/:id/reschedule` presume uma rota que o AshJsonApi não gera
   sozinho.** O AshJsonApi roteia por recurso; ações que não são o CRUD padrão precisam
   de uma entrada explícita no bloco `json_api do routes ... end` do recurso. O verbo e o
   caminho são escolha nossa, não convenção automática. Padronizo abaixo em
   `POST /appointments/:id/reschedule` (ver [justificativa de método na seção 2](#21-por-que-post-e-não-patch-para-transições)).

3. **`GET /availability` não é um recurso persistido.** Disponibilidade é resultado do
   motor `dayPeriods` ([`:854`](../interface/Movimento.dc.html#L854)), computado sob demanda.
   No Ash isso é uma **ação genérica** (não `:read` sobre uma tabela) exposta como rota
   própria. Trato-a como tal, não como coleção JSON:API paginável.

Tudo o mais do §3 — tenant vindo da sessão e nunca do corpo, `include` para aninhamento,
ações nomeadas — é mantido e detalhado.

---

## 1. Convenção JSON:API (AshJsonApi)

O AshJsonApi expõe recursos Ash como uma API [JSON:API 1.0](https://jsonapi.org/). O
`Content-Type` de requisição e resposta é `application/vnd.api+json`. O que segue é o
subconjunto do JSON:API que este domínio realmente usa, com a ressalva de que a **sintaxe
exata de cada parâmetro deve ser confirmada contra a documentação do AshJsonApi ao
scaffoldar** — descrevo o comportamento pretendido, não decoro assinaturas.

### 1.1 Estrutura de um recurso

Um agendamento serializado segue o envelope `data` do JSON:API: `type`, `id` e um mapa
`attributes`, com `relationships` apontando para outros recursos por `{type, id}`. O que
é atributo e o que é relacionamento vem da declaração do recurso Ash — atributos e
calculations viram `attributes`; `belongs_to`/`has_many`/`many_to_many` viram
`relationships`.

```jsonc
// GET /api/appointments/a-8f3c
{
  "data": {
    "type": "appointment",
    "id": "a-8f3c",
    "attributes": {
      "starts_at": "2026-07-09T09:00:00-03:00",  // ISO-8601 com offset da clínica (ADR-009)
      "duration_minutes": 50,
      "status": "agendado",                        // enum verificado em L810-820 do protótipo
      "encaixe": false,                            // exceção à não-sobreposição; ver §6
      "version": 7                                 // lock otimista; ver §6
    },
    "relationships": {
      "professional":      { "data": { "type": "professional", "id": "p1" } },
      "appointment_type":  { "data": { "type": "appointment_type", "id": "t2" } },
      "attendances":       { "data": [ { "type": "attendance", "id": "att-1" } ] }
    }
  }
}
```

O campo `clinic_id` **nunca** aparece no corpo aceito de uma escrita e nunca é lido do
cliente: o tenant é resolvido da sessão no `Ash.Scope` (ADR-003). Ele pode aparecer em
respostas de leitura, mas como fato derivado do escopo, não como algo que o cliente possa
influenciar.

### 1.2 Relacionamentos e `include`

Recursos relacionados vêm por referência `{type, id}` em `relationships` e só têm seus
atributos materializados no topo `included` quando pedidos por `?include=`. O carregamento
aninhado usa notação de caminho com ponto:

```
GET /api/appointments?include=professional,appointment_type,attendances.patient
```

Isto traduz para um `Ash.Query.load/2` no servidor. Vale a orientação de
`.claude/rules/ash.md`: preferir carregamento **estrito** (`strict?: true`) para não puxar
campos sensíveis por engano — e aqui isso não é só performance, é LGPD (ADR-007): incluir
`attendances.patient` traz um paciente cujas `tags` clínicas são categoria especial e estão
sob `field_policies` e `AshCloak`. O `include` pede a relação; a **política decide o que de
fato serializa**.

### 1.3 Sparse fieldsets

`?fields[type]=a,b` limita quais atributos de cada tipo voltam. É a ferramenta para a
agenda mensal não arrastar o payload inteiro de cada agendamento:

```
GET /api/appointments?fields[appointment]=starts_at,duration_minutes,status,professional
                     &include=professional&fields[professional]=nome,cor
```

O comportamento que **projetamos** (e que precisamos confirmar, não afirmar): field policies e
sparse fieldsets deveriam **compor**, de modo que pedir um campo que a política nega não o
revele — o campo sairia do payload em vez de vazar. Se essa composição de fato ocorre no
AshJsonApi (a política negar um campo o remove silenciosamente da serialização, mesmo quando
pedido por `fields[...]`), ou se em vez disso o pedido é rejeitado, ou o campo volta nulo, é
uma questão de biblioteca em aberto:
`// NAO-VERIFICADO: confirmar contra a doc do Ash/AshJsonApi ao scaffoldar como field_policies interagem com sparse fieldsets`.
Seja qual for a resposta, a decisão de contrato é: o front trata a **ausência** de um campo
sensível como "sem permissão", não como "sem dado" — e validamos essa premissa em teste ao
scaffoldar antes de depender dela.

### 1.4 Filtragem

O AshJsonApi expõe filtragem via `filter[...]`. A sintaxe exata de operadores
(`gte`, `lte`, `in`, `eq`) e seu aninhamento em colchetes **deve ser confirmada** — o Ash
tem um DSL de filtro rico e o AshJsonApi mapeia um subconjunto dele para query params. A
intenção, no formato que o §3 já usava:

```
GET /api/appointments?filter[starts_at][gte]=2026-07-09T00:00:00-03:00
                     &filter[starts_at][lte]=2026-07-09T23:59:59-03:00
                     &filter[professional][eq]=p1
```

Regra de projeto: **só expomos os filtros de que as telas precisam**, declarados
explicitamente no recurso. Não abrimos o DSL inteiro de filtro do Ash à rede — isso seria
uma superfície de ataque e de N+1. Os filtros habilitados por recurso estão no
[catálogo da seção 3](#3-catálogo-de-endpoints).

### 1.5 Ordenação

`?sort=campo` ascendente, `?sort=-campo` descendente, múltiplos separados por vírgula:
`?sort=starts_at,-created_at`. Mapeia para `Ash.Query.sort/2`. A agenda ordena por
`starts_at`; a fila tem ordenação própria de domínio que **não** é `?sort` (ver
[seção 3.6](#36-fila-de-espera)).

### 1.6 Paginação

O Ash suporta paginação por **offset** e por **keyset**; o AshJsonApi expõe a que o recurso
declarar, via `page[limit]` / `page[offset]` (offset) ou `page[after]` / `page[limit]`
(keyset), com `links` de `next`/`prev` e um `meta` de contagem quando a paginação é offset.
A escolha por recurso e o porquê estão na [seção 7](#7-versionamento-depreciação-e-paginação).

---

## 2. Ações nomeadas, nunca CRUD genérico

Esta é a característica que mais molda o contrato, e a justificativa é concreta no protótipo,
não filosófica. **Não existe `PATCH /appointments/:id` genérico.** Cada transição de estado
de um agendamento tem policy, validação e efeito colateral distintos.

### 2.1 Por que POST e não PATCH para transições

Transições como "concluir", "marcar falta", "remarcar" não são "substitua estes campos" —
são comandos com efeito colateral que às vezes tocam **outro** agregado (o pacote do
paciente). Modelá-las como `PATCH` de atributo mente sobre o que acontece. Uso
`POST /appointments/:id/<transição>` para deixar explícito que é um comando, não uma
edição idempotente de campo. (O AshJsonApi permite escolher o método na rota; a escolha é
de projeto — `# NAO-VERIFICADO: confirmar a forma exata do bloco de rotas do AshJsonApi ao scaffoldar`.)

### 2.2 O caso que prova a regra: consumo de sessão de pacote

O protótipo distingue, com uma função de regra real, quando uma transição debita uma sessão
do pacote do paciente. Verificado em `wouldConsume` ([`:1104`](../interface/Movimento.dc.html#L1104)):

```js
// interface/Movimento.dc.html:1104 (verbatim, verificado)
wouldConsume(a,statusVal,pk){
  if(statusVal==='concluido') return true;
  if(statusVal==='faltou'){ if(a && a.faltaJustificada) return false; return this.pkgPunitivo(pk); }
  return false;
}
```

e `pkgPunitivo` ([`:1103`](../interface/Movimento.dc.html#L1103)) resolve a "falta punitiva"
do pacote com fallback para a configuração global `settings.noShowConsome`:

```js
// interface/Movimento.dc.html:1103 (verbatim, verificado)
pkgPunitivo(pk){ return (pk && pk.faltaPunitiva!=null) ? !!pk.faltaPunitiva : !!this.state.settings.noShowConsome; }
```

Lido em prosa: **concluir sempre debita uma sessão do pacote. Faltar debita conforme a
`faltaPunitiva` daquele pacote** (e, se o pacote não define, conforme o padrão da clínica),
**a menos que a falta esteja justificada** (`faltaJustificada`), caso em que não debita.
**Cancelar não debita nunca.** É por isso que `mark_completed`, `mark_no_show` e `cancel`
são três ações separadas com efeitos diferentes, e não um único `PATCH status=...`: a
mesma edição de string dispararia débitos diferentes. O motor `wouldConsume` vive no
servidor como código de domínio puro (é o mesmo padrão da tabela de motores em
[04-arquitetura §2](04-arquitetura.md#2-fronteiras-e-responsabilidades)); a resource action
o consulta dentro da transação para debitar ou não.

Correlato verificado: `setStatus` ([`:1032`](../interface/Movimento.dc.html#L1032)) também
mexe no contador de faltas do **paciente** (`patients...faltas`), e ao marcar falta de uma
sessão que já começou, abre o fluxo "quem cabe" (oferecer a vaga que abriu). Ou seja, uma
única transição de status tem efeito em três agregados — agendamento, pacote, paciente — e
mais um efeito de fila. Nenhum `PATCH` genérico expressa isso.

---

## 3. Catálogo de endpoints

Prefixo `/api`. Todas as rotas exigem sessão autenticada (cookie, [seção 8](#8-autenticação)),
resolvem o tenant do escopo e aplicam as policies do Ash. Papéis referem-se aos três do
protótipo, verificados em `roleMeta` ([`:2411`](../interface/Movimento.dc.html#L2411)) e nos
dados-semente ([`:203`](../interface/Movimento.dc.html#L203)):

| Papel | Alcance (do protótipo) |
|---|---|
| `admin` | "Acesso total — configurações, equipe, todas as agendas e relatórios" |
| `profissional` | "Gerencia a própria agenda e seus pacientes" |
| `membro` | "Opera a agenda de todos, sem configurações sensíveis" |

A coluna "papéis" abaixo é o **alvo de policy**, a ser implementado como `Ash.Policy`, não
como filtro no controller. Onde diz "próprio", a policy é um filtro (`profissional` só
enxerga/muta o que se relaciona a ele via `professional_id`).

Códigos de erro comuns a quase toda rota, omitidos das linhas para não repetir:
`401` (sem sessão), `403` (policy nega), `404` (fora do tenant ou inexistente — retornamos
404 e não 403 para não confirmar existência entre tenants), `422` (validação),
`409` (conflito de concorrência, [seção 6](#6-concorrência-no-contrato)).

### 3.1 Agenda / Agendamentos

| Método | Rota | Ação Ash | Papéis | Corpo → Resposta | Erros específicos |
|---|---|---|---|---|---|
| GET | `/appointments?filter[starts_at][gte]=…&[lte]=…&include=…` | `:read` (por intervalo) | todos; `profissional` filtrado ao próprio | — → coleção | — |
| GET | `/appointments/:id` | `:read` get_by id | todos (próprio p/ profissional) | — → recurso | — |
| POST | `/appointments` | `:schedule` | admin, membro, profissional(próprio) | `{starts_at, duration?, professional_id, appointment_type_id, patient_id \| patient_ids, encaixe?, from_waitlist_id?}` → recurso criado | `409` conflito de horário; `422` fora do expediente; `422` turma cheia |
| POST | `/appointments/:id/reschedule` | `:reschedule` | admin, membro, profissional(próprio) | `{starts_at, professional_id?, encaixe?, expected_version}` → recurso | `409` versão divergente; `409` conflito de horário (sem `encaixe`) |
| POST | `/appointments/:id/complete` | `:mark_completed` | admin, membro, profissional(próprio) | `{expected_version}` → recurso | `409` versão; `422` transição inválida |
| POST | `/appointments/:id/no_show` | `:mark_no_show` | admin, membro, profissional(próprio) | `{expected_version}` → recurso | `409` versão |
| POST | `/appointments/:id/justify_absence` | `:justify_absence` | admin, membro, profissional(próprio) | `{expected_version}` → recurso | `409` versão |
| POST | `/appointments/:id/confirm` | `:mark_confirmed` | admin, membro, profissional(próprio) | `{expected_version}` → recurso | `409` versão |
| POST | `/appointments/:id/start` | `:mark_in_progress` | admin, membro, profissional(próprio) | `{expected_version}` → recurso | `409` versão |
| POST | `/appointments/:id/cancel` | `:cancel` | admin, membro, profissional(próprio) | `{expected_version, reason?}` → recurso | `409` versão |

Os seis status são verificados em `statusMeta` ([`:810`](../interface/Movimento.dc.html#L810)):
`agendado`, `confirmado`, `em_atendimento`, `concluido`, `faltou`, `cancelado`. As
transições `complete`/`no_show`/`cancel`/`justify_absence` disparam o efeito de pacote da
[seção 2.2](#22-o-caso-que-prova-a-regra-consumo-de-sessão-de-pacote).

**Turma (atendimento em grupo).** Quando o tipo é `grupo`, o protótipo **funde** o participante
num bloco já existente sempre que há um bloco compatível (mesmo `profId`/`date`/`start`/`typeId`,
não cancelado) — `createAppt` ([`:1056`](../interface/Movimento.dc.html#L1056)) e `createPacote`
([`:350`](../interface/Movimento.dc.html#L350)) —, **sem checar capacidade na fusão** (o merge só
deduplica `patientIds`). A capacidade (`cap = tp.cap || settings.capPilates || 4`, definida em
`createPacote`, [`:341`](../interface/Movimento.dc.html#L341), e no preview,
[`:702`](../interface/Movimento.dc.html#L702)) só limita o fluxo na pré-visualização `occIssue`
([`:703`](../interface/Movimento.dc.html#L703)) e no drawer da turma
([`:1827`](../interface/Movimento.dc.html#L1827)), e é um teto **soft** — contornável via "encaixe"
([`:1997`](../interface/Movimento.dc.html#L1997)).
Participação individual em turma é modelada como recurso `attendance`, não como campo do
agendamento:

| Método | Rota | Ação Ash | Papéis | Corpo → Resposta | Erros |
|---|---|---|---|---|---|
| POST | `/appointments/:id/participants` | `:add_participant` | admin, membro, profissional(próprio) | `{patient_id, package_id?}` → `attendance` | `422` turma cheia; `422` paciente já na turma |
| DELETE | `/appointments/:id/participants/:patient_id` | `:remove_participant` | idem | — → `204` | — |

Cada `attendance` liga `appointment` ↔ `patient` **e carrega o `package_id` daquele
participante** — ver a [subseção 3.1.1](#311-turma-multi-pacote-cada-participante-tem-seu-próprio-pacote).

> **Lacuna consciente.** Se "presença individual em turma" se confirmar como requisito
> (está em aberto — [00-decisoes.md, decisões em aberto](00-decisoes.md#decisões-ainda-em-aberto)),
> `complete`/`no_show` passam a ter granularidade por `attendance`, não por `appointment`.
> O contrato acima já isola isso num sub-recurso justamente para absorver essa decisão sem
> reescrever a rota do agendamento.

#### 3.1.1 Turma multi-pacote: cada participante tem seu próprio pacote

Faltava, na versão anterior, ligar o `attendance` ao `pkgOf` do protótipo. É uma lacuna
concreta, não estética: no protótipo, um bloco de grupo carrega `patientIds` **e** um mapa
`pkgOf` que associa **cada participante ao seu próprio pacote** (`pkgOf:{...(g.pkgOf||{}),[d.patientId]:pkId}`,
[`:350`](../interface/Movimento.dc.html#L350)). É esse mapa `pkgOf` — um pacote por participante —
que sustenta a modelagem: **não há um "pacote do agendamento", há um pacote por presença**. A
resolução "de qual pacote esta sessão debita, e de quem" é `apptPkg`
([`:1110`](../interface/Movimento.dc.html#L1110)), que **itera `pkgOf`** mas faz `return` **dentro**
do laço ([`:1113`](../interface/Movimento.dc.html#L1113)): devolve **uma única** tupla
`{pk, patient, ownerId, pkgId}` — o **primeiro** participante cujo `pkgId` existe em
`patient.pacotes` —, não uma por participante. A varredura completa por participante/pacote ocorre
nas funções de agregação do pacote (`pkgUsadas`/`pkgAppts`,
[`:326`](../interface/Movimento.dc.html#L326)/[`:330`](../interface/Movimento.dc.html#L330)), não
em `apptPkg`.

Consequência de modelagem: o `package_id` é atributo do **`attendance`**, nunca do
`appointment`. O `attendance` é a materialização de uma entrada de `pkgOf`. Isso muda três
coisas no contrato:

1. **Consumo de sessão por participante.** A regra `wouldConsume`
   ([`:1104`](../interface/Movimento.dc.html#L1104)) da [seção 2.2](#22-o-caso-que-prova-a-regra-consumo-de-sessão-de-pacote)
   debita do pacote **do dono daquela presença** (`attendance.package_id`), com a `faltaPunitiva`
   **daquele** pacote — não de um pacote único do bloco. Num grupo de quatro, uma conclusão pode
   debitar quatro pacotes diferentes, e uma falta pode debitar dois e poupar dois conforme a
   punitividade de cada pacote. Quando `complete`/`no_show` ganharem granularidade por presença
   (a decisão em aberto acima), a rota será
   `POST /appointments/:id/participants/:patient_id/complete` (e `/no_show`), com corpo
   `{expected_version}`; o servidor usa `attendance.package_id` para saber de quem debitar.

2. **`add_participant` precisa saber o pacote.** O corpo aceita `package_id?`: quando a inclusão
   na turma vem de um pacote (o caso comum — a série de um pacote de Pilates cai numa turma),
   `package_id` é obrigatório de fato e vem da série que originou a sessão; quando é um encaixe
   avulso sem pacote, `package_id` é nulo e a presença é "particular"/avulsa. O servidor valida
   que o `package_id`, se presente, é um pacote **do próprio `patient_id`** (espelha `apptPkg`,
   que só casa `pkgId` dentro de `patient.pacotes`) — senão `422`.

3. **Ajuste e cancelamento em massa de pacote operam sobre presenças, não sobre o bloco
   inteiro.** É aqui que a lacuna mordia. As ações de pacote da [seção 3.4](#34-pacotes-de-sessões)
   — `:bulk_adjust` (`applyMassaPacote`, [`:1149`](../interface/Movimento.dc.html#L1149)),
   `:bulk_cancel` (`cancelarMassaPacote`, [`:1174`](../interface/Movimento.dc.html#L1174)),
   `:adjust_grade`, `:pause`, `:resume`, `:cancel` — quando uma sessão do pacote caiu **dentro de
   uma turma**, **não** podem tocar o `appointment` de grupo inteiro: precisam mexer só na
   presença cujo `attendance.package_id` é o pacote alvo. O escopo dessas ações (`esta` |
   `proximas` | `todas`) resolve-se para o conjunto de **`attendance`s** daquele `package_id`, e o
   efeito por presença é:
   - **cancelar/remover** a presença ⇒ retira o participante do bloco (`patientIds` menos aquele,
     e a entrada correspondente de `pkgOf`), deixando os demais participantes intactos. Se a
     presença era a última do bloco, o bloco em si é cancelado; senão, sobrevive.
   - **remarcar** (mudar profissional/horário da sessão daquele pacote) ⇒ **destaca** a presença
     do bloco antigo e a reinsere no bloco novo (fundindo com uma turma existente naquele
     horário/tipo se houver capacidade, ou criando um bloco novo) — exatamente o `join`/`push`
     de `createPacote` ([`:350`](../interface/Movimento.dc.html#L350)), agora por presença.

   Endpoints afetados, portanto, **não** ganham rota nova: são os mesmos
   `POST /packages/:id/bulk_adjust` e `POST /packages/:id/bulk_cancel` da
   [seção 3.4](#34-pacotes-de-sessões). O que muda é a **semântica de execução** no servidor —
   o alvo é `attendance` filtrado por `package_id`, e o resultado emite `participant_removed`
   ou `participant_added` (e não `appointment_canceled`) para as sessões que eram de grupo.
   Um `bulk_cancel` de um pacote cujas sessões são todas individuais cancela `appointment`s; se
   forem de turma, remove presenças. O servidor decide caso a caso pela presença/`pkgOf`, como o
   `apptPkg` do protótipo já faz.

Resumo do payload que faltava:

```jsonc
// attendance serializado
{
  "type": "attendance",
  "id": "att-1",
  "attributes": { "status": "agendado" },     // ganha granularidade se a decisão em aberto confirmar
  "relationships": {
    "appointment": { "data": { "type": "appointment",  "id": "a-8f3c" } },
    "patient":     { "data": { "type": "patient",       "id": "pac12" } },
    "package":     { "data": { "type": "package",        "id": "pkM1" } }  // pkgOf[patient_id]; null se avulso
  }
}
```

### 3.2 Disponibilidade (ação genérica, não recurso)

| Método | Rota | Ação Ash | Papéis | Resposta |
|---|---|---|---|---|
| GET | `/availability?professional_id=&date_from=&date_to=` | ação genérica `:availability` | todos | lista de `{date, periods: [[ini,fim]], closed_reason?}` |

Isto é o motor `dayPeriods` ([`:854`](../interface/Movimento.dc.html#L854)) exposto: resolve
disponibilidade por precedência de 4 camadas (exceção de data da clínica > exceção do
profissional > horário especial da clínica > horário semanal do profissional). Não é
paginável nem filtrável como coleção JSON:API — é um cálculo. O resultado alimenta o
espelho de validação do front (validar horário antes do round-trip, a "exceção pragmática"
de [04-arquitetura §2](04-arquitetura.md#2-fronteiras-e-responsabilidades)), mas o servidor
revalida na hora de agendar.

### 3.3 Pacientes

| Método | Rota | Ação Ash | Papéis | Erros |
|---|---|---|---|---|
| GET | `/patients?filter[nome]=&sort=nome` | `:read` | admin, membro; profissional só os próprios | — |
| GET | `/patients/:id` | `:read` get_by id | idem | — |
| POST | `/patients` | `:create` | admin, membro, profissional | `422` CPF inválido/duplicado |
| PATCH | `/patients/:id` | `:update` | idem | `422` |

A ficha do paciente é o recurso mais sensível: `tags` clínicas, `medico`/`crm`,
consentimento LGPD versionado — todos sob `field_policies` e `AshCloak` (ADR-007). O
`profissional` só lê a ficha de quem é seu paciente (filtro de policy). Aqui `PATCH`
genérico **é** aceitável, ao contrário do agendamento: editar dados cadastrais é de fato
"substitua estes campos" sem efeito colateral em outro agregado.

### 3.4 Pacotes de sessões

O pacote é uma máquina de estados com transições que geram ou apagam agendamentos em massa.
Cada uma é ação nomeada porque cada uma tem efeito distinto — verificado nas funções do
protótipo:

| Método | Rota | Ação Ash | Origem no protótipo | Efeito |
|---|---|---|---|---|
| POST | `/packages` | `:create_with_series` | `computeSerie` [`:1081`](../interface/Movimento.dc.html#L1081) | Gera a série de N sessões pela grade (dows+horários), pulando feriados |
| POST | `/packages/:id/pause` | `:pause` | `pkgPause` [`:553`](../interface/Movimento.dc.html#L553) | Marca `pausado`; sessões futuras saem da agenda (`pkgHold`), continuam no pacote |
| POST | `/packages/:id/resume` | `:resume` | `pkgResume` [`:561`](../interface/Movimento.dc.html#L561) | Marca `ativo`; sessões voltam à agenda |
| POST | `/packages/:id/cancel` | `:cancel` | `cancelarPkg` [`:568`](../interface/Movimento.dc.html#L568) | Marca `cancelado`; sessões futuras viram `cancelado` |
| PATCH | `/packages/:id/grade` | `:adjust_grade` | `pkgSaveGrade` [`:578`](../interface/Movimento.dc.html#L578) | Remarca todas as sessões futuras para a nova grade (profissional/dows/horários) |
| POST | `/packages/:id/bulk_adjust` | `:bulk_adjust` | `applyMassaPacote` [`:1149`](../interface/Movimento.dc.html#L1149) | Muda profissional e/ou horário de um escopo de sessões (`esta`/`proximas`/`todas`) |
| POST | `/packages/:id/bulk_cancel` | `:bulk_cancel` | `cancelarMassaPacote` [`:1174`](../interface/Movimento.dc.html#L1174) | Cancela o escopo de sessões |
| POST | `/packages/:id/sessions` | `:add_session` | (grade+1) | Acrescenta uma sessão avulsa à série; reativa o pacote se estava `concluido` |
| DELETE | `/packages/:id/sessions/:appointment_id` | `:remove_session` | — | Remove uma sessão da série |
| POST | `/packages/:id/archive` | `:archive` | `archivePkg` [`:576`](../interface/Movimento.dc.html#L576) | Marca `concluido` e arquiva no histórico (habilitado quando `done`) |

Papéis: admin e membro em tudo; `profissional` restrito aos pacotes de seus pacientes.

Estados do pacote — a fonte real é `pkgStatusMeta`
([`:334`](../interface/Movimento.dc.html#L334)), não o seed (a linha `:117` é um único
registro `status:'ativo'` e não prova o enum). O `status` **persistido** de produção tem quatro
valores: `ativo`, `pausado`, `cancelado` e `concluido` (o `renovado` do protótipo **foi removido**
— não há renovação, [ADR-011](00-decisoes.md)). O `concluido` **é gravado**, não derivado: aparece
no seed ([`:108`](../interface/Movimento.dc.html#L108), [`:123`](../interface/Movimento.dc.html#L123),
[`:124`](../interface/Movimento.dc.html#L124)), é escrito pela ação `:archive` (`archivePkg`,
[`:576`](../interface/Movimento.dc.html#L576)) e é lido por `add_session`
([`:541`](../interface/Movimento.dc.html#L541)) para reativar o pacote (`concluido → ativo`). Só o
rótulo "Acabando" **não** é um valor de `status` gravado — é um estado **derivado**, computado por
`pkgEnding(pk)` a partir de sessões usadas/total e da data da última sessão, e só aparece quando
nenhum dos quatro `status` explícitos casa. No domínio Ash isto vira: um atributo enum `status` com
os quatro valores persistidos, e `acabando` como **calculation**, não como membro do enum.

Notas de contrato que vêm direto do protótipo:
- **`pause` pode aceitar uma data de retomada sugerida** (`resume_at?` opcional, no lugar do
  `retomaEm` "+21" hardcoded do protótipo, [`:554`](../interface/Movimento.dc.html#L554)).
  **Não há validade de pacote ([ADR-013](00-decisoes.md)/D6):** pausar não estende validade
  nenhuma — só tira as sessões futuras da agenda (`pkgHold`).
- **`resume` no protótipo devolve as sessões nas datas originais, já no passado**
  ([`:561`](../interface/Movimento.dc.html#L561), catalogado como job de reprojeção em
  [04-arquitetura §11](04-arquitetura.md#11-jobs-em-background-oban)). No contrato,
  `:resume` **reprojeta** as sessões para datas futuras — é uma correção deliberada, não o
  espelho do protótipo.
- **`bulk_adjust` carrega o `escopo`** (`esta` | `proximas` | `todas`) e flags
  `aplicar_profissional`/`aplicar_horario`, exatamente os campos de `applyMassaPacote`
  ([`:1149`](../interface/Movimento.dc.html#L1149)).
- **Não há `renew` ([ADR-011](00-decisoes.md)).** O protótipo era ambíguo (sucessor via
  `renovadoDe` [`:362`](../interface/Movimento.dc.html#L362) **e** `total += N` no mesmo pacote,
  `confirmRenovar` [`:590`](../interface/Movimento.dc.html#L590)); a produção **elimina a
  renovação**. O `total` é ajustado a qualquer momento por `add_session`/`remove_session`, sempre
  no mesmo pacote.

### 3.5 Profissionais, tipos, horário, feriados

| Método | Rota | Ação Ash | Papéis | Notas |
|---|---|---|---|---|
| GET | `/professionals` | `:read` | todos | |
| POST | `/professionals` | `:create` | admin | Coleta banco/PIX (sensível, ADR-007) |
| PATCH | `/professionals/:id` | `:update` | admin; próprio p/ profissional (campos limitados por field policy) | Dados bancários só o próprio/admin |
| GET | `/appointment-types` | `:read` | todos | |
| POST/PATCH/DELETE | `/appointment-types[/:id]` | `:create`/`:update`/`:destroy` | admin | `grupo`, `cap`, `dur`, `cor` |
| GET | `/clinic-hours` | `:read` | todos | Horário semanal da clínica |
| PATCH | `/clinic-hours` | `:update` | admin | **Ver aviso abaixo** |
| GET | `/holidays?filter[data][gte]=…` | `:read` | todos | Feriados e exceções de data |
| POST/DELETE | `/holidays[/:id]` | `:create`/`:destroy` | admin | `tipo` ∈ {feriado, horario} |

**Aviso de impacto retroativo em `PATCH /clinic-hours`.** Mudar o horário da clínica pode
deixar agendamentos futuros fora do expediente. É o motor `futureConflicts`
([`:864`](../interface/Movimento.dc.html#L864)), consumido por `hourConflicts`
([`:884`](../interface/Movimento.dc.html#L884)). O contrato: `:update` de horário roda uma
**checagem prévia** e, se houver conflitos, retorna `409` com a lista dos agendamentos
afetados (data, horário, profissional, motivo) **sem aplicar**. Só um segundo request com
`confirm: true` aplica. É o mesmo padrão de "decisão do usuário" da remarcação com colisão
([seção 9](#9-exemplo-end-to-end-remarcar-com-colisão-e-encaixe)). O mesmo vale para
exceção de data do profissional, que também aciona `futureConflicts`.

### 3.6 Fila de espera

| Método | Rota | Ação Ash | Origem | Papéis | Erros |
|---|---|---|---|---|---|
| GET | `/waitlist` | `:read` (ordem de domínio) | dados [`:163`](../interface/Movimento.dc.html#L163) | admin, membro, profissional | — |
| POST | `/waitlist` | `:enqueue` | `addFila` | admin, membro, profissional | `422` |
| PATCH | `/waitlist/:id` | `:update` | — | idem | — |
| DELETE | `/waitlist/:id` | `:dequeue` | [`:1186`](../interface/Movimento.dc.html#L1186) | idem | — |
| GET | `/waitlist/:id/slots` | ação genérica `:find_slots` | `filaVagas` [`:2531`](../interface/Movimento.dc.html#L2531) | idem | — |
| POST | `/waitlist/:id/offer` | `:offer` (cria `SlotHold`) | `offerVaga` [`:2596`](../interface/Movimento.dc.html#L2596) | idem | **`409` vaga já segurada** (ver §6) |
| POST | `/waitlist/:id/convert` | `:convert_to_appointment` | `createAppt` c/ `_fromFila` [`:1062`](../interface/Movimento.dc.html#L1062) | idem | `409` conflito; `422` |

O item da fila tem `prio` — a fonte real do enum é `prioMeta`
([`:2511`](../interface/Movimento.dc.html#L2511)), com **quatro** níveis: `urgente`, `alta`,
`normal` e `baixa` (a linha `:163` do seed só exibe `urgente` e não prova o conjunto). Tem
ainda `profIds` preferidos, `janela` (`manhã`/`tarde`/`qualquer`), `regras` de disponibilidade e
`obs` (queixa clínica — sensível, ADR-007). `GET /waitlist/:id/slots` é o motor `filaVagas`:
varre 14 dias, casa janela + regras, e **prioriza vagas que abriram** por cancelamento/falta
(`freed`), verificado na ordenação final de `filaVagas`
([`:2591`](../interface/Movimento.dc.html#L2591)). Por isso a ordenação da fila é de
domínio, não `?sort` do cliente.

O par `offer` → `convert` é onde mora a corrida de concorrência da
[seção 6.2](#62-reserva-de-vaga-hold). `offer` cria o hold; `convert` o consome criando o
agendamento e removendo o item da fila (o `_fromFila` do `createAppt`,
[`:1062`](../interface/Movimento.dc.html#L1062)).

### 3.7 Membros (equipe / acessos)

| Método | Rota | Ação Ash | Origem | Papéis |
|---|---|---|---|---|
| GET | `/members` | `:read` | [`:203`](../interface/Movimento.dc.html#L203) | admin |
| POST | `/members/invite` | `:invite` | `saveMembro` [`:2500`](../interface/Movimento.dc.html#L2500) | admin |
| PATCH | `/members/:id` | `:update` (papel/vínculo) | idem | admin |
| DELETE | `/members/:id` | `:revoke_access` | [`:2509`](../interface/Movimento.dc.html#L2509) | admin |

`status` do membro: `ativo`/`pendente` ([`:206`](../interface/Movimento.dc.html#L206)).
Convite cria membro `pendente`; ativa ao aceitar. Vínculo `profId` é opcional e único (um
membro `profissional` aponta para um profissional).

### 3.8 Relatórios

| Método | Rota | Ação Ash | Papéis | Resposta |
|---|---|---|---|---|
| GET | `/reports/summary?date_from=&date_to=&professional_id?=` | ação genérica `:summary` | admin (todos); profissional (próprio) | KPIs agregados |

KPIs verificados em `renderRelatorios` ([`:3367`](../interface/Movimento.dc.html#L3367),
[`:3455`](../interface/Movimento.dc.html#L3455)): atendimentos, concluídos, taxa de falta,
cancelamentos, ocupação, volume por dia/profissional, pico. No servidor isto é agregado Ash
empurrado ao SQL, alimentado por snapshot noturno para não varrer a tabela ao vivo
([04-arquitetura §11](04-arquitetura.md#11-jobs-em-background-oban)).

### 3.9 Anexos

| Método | Rota | Ação Ash | Papéis | Notas |
|---|---|---|---|---|
| GET | `/patients/:id/attachments` | `:read` | admin, membro, profissional(próprio) | Metadados, não bytes |
| POST | `/patients/:id/attachments` | `:request_upload` | idem | Retorna URL assinada de upload |
| GET | `/attachments/:id/url` | `:signed_download` | idem | URL assinada de vida curta |
| DELETE | `/attachments/:id` | `:destroy` | admin, profissional(próprio) | |

Anexos são laudos/exames — dado de saúde. Os **bytes nunca passam pela API**: o cliente
faz upload/download direto no object storage privado por URL assinada de vida curta, e a API
só troca metadados e assina URLs (ADR-007, item 4). Isso corrige o `URL.createObjectURL`
persistido do protótipo. Toda leitura de anexo entra na trilha `AshPaperTrail`.

### 3.10 Autenticação

Detalhada na [seção 8](#8-autenticação). Rotas: `POST /auth/sign_in`, `DELETE /auth/sign_out`,
`GET /auth/me`, e a emissão do token efêmero de WebSocket via `GET /realtime/token`.

---

## 4. Concorrência no contrato — visão geral

Duas corridas reais do protótipo ([04-arquitetura §7](04-arquitetura.md#7-concorrência-as-duas-corridas-reais))
viram elementos de contrato explícitos, não detalhes de implementação. Ambas usam
`409 Conflict`, mas com corpos diferentes. Detalhadas na [seção 6](#6-concorrência-no-contrato).

---

## 5. Erros

### 5.1 Erros de campo → `source.pointer`

A intenção é que erros de validação venham no formato de erros do JSON:API: um array `errors`,
cada um com `status`, `title`, `detail` e, quando o erro pertence a um campo, um
`source.pointer` apontando para o atributo (`/data/attributes/starts_at`).

> **Precisamos confirmar** ao scaffoldar: que o AshJsonApi de fato serializa
> `Ash.Error.Invalid` com `source.pointer` por campo (é o comportamento que esperamos,
> mas não foi verificado contra a doc — `// NAO-VERIFICADO: confirmar contra a doc ao scaffoldar`).

Importante para a fronteira do ADR-005/ADR-006: **`AshPhoenix.Form` não está neste caminho.**
Aquele módulo serve formulários HTML renderizados por Phoenix/LiveView; aqui o consumidor é o
BFF SvelteKit sobre JSON:API, sem LiveView no meio. Quem lê `source.pointer` e o mapeia de volta
ao input é o **form action do SvelteKit**, que faz o parsing do envelope de erro do JSON:API por
conta própria. A regra de `.claude/rules/ash_phoenix.md` continua relevante como *analogia* — o
mesmo risco de "erro sem campo some do formulário" existe — mas o mecanismo do `AshPhoenix.Form`
não é o que usamos. Exemplo de `422`:

```jsonc
{
  "errors": [
    {
      "status": "422",
      "title": "Invalid",
      "detail": "deve estar dentro do expediente do profissional",
      "source": { "pointer": "/data/attributes/starts_at" }
    }
  ]
}
```

### 5.2 O canal de erro **não-de-campo** (a correção do §4)

`.claude/rules/ash_phoenix.md` avisa: erros que não implementam o protocolo `FormData.Error`
ou não têm `field`/`fields` **não aparecem no formulário**. Neste domínio há erros que
legitimamente não pertencem a campo nenhum:

- **conflito de agenda** — o horário colide com outro agendamento do profissional
  (`checkConflict`, [`:834`](../interface/Movimento.dc.html#L834));
- **turma cheia** — capacidade do tipo excedida ([`:341`](../interface/Movimento.dc.html#L341));
- **hold de vaga já tomado** — outro atendente segurou a mesma vaga primeiro;
- **versão desatualizada** — o registro mudou desde que foi lido (lock otimista).

Um "input vermelho em `starts_at`" mente sobre um conflito de agenda: o horário digitado
pode estar perfeitamente válido; o problema é o mundo lá fora. O contrato:

1. **Conflito de agenda e turma cheia** voltam como `422` **sem** `source.pointer` (ou com
   `source.pointer` apontando `/data` inteiro, não um atributo), com um `code` estável em
   `meta` para o front discriminar:
   ```jsonc
   {
     "errors": [{
       "status": "422",
       "code": "schedule_conflict",
       "title": "Conflito de horário",
       "detail": "Marina já tem Fisioterapia às 09:00 neste horário.",
       "meta": { "conflicting_appointment_id": "a-2b7", "professional_id": "p1" }
     }]
   }
   ```
2. **Hold tomado e versão desatualizada** voltam como `409` (são concorrência, não validação
   de entrada) — [seção 6](#6-concorrência-no-contrato).

**Como o front consome.** O form action do SvelteKit separa erros com `source.pointer`
(vão para o input correspondente via `$state` do form) de erros sem ponteiro (vão para um
**banner de formulário** — um slot fixo no topo/rodapé do modal, nunca um input). O `code`
em `meta` decide a UX: `schedule_conflict` abre o fluxo de encaixe (oferecer override);
`group_full` desabilita o botão e explica; `version_conflict` mostra "Fulano moveu isto
enquanto você editava" com o estado atual. Sem esse canal separado, a ação falharia em
silêncio — exatamente a armadilha que a regra descreve.

### 5.3 Mapa de status HTTP

| Status | Quando |
|---|---|
| `200` | leitura, transição idempotente bem-sucedida |
| `201` | criação de recurso |
| `204` | destroy |
| `401` | sem sessão / token inválido |
| `403` | policy nega (dentro do tenant) |
| `404` | recurso inexistente **ou** fora do tenant (não confirmamos existência cruzada) |
| `409` | conflito de concorrência: versão divergente **ou** hold tomado |
| `422` | validação, incluindo conflito de agenda e turma cheia (não-de-campo) |
| `429` | rate limit |

A distinção `409` vs `422` é semântica e o front depende dela: `422` é "seu pedido está
errado, corrija"; `409` é "seu pedido estava certo, mas o mundo mudou embaixo de você,
reconcilie". Conflito de agenda é `422` (o horário pedido está errado agora); versão
divergente é `409` (o horário pedido estava certo quando você leu).

**Este mapa é uma decisão nossa, não um comportamento herdado da biblioteca.** Escolhemos
qual erro de domínio vira qual status. O que fica pendente de verificação é o *mecanismo* pelo
qual cada erro do Ash sai com o status certo pela porta do AshJsonApi:

> `// NAO-VERIFICADO: confirmar contra a doc ao scaffoldar` — que o AshJsonApi permite
> mapear (a) o erro de lock otimista para `409`, (b) o erro de exclusion constraint para `409`,
> e (c) os nossos erros de domínio de conflito de agenda/turma cheia para `422` **sem**
> `source.pointer`. O Ash tem `Ash.Error` com anotação de `http_status` por classe de erro; se o
> default de alguma dessas classes não for o status que decidimos, precisamos sobrescrevê-lo
> explicitamente na definição do erro/rota. Não afirmamos que "o AshJsonApi já traduz
> `version_conflict → 409`" — afirmamos que **é a nossa intenção** e que a confirmaremos.

---

## 6. Concorrência no contrato — detalhe

### 6.1 Locking otimista em remarcação

Todo `Appointment` carrega `version` (inteiro), serializado em `attributes.version`. Toda
ação de transição ([seção 3.1](#31-agenda--agendamentos)) exige `expected_version` no corpo.
Se a versão lida divergir da atual, o servidor **não aplica** e retorna `409` com o estado
atual do recurso e o autor da mudança:

```jsonc
// POST /appointments/a-8f3c/reschedule  com expected_version: 7, mas já está em 8
// → 409 Conflict
{
  "errors": [{
    "status": "409",
    "code": "version_conflict",
    "title": "Registro desatualizado",
    "detail": "Aline moveu este agendamento enquanto você editava.",
    "meta": {
      "current_version": 8,
      "updated_by": { "id": "u1", "nome": "Aline" }
    }
  }],
  "data": {            // estado atual embutido para a UI reconciliar sem novo GET
    "type": "appointment", "id": "a-8f3c",
    "attributes": { "starts_at": "2026-07-09T10:00:00-03:00", "status": "agendado", "version": 8 }
  }
}
```

No servidor, o desenho é: `expected_version` alimenta o mecanismo de **lock otimista** do Ash,
que filtra a escrita pela versão corrente e a incrementa atomicamente na mesma operação, e a
garantia final é do banco (a escrita condiciona ao `version` corrente). A forma exata desse
mecanismo é comportamento de biblioteca que **não podemos verificar aqui**:

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# - o nome do change built-in de lock otimista do Ash (algo como optimistic_lock(:version));
# - que ele filtra por versão e incrementa atomicamente numa só escrita, sem "change set_attribute" manual;
# - o módulo/classe exato do erro de "registro obsoleto" que ele levanta.
# É o mesmo ponto pendente de 04-arquitetura §7.3.
```

A UI, ao receber `409`, mostra o aviso e reoferece a decisão sobre o **estado novo**, em vez de
sobrescrever silenciosamente.

Independente do `version`, a **não-sobreposição por profissional** é garantida no banco por
uma *exclusion constraint* (`btree_gist` sobre `professional_id` + intervalo de tempo, com
exceção para `encaixe`) — [04-arquitetura §7](04-arquitetura.md#7-concorrência-as-duas-corridas-reais).
A validação Ash dá a mensagem bonita (`checkConflict`, [`:834`](../interface/Movimento.dc.html#L834),
que verifica `encaixe` e ignora `cancelado`); a constraint garante que a mensagem é verdade
mesmo sob corrida. O DDL exato dessa *exclusion constraint parcial* (com o predicado
`WHERE (encaixe = false AND status <> 'cancelado')`, que é imutável e portanto **válido**)
está em [04-arquitetura §7.1](04-arquitetura.md#71-a-garantia-final-de-não-sobreposição-exclusion-constraint).
Se dois requests passam pela validação e colidem no commit, o segundo recebe `409` — sujeito à
confirmação, na [seção 5.3](#53-mapa-de-status-http), de que o erro de exclusion constraint é
mapeado para esse status.

### 6.2 Reserva de vaga (hold)

`POST /waitlist/:id/offer` cria um `SlotHold` com um TTL curto — **parâmetro de design a
validar**, provisoriamente 5 min. Não é fato do protótipo (o protótipo não tem reserva alguma:
`offerVaga`, [`:2596`](../interface/Movimento.dc.html#L2596), só pré-preenche um modal); é uma
decisão nossa e o valor exato ("quanto tempo uma vaga fica segurada?") fica em aberto até
observarmos o uso real.

O hold é protegido por uma *exclusion constraint* sobre
`(professional_id, tstzrange(starts_at, ends_at))`. **Atenção ao DDL — corrigido em
[04-arquitetura §7.2](04-arquitetura.md#72-reserva-de-vaga-na-fila-hold--e-por-que-now-não-pode-entrar-na-constraint).**
A versão anterior deste documento dizia que a constraint era "filtrada por holds não expirados"
via `WHERE expires_at > now()`. **Isso é DDL inválido:** o predicado de uma exclusion constraint
precisa ser imutável, e `now()` é `STABLE`, não `IMMUTABLE` — o Postgres **recusa** criar a
constraint. O desenho correto:

1. A constraint cobre **todos** os holds vivos, **sem** predicado de tempo.
2. A ação `:offer`, dentro da própria transação e **antes** de inserir, apaga os holds já
   vencidos daquele profissional (`DELETE FROM slot_holds WHERE professional_id = $1 AND expires_at <= now()`).
   Em DML, `now()` é perfeitamente válido, e é o **relógio do banco** — não o relógio injetável
   da clínica do ADR-009. O ADR-009 governa as decisões de **negócio** dependentes de data
   ("hoje", "já começou", debitar sessão, expirar regra de fila); a expiração de um hold é
   *housekeeping* de infraestrutura de reserva, não uma decisão de agenda, então usa o relógio
   do banco na DML. Essa limpeza in-transaction fecha deterministicamente a janela entre
   "venceu" e "o coletor apagou".
3. Um job Oban (cron, 1 min) é apenas **backstop** de limpeza para holds de profissionais que
   ninguém tentou reservar; a correção nunca depende dele.

Dois atendentes oferecendo a mesma vaga: o primeiro cria o hold, o segundo — depois de o
passo (2) apagar o que venceu — recebe `409` **imediatamente** da constraint, com quem segurou:

```jsonc
// POST /waitlist/f2/offer  {professional_id:"p1", starts_at:"…T09:00-03:00", duration:50}
// → 409 Conflict  (segundo atendente)
{
  "errors": [{
    "status": "409",
    "code": "slot_held",
    "title": "Vaga já reservada",
    "detail": "João está oferecendo este horário (expira em 4 min).",
    "meta": {
      "held_by": { "id": "u5", "nome": "João" },
      "expires_at": "2026-07-09T11:46:00-03:00"
    }
  }]
}
```

O `expires_at` no corpo (e o "expira em N min" do `detail`) é ilustrativo, derivado do TTL
provisório acima. Sucesso retorna o `SlotHold` (`201`) com `id` e `expires_at`; a conversão
`POST /waitlist/:id/convert` consome o hold, cria o agendamento e remove o item da fila numa
transação. Como já dito, a correção sob corrida vem do par constraint-sem-tempo +
`DELETE ... expires_at <= now()` in-transaction do passo (2); o job Oban de minuto a minuto é
só higiene, nunca a fonte da garantia.

---

## 7. Eventos de Phoenix Channel

Os eventos de tempo real são **parte do contrato de API tanto quanto o REST**. O cliente
Svelte usa o pacote npm `phoenix` direto contra o Phoenix (ADR-004), autenticado pelo token
efêmero da [seção 8](#8-autenticação). O desenho: configuramos um `Ash.Notifier` nos recursos
e ações que nos interessam, que publica no `Phoenix.PubSub`, e o Channel reenvia. Não afirmo
que "o Ash emite notificação em toda mutação automaticamente" — isso é comportamento de
biblioteca que precisa confirmação
(`# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar` — se as notificações do Ash são
opt-in por notifier/ação, o formato do payload de notificação, e se transações agrupam
notificações até o commit). O que o ADR-004 trava é a **arquitetura** (PubSub alimentado por
notificações do Ash); os eventos abaixo são o contrato que emitiremos, não uma lista do que a
biblioteca dispara sozinha.

### 7.1 Tópicos

Verbatim de [04-arquitetura §6](04-arquitetura.md#6-tempo-real):

```
clinic:<clinic_id>:agenda:<YYYY-MM-DD>   # uma agenda de um dia
clinic:<clinic_id>:waitlist              # fila de espera + holds
clinic:<clinic_id>:presence              # quem está olhando o quê
```

O cliente entra no tópico do dia visível e sai ao navegar; o `clinic_id` do tópico é
validado contra o tenant do token no `join` — não basta pedir, a policy do Channel confere.
A vista semanal/mensal entra em vários tópicos de dia (ou um tópico de intervalo dedicado,
decisão de implementação deixada em aberto para não vazar barulho).

### 7.2 Eventos da agenda

Payload é evento semântico com o recurso já serializado, não "invalide tudo"
([04-arquitetura §6](04-arquitetura.md#6-tempo-real)). O cliente aplica patch no store de
runes; se o evento é para um recurso que ele não tem, ignora.

| Evento | Quando | Payload (essencial) |
|---|---|---|
| `appointment_scheduled` | `:schedule` | `{appointment: {…, version}, actor}` |
| `appointment_rescheduled` | `:reschedule` | `{appointment: {id, starts_at, professional_id, version}, actor}` |
| `appointment_status_changed` | `complete`/`no_show`/`confirm`/`start`/`cancel`/`justify_absence` | `{appointment: {id, status, version}, actor, package_debit?: bool}` |
| `appointment_canceled` | `:cancel` | `{appointment_id, version, actor}` |
| `participant_added` / `participant_removed` | turma | `{appointment_id, patient_id, version, actor}` |

`package_debit` no evento de status permite a UI atualizar o contador de sessões do pacote
sem refazer o cálculo `wouldConsume` no cliente. Forma do payload
(`# NAO-VERIFICADO: confirmar a forma exata do push do Phoenix.Channel ao scaffoldar`):

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
%{
  event: "appointment_rescheduled",
  appointment: %{id: "a-8f3c", starts_at: "2026-07-09T10:00:00-03:00",
                 professional_id: "p1", status: "agendado", version: 8},
  actor: %{id: "u1", nome: "Aline"}
}
```

### 7.3 Eventos da fila

| Evento | Quando | Payload |
|---|---|---|
| `waitlist_entry_added` | `:enqueue` | `{entry, actor}` |
| `waitlist_entry_removed` | `:dequeue`/`:convert` | `{entry_id, reason: "converted"\|"removed", actor}` |
| `slot_held` | `:offer` | `{hold: {id, professional_id, starts_at, expires_at, held_by}, waitlist_id}` |
| `slot_released` | hold expira/converte | `{hold_id, reason: "expired"\|"converted"}` |

`slot_held` é o que torna a corrida da [seção 6.2](#62-reserva-de-vaga-hold) **visível**:
os outros atendentes veem a vaga esmaecer em tempo real antes mesmo de tentar, o que
[04-arquitetura §6](04-arquitetura.md#6-tempo-real) chama de "evitar metade dos conflitos
por simplesmente tornar visível que outra pessoa está lá".

### 7.4 Presence

`Phoenix.Presence` no tópico da agenda: `presence_state` no join e `presence_diff` nas
mudanças, formato padrão do `Phoenix.Presence`
(`# NAO-VERIFICADO: confirmar payload de presence_diff ao scaffoldar`). Mostra quem mais
está no mesmo dia.

### 7.5 Contrato de reconexão

O cliente que reconecta pode ter perdido eventos. O contrato: ao (re)entrar num tópico de
agenda, o cliente faz um `GET /appointments` do dia para ressincronizar o estado, e o
`invalidate()` do SvelteKit é o fallback quando um patch de evento não é aplicável
([04-arquitetura §6](04-arquitetura.md#6-tempo-real)). Eventos são otimização sobre um estado
que o REST sempre pode reconstituir, nunca a única fonte de verdade.

---

## 8. Autenticação

`AshAuthentication` com sessão por **cookie** `HttpOnly`, `Secure`, `SameSite=Lax`
([04-arquitetura §5](04-arquitetura.md#5-autenticação)). O fluxo:

- `POST /auth/sign_in` `{email, password}` → `200` + `Set-Cookie` de sessão. O BFF do
  SvelteKit guarda o cookie e o repassa nas chamadas server-to-server; **o cookie de sessão
  nunca vai para o JS do navegador**.
- `DELETE /auth/sign_out` → `204`, invalida a sessão.
- `GET /auth/me` → `{user: {id, nome, papel, professional_id?}}`, para o BFF montar o menu e
  as permissões de UI (que são espelho — a autoridade é a policy do servidor).
- `GET /realtime/token` → `{token, expires_at}`. O BFF pede este **token efêmero**
  (Phoenix.Token, minutos de vida) em nome da sessão e o entrega ao cliente no `load`. É só
  esse token que vai para o JS e para o WebSocket. Escopo do token: o `clinic_id` e o
  `user_id`, para o `join` do Channel validar o tópico.

O `Authorization: Bearer` do diagrama de [04-arquitetura §1](04-arquitetura.md#1-visão-geral)
é o **cookie repassado**, não um token de longa duração no browser — o único token no cliente
é o efêmero de WebSocket. Convite de membro ([seção 3.7](#37-membros-equipe--acessos)) tem
seu próprio fluxo de aceite, a ser detalhado quando `AshAuthentication` for scaffoldado
(`# NAO-VERIFICADO: confirmar estratégias e rotas geradas pelo AshAuthentication`).

---

## 9. Versionamento, depreciação e paginação

### 9.1 Versionamento

Versão na **URL**: `/api/v1/...`. É o BFF que fala com a API, não o público, então o custo
de um prefixo de versão é baixo e o ganho de clareza é alto. Uma mudança incompatível abre
`/api/v2/...`; `v1` e `v2` coexistem enquanto o BFF migra. Rejeito versionamento por header
(`Accept` com `;version=`) porque torna as rotas menos inspecionáveis e o cache mais difícil,
e aqui não há terceiros que justifiquem a sofisticação.

### 9.2 Depreciação

Um endpoint em vias de sair responde com header `Deprecation: true` e `Sunset: <data>`
(RFCs de Deprecation/Sunset). Como o único consumidor é o BFF interno, a "depreciação" na
prática é uma tarefa de migração coordenada entre os dois apps, não uma negociação com
clientes externos — o header existe para telemetria e para não esquecer.

### 9.3 Paginação de listas grandes

A agenda de um **mês** é a lista grande do domínio. Estratégia por recurso:

- **`GET /appointments` por intervalo de datas** — não pagina por página; pagina pela
  **janela de tempo** (`filter[starts_at]` entre início e fim do intervalo visível) e usa
  **sparse fieldsets** ([seção 1.3](#13-sparse-fieldsets)) para enxugar cada item. Um mês de
  uma clínica são centenas, não milhões, de agendamentos, e a vista precisa de todos os do
  intervalo de uma vez para o layout de raias (`layoutAppts`,
  [`:1576`](../interface/Movimento.dc.html#L1576), que roda no cliente). Paginar por página
  quebraria a coloração de grafo de intervalos. O limite natural é o intervalo de datas.
- **`GET /patients`, `GET /members`** — paginação **keyset** por `nome`/`id`, `page[after]`
  + `page[limit]`, para listas que crescem sem teto. Keyset e não offset porque são listas
  que mudam sob paginação e offset pula/repete itens.
- **`GET /waitlist`, `GET /appointment-types`, `GET /holidays`** — sem paginação; são listas
  curtas por natureza. A fila tem ordem de domínio (prioridade + vagas que abriram), não
  `?sort`.

O `meta` de contagem só vem na paginação offset; keyset entrega `links.next` e para quando
não há mais. `# NAO-VERIFICADO: confirmar os nomes exatos dos parâmetros de paginação keyset do AshJsonApi ao scaffoldar`.

---

## 10. Exemplo end-to-end: remarcar com colisão e encaixe

O caso que exercita erro não-de-campo, `409`, decisão do usuário e o caminho de override
(`encaixe`). É a tradução fiel do fluxo de arrastar do protótipo:
`startDrag` → `checkConflict` → modal `override` ([`:1258`](../interface/Movimento.dc.html#L1258)).

**Cenário.** Aline arrasta o bloco de Marina das 09:00 para as 10:00, mas Marina já tem
outro paciente às 10:00. Aline leu o agendamento na versão 7.

**Passo 1 — tentativa de remarcação.** O BFF envia:

```http
POST /api/v1/appointments/a-8f3c/reschedule
Content-Type: application/vnd.api+json

{ "data": { "type": "appointment", "attributes": {
  "starts_at": "2026-07-09T10:00:00-03:00",
  "expected_version": 7,
  "encaixe": false
}}}
```

**Passo 2 — o servidor detecta a colisão.** A versão bate (ainda é 7), mas `checkConflict`
([`:834`](../interface/Movimento.dc.html#L834)) encontra sobreposição com o agendamento das
10:00 do mesmo profissional, sem `encaixe`. Retorna `422` no canal não-de-campo
([seção 5.2](#52-o-canal-de-erro-não-de-campo-a-correção-do-4)):

```jsonc
// 422 Unprocessable Entity
{
  "errors": [{
    "status": "422",
    "code": "schedule_conflict",
    "title": "Conflito de horário",
    "detail": "Marina já tem Pilates às 10:00.",
    "meta": { "conflicting_appointment_id": "a-2b7", "professional_id": "p1" }
  }]
}
```

**Passo 3 — decisão do usuário.** O front, vendo `code: "schedule_conflict"`, **não** pinta
input vermelho — abre o modal de override (o mesmo `openModal('override', …)` do protótipo, aberto no
*drop* conflitante do arrasto, [`:1258`](../interface/Movimento.dc.html#L1258): o
handler chama `checkConflict` na linha anterior e, se `conf` é verdadeiro, abre
`openModal('override', …)`): "Já há um atendimento neste horário.
Encaixar mesmo assim?" Aline escolhe encaixar.

**Passo 4 — remarcação com encaixe.** O BFF reenvia, agora com `encaixe: true` e a **versão
ainda lida** (nada mudou, continua 7):

```http
POST /api/v1/appointments/a-8f3c/reschedule
Content-Type: application/vnd.api+json

{ "data": { "type": "appointment", "attributes": {
  "starts_at": "2026-07-09T10:00:00-03:00",
  "expected_version": 7,
  "encaixe": true
}}}
```

`checkConflict` retorna `null` quando `encaixe` é verdadeiro
([`:835`](../interface/Movimento.dc.html#L835): `if(encaixe) return null;`), e a exclusion
constraint do banco tem a exceção para `encaixe` ([seção 6.1](#61-locking-otimista-em-remarcação)).
A escrita condiciona ao `version == 7`, aplica, e incrementa para 8. Resposta:

```jsonc
// 200 OK
{ "data": { "type": "appointment", "id": "a-8f3c", "attributes": {
  "starts_at": "2026-07-09T10:00:00-03:00", "status": "agendado",
  "encaixe": true, "version": 8
}}}
```

**Passo 5 — broadcast.** O `Ash.Notifier` publica em
`clinic:<id>:agenda:2026-07-09`, e todo cliente no dia recebe:

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
%{event: "appointment_rescheduled",
  appointment: %{id: "a-8f3c", starts_at: "2026-07-09T10:00:00-03:00",
                 professional_id: "p1", status: "agendado",
                 encaixe: true, version: 8},
  actor: %{id: "u1", nome: "Aline"}}
```

Cada cliente aplica o patch no store de runes e recolore as raias com `layoutAppts` no
próprio navegador — o encaixe aparece marcado, sobreposto, como manda o layout de grafo de
intervalos.

**Variante — corrida perdida.** Se, entre os passos 1 e 4, João tivesse movido o mesmo
bloco (versão foi para 8), o passo 4 com `expected_version: 7` receberia `409`
`version_conflict` com o estado atual embutido ([seção 6.1](#61-locking-otimista-em-remarcação)),
e o front mostraria "João moveu este agendamento enquanto você editava" com o novo estado,
em vez de sobrescrever a mudança de João em silêncio. É a diferença entre o `checkConflict`
em memória do protótipo (que roda sobre uma lista local e não vê o outro usuário) e o
contrato multiusuário que este documento define.

---

## Correções desta revisão

Alterações feitas em resposta à auditoria adversarial, cada uma verificada contra o protótipo
ou contra os ADRs.

1. **DDL inválido no `SlotHold` (§6.2) — o mais grave.** A versão anterior dizia que a exclusion
   constraint dos holds era "filtrada por holds não expirados" e que "a constraint já os ignora
   por `expires_at > now()`". Isso é **DDL inválido**: o predicado de uma exclusion constraint
   precisa ser imutável e `now()` é `STABLE`. Reescrito para o desenho de
   [04-arquitetura §7.2](04-arquitetura.md#72-reserva-de-vaga-na-fila-hold--e-por-que-now-não-pode-entrar-na-constraint):
   constraint **sem** predicado de tempo cobrindo todos os holds vivos + `DELETE ... expires_at <= now()`
   in-transaction na ação `:offer` + job Oban só como backstop.

2. **Três afirmações de API declaradas como fato receberam marcação/reescrita.**
   (a) O mapa de status HTTP (`version_conflict → 409`, conflito de agenda → `422`) foi
   explicitado como **decisão nossa**, com nota `NAO-VERIFICADO` sobre o *mecanismo* pelo qual o
   AshJsonApi emite cada status (§5.3). (b) A composição "field_policies + sparse fieldsets ⇒
   campo negado some silenciosamente" foi reescrita como comportamento **a confirmar**, não fato
   (§1.3). (c) O lock otimista ("validação atômica na changeset") foi marcado `NAO-VERIFICADO`
   quanto ao nome do change built-in, à atomicidade e à classe de erro (§6.1). Também marcado o
   "Ash emite notificações em toda mutação" (§7).

3. **Citação refutada `openModal('override')` [:1256] → [:1258].** A linha 1256 é
   `const field='profId';`; o modal de override é aberto no *drop* conflitante do arrasto na
   linha **1258** (`if(conf){ ... this.openModal('override',{...}); }`), após o `checkConflict`
   da 1257. Corrigido nas duas ocorrências (§10).

4. **Proveniência ausente, corrigida.** (a) TTL do hold "5 min" / "expira em 4 min" reetiquetado
   como **parâmetro de design a validar**, não fato do protótipo (§6.2). (b) Estados do pacote:
   a fonte real é `pkgStatusMeta` ([`:334`](../interface/Movimento.dc.html#L334)) — quatro valores
   **persistidos** (`ativo`, `pausado`, `cancelado`, `concluido`; o `renovado` do protótipo foi
   removido, [ADR-011](00-decisoes.md)); só "Acabando" é **derivado** (`pkgEnding`), enquanto
   `concluido` **é gravado** (seed, `archivePkg` [`:576`](../interface/Movimento.dc.html#L576), lido
   por `add_session` [`:541`](../interface/Movimento.dc.html#L541)). A `:117` (seed) não prova o enum
   (§3.4). (c) Prioridade da fila: a fonte é `prioMeta` ([`:2511`](../interface/Movimento.dc.html#L2511)),
   com **quatro** níveis — `urgente`, `alta`, `normal`, `baixa` (a `:163` só exibe `urgente`) (§3.6).

5. **Referências de seção ao 04-arquitetura corrigidas** para a numeração real: Contrato §3→**§4**,
   Tempo real §4→**§6**, Concorrência §5→**§7**, Jobs Oban §6→**§11**, Autenticação §3→**§5**,
   com as âncoras correspondentes.

6. **Contradições com ADR resolvidas.** (a) `AshPhoenix.Form` foi removido do caminho de mapeamento
   de erro — ele serve formulários HTML de Phoenix/LiveView, e o ADR-005/006 põem o SvelteKit como
   BFF sobre JSON:API, sem LiveView; quem lê `source.pointer` é o form action do SvelteKit (§5.1).
   (b) O `now()` do hold foi reatribuído ao **relógio do banco em DML**, não ao relógio injetável
   da clínica: o ADR-009 governa decisões de **negócio** dependentes de data, não o *housekeeping*
   de TTL de reserva (§6.2). (c) "Ash emite notificações em toda mutação" foi reduzido ao que o
   ADR-004 de fato trava — a **arquitetura** (PubSub alimentado por `Ash.Notifier`) — sem afirmar
   comportamento automático da biblioteca (§7).

7. **Lacuna de turma multi-pacote fechada (nova §3.1.1).** O `attendance` foi ligado ao `pkgOf`
   do protótipo ([`:350`](../interface/Movimento.dc.html#L350)) e a `apptPkg`
   ([`:1110`](../interface/Movimento.dc.html#L1110)): cada participante da turma tem **seu próprio
   pacote**, então `package_id` é atributo do `attendance`, não do `appointment`. Especificados o
   payload do `attendance`, o `package_id?` em `:add_participant`, o consumo de sessão por
   participante e — o ponto que a auditoria cobrou — a semântica de `:bulk_adjust`/`:bulk_cancel`
   operando sobre presenças filtradas por `package_id`, não sobre o bloco de grupo inteiro.
