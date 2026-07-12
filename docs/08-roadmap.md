# Roadmap — Por onde começamos

Este documento responde à pergunta que originou o projeto: **por onde começamos?**
Ele não estima prazo. O usuário não deu capacidade de time, então falar em semanas
ou pontos seria inventar. O que este documento fixa é **ordem e dependência**: o que
vem antes do quê, e por quê. As decisões que sustentam cada escolha estão em
[00-decisoes.md](00-decisoes.md); o desenho de sistema, em [04-arquitetura.md](04-arquitetura.md).

> **Nota de proveniência (atualizada em 2026-07-10).** Os documentos
> [01-dominio-ash.md](01-dominio-ash.md), [02-regras-e-lacunas.md](02-regras-e-lacunas.md) e
> [03-frontend-sveltekit.md](03-frontend-sveltekit.md) — que rodadas anteriores deste roadmap
> davam como inexistentes — **já existem e são densos**: o `02` traz o catálogo formal de regras
> (RN-01…RN-60) e lacunas (GAP-01…16), e o `01`, o modelo Ash completo. O catálogo provisório de
> GAPs de [§9](#9-catálogo-provisório-de-gaps-para-o-02) foi **absorvido e renumerado** pelo `02`
> (a numeração canônica é a do `02`; onde §9 divergir, vale o `02`). Os documentos
> [05-observabilidade-e-producao.md](05-observabilidade-e-producao.md) e
> [06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md) também existem. As decisões de produto que este
> roadmap listava como abertas foram fechadas em [10-decisoes-de-produto-v1.md](10-decisoes-de-produto-v1.md)
> e nos ADRs 011–013; o resumo consolidado é [11-resumo-consolidado.md](11-resumo-consolidado.md).

---

## 1. Princípio: fatias verticais, nunca camadas horizontais

Existem duas maneiras de sair de um protótipo para produção. A errada é horizontal:
"primeiro modelamos todo o domínio no Ash, depois toda a API, depois todo o realtime,
depois toda a UI". A certa é vertical: escolher **uma funcionalidade fina e completa** e
levá-la do banco à tela, passando por API, autorização, tempo real e interação, antes de
abrir a segunda funcionalidade.

A abordagem horizontal falha por três motivos, todos agudos neste projeto:

1. **O risco fica escondido até o fim.** Se modelarmos 12 recursos Ash e só então
   tentarmos desenhar a agenda com raias, descobriremos tarde demais que o `layoutAppts`
   ([`Movimento.dc.html:1576`](../interface/Movimento.dc.html#L1576) — `layoutAppts(appts)`)
   ou a exclusion constraint de não-sobreposição têm uma consequência de modelagem que
   obriga a refazer schema. Fatia vertical força o encontro com o risco no primeiro dia.

2. **Nada é demonstrável até que tudo esteja pronto.** Uma pilha de recursos sem tela não
   é apresentável para quem decide produto. Uma agenda que carrega e cria um agendamento,
   ainda que só isso, é.

3. **As quatro camadas deste sistema têm contratos que só se validam juntos.** O ADR-004
   (realtime) e o ADR-005 (BFF) definem um fluxo — mutação no Ash → notificação → PubSub →
   Channel → patch no store de runes — que não pode ser testado por partes. Ou a fatia
   atravessa tudo, ou o contrato entre camadas segue não-verificado.

Portanto: **cada fatia deste roadmap é ponta-a-ponta.** Ela toca Postgres, Ash, AshJsonApi,
policy, Channel e UI Svelte. Uma fatia só está "pronta" quando um humano consegue exercê-la
no navegador contra a API real.

---

## 2. Fatia 0 — O andaime (provar o pipeline antes de qualquer regra)

**Objetivo:** levar um "hello" trivial do banco à produção, com observabilidade ligada,
**antes de escrever uma única regra de negócio.** O que estamos validando aqui não é código
de domínio — é o encanamento: dois serviços, dois deploys, um contrato entre eles, e a
telemetria enxergando tudo. Se o pipeline não fecha, nenhuma fatia de negócio fecha.

Não há regra de precedência de disponibilidade, nem pacote, nem prontuário nesta fatia.
Há um recurso Ash bobo (por exemplo, um `Ping` com um campo e uma ação `:read`) exposto por
AshJsonApi, lido pelo BFF do SvelteKit e renderizado numa página. E há um deploy real.

### Passos

O repositório hoje não tem projeto Elixir nem SvelteKit. O andaime cria os dois.

1. **Backend Elixir/Ash via Igniter.** O Igniter é o framework de geração e *patching*
   semântico de código descrito em [.claude/rules/igniter.md](../.claude/rules/igniter.md);
   ele não só cria arquivos, mas modifica `mix.exs`, `config/*.exs` e a árvore de aplicação
   de forma idempotente (módulos `Igniter.Project.Deps`, `Igniter.Project.Config`,
   `Igniter.Project.Application`). Usar os instaladores do Ash em vez de escrever
   `mix.exs` à mão é o caminho suportado.

   ```bash
   # NAO-VERIFICADO: confirmar contra hexdocs/igniter ao scaffoldar
   mix archive.install hex igniter_new
   mix igniter.new movimento_api --install ash,ash_postgres,ash_phoenix,ash_json_api,ash_authentication
   ```

   As dependências correspondem ao stack travado no ADR-002 (Ash 3.x + AshPostgres +
   AshJsonApi sobre Phoenix) e no ADR-004 (Phoenix para os Channels). `AshPaperTrail`,
   `AshCloak` e `Oban` **não** entram no andaime — eles chegam nas fatias que os exigem
   (prontuário, hold), para não pagar complexidade antes da hora.

2. **Multitenancy desde o primeiro recurso.** O ADR-003 é explícito: toda entidade nasce
   escopada a uma clínica. Mesmo o `Ping` do andaime carrega tenant. A escolha concreta
   entre `strategy :context` (schema por tenant) e `strategy :attribute` (`clinic_id`) é do
   [01-dominio-ash.md](01-dominio-ash.md); o andaime materializa a que ele recomendar.
   O ponto de fazer isso já: adicionar tenancy depois de existir dado de saúde é caro
   (ADR-003).

3. **Relógio injetável desde o primeiro recurso.** O ADR-009 proíbe qualquer módulo de
   domínio de ler o relógio do sistema. O andaime já estabelece o padrão de passar o tempo
   pelo contexto/escopo da ação, e cada clínica já nasce com um timezone canônico persistido.
   Isso é barato agora e impagável depois — o protótipo congela o tempo em
   `hoje()` retornando a string `'2026-06-25'`
   ([`Movimento.dc.html:1098`](../interface/Movimento.dc.html#L1098) —
   `hoje(){ return '2026-06-25'; }`) e num `NOW=702` fixo
   ([`Movimento.dc.html:2533`](../interface/Movimento.dc.html#L2533) —
   `const TODAY='2026-06-25', NOW=702, DUR=50, DAYS=14, STEP=30, CAP=50;`), e essa constante
   contamina toda regra que depende de passado/futuro. Congelar o tempo em teste é bom;
   congelá-lo no código de produção é o defeito que estamos eliminando.

4. **BFF SvelteKit.** Projeto SvelteKit 2 + Svelte 5 (runes) + TypeScript, `adapter-node`
   (ADR-006). Um `+page.server.ts` que chama a API Phoenix por JSON:API e renderiza o
   resultado. Sem conexão de banco no web (ADR-005). A abertura de WebSocket direto contra
   o Phoenix pode ficar como um "ping" de fumaça para provar o caminho do Channel.

   ```bash
   # NAO-VERIFICADO: confirmar comando/flags do create-svelte atual ao scaffoldar
   npm create svelte@latest movimento_web
   ```

5. **Autenticação, esqueleto.** `AshAuthentication` **sem senha** — **Google OAuth + Magic
   Link** (ADR-015) — com sessão por cookie (`HttpOnly`, `Secure`, `SameSite=Lax`) e o repasse
   de cookie server-to-server do BFF, conforme [04-arquitetura.md](04-arquitetura.md) §5. No
   andaime basta uma sessão que prove o fluxo (ex.: magic link em dev); o RBAC de verdade e a
   troca de tenant (ADR-014) estreiam na fatia de identidade/Fatia 1.

6. **CI e deploy até produção.** Dois apps Fly na região `gru`, Postgres gerenciado, seguindo
   ADR-008. Pipeline de CI que roda `mix test` / `mix credo` / build do SvelteKit, e um
   deploy real do "hello". **OpenTelemetry puro ligado** desde este deploy: o trace de uma
   requisição precisa atravessar browser → BFF → API → Postgres e aparecer no coletor. Se o
   trace não fecha, o andaime não está pronto.

### Critério de pronto

Um humano abre a URL de produção, a página renderiza um dado que veio do Postgres via Ash
via BFF, o WebSocket conecta, e o trace completo dessa visita está visível no backend de
telemetria. **Nenhuma regra de negócio foi escrita.** Esse é exatamente o ponto.

---

## 3. Fatia 1 — Agenda do dia (leitura + criar agendamento)

**Esta é a fatia vertical certa para começar o produto, e a razão é risco.** A agenda é o
coração do sistema e concentra a maior parte do risco técnico. O princípio de fatia vertical
manda atacar o risco cedo; a agenda *é* o risco. Escopo deliberadamente mínimo: **ver a
agenda de um dia e criar um agendamento nela.** Sem remarcar, sem concluir, sem faltar —
essas transições são a Fatia 2.

### Por que ela, e não algo "mais fácil"

Uma tela de listagem de pacientes seria mais fácil e provaria menos. A agenda do dia, mesmo
só com leitura + criação, exercita de uma vez quase todo o encanamento de risco do sistema:

- **Tenancy e auth reais** (ADR-003, ADR-005): a agenda só mostra os agendamentos da clínica
  do usuário logado, resolvida pela sessão, nunca por `clinic_id` vindo do cliente
  ([04-arquitetura.md](04-arquitetura.md) §3).

- **RBAC** (ADR-002 via `Ash.Policy.Authorizer`): quem é `recepcao`, quem é `profissional` e
  quem é `admin`/`owner` vê e cria coisas diferentes. Três papéis vêm do protótipo
  (`papel:'admin'`, `papel:'profissional'`, `papel:'membro'`→`recepcao`, verificados em
  [`Movimento.dc.html:203`](../interface/Movimento.dc.html#L203) e seguintes); o **`owner`** é
  acréscimo do modelo Vercel ([ADR-016](00-decisoes.md)). A policy nasce aqui, na primeira tela,
  não numa "fase de segurança" que nunca chega.

- **`dayPeriods` — disponibilidade por precedência de 4 camadas**
  ([`Movimento.dc.html:854`](../interface/Movimento.dc.html#L854) —
  `dayPeriods(prof,date,hoursOverride)`): para oferecer horários válidos ao criar, o servidor
  precisa resolver a disponibilidade do profissional naquele dia. É o motor
  `Movimento.Scheduling.Availability` de [04-arquitetura.md](04-arquitetura.md) §2. **Nesta
  fatia as camadas de origem (horário da clínica, feriado, horário do profissional) vêm do
  seed**, derivado do próprio protótipo (PRNG determinístico em
  `Movimento.dc.html:43-263`); a *edição* dessas camadas é a Fatia 7. Assim conseguimos
  disponibilidade real sem antes construir a tela de configuração.

- **`checkConflict` + a exclusion constraint** (o maior perigo silencioso):
  ([`Movimento.dc.html:834`](../interface/Movimento.dc.html#L834) —
  `checkConflict(profId,start,dur,date,ignoreId,encaixe)`). No protótipo isso roda em memória
  sobre uma lista local. No servidor, a garantia final de não-sobreposição por profissional é
  uma exclusion constraint no Postgres (`btree_gist` sobre `professional_id` + intervalo,
  com exceção para `encaixe`), como manda [04-arquitetura.md](04-arquitetura.md) §7.1. Criar um
  agendamento é a primeira ação que precisa dessa constraint existir — por isso ela nasce
  aqui.

- **`layoutAppts` — coloração de grafo de intervalos para as raias**
  ([`Movimento.dc.html:1576`](../interface/Movimento.dc.html#L1576)): a agenda desenha blocos
  em raias para que sobreposições fiquem lado a lado. É o único dos quatro motores que
  **fica no cliente** como função pura (ADR-006; [04-arquitetura.md](04-arquitetura.md) §2), e
  portar essa coloração de React para Svelte 5 é o primeiro teste de fogo do port não-mecânico
  (ver Risco §7). O grid absoluto de posicionamento por minuto entra junto.

- **O primeiro evento de PubSub** (ADR-004): quando um atendente cria um agendamento, a
  agenda de quem mais está olhando o mesmo dia atualiza sem refresh. O tópico é
  `clinic:<id>:agenda:<YYYY-MM-DD>` ([04-arquitetura.md](04-arquitetura.md) §4). Este é o
  primeiro exercício real do caminho notificação-Ash → PubSub → Channel → patch de store.

Nenhuma outra fatia entrega tantos riscos de uma vez. Atacá-la primeiro é a decisão que mais
reduz incerteza do programa.

### Escopo

Ler a agenda de **um** dia (um profissional ou todos, conforme papel), com as raias
posicionadas; e criar um agendamento simples (paciente, profissional, tipo, horário) com
validação de disponibilidade e de conflito. Paciente aqui é **mínimo** — só o suficiente para
selecionar um nome; o prontuário sensível é a Fatia 6.

### Critério de pronto

Dois navegadores abertos no mesmo dia. Um cria um agendamento válido; ele aparece na raia
correta nos dois, sem refresh. Uma tentativa de criar sobre horário fora do expediente é
recusada com erro no campo; uma tentativa de sobrepor outro profissional-horário é recusada
pela constraint mesmo sob corrida. O trace da criação atravessa todas as camadas.

### GAPs que fecha

Estabelece o modelo de autorização e de tenant que o protótipo não tem (ele é clínica única,
ADR-003) e substitui o `checkConflict` em-memória por garantia de banco. O catálogo numerado
fica em [02-regras-e-lacunas.md](02-regras-e-lacunas.md).

### Perguntas de produto que precisam de resposta ANTES

- Quem enxerga a agenda de quem? Um `profissional` vê só a própria agenda ou a da clínica
  inteira? Isso define a policy de leitura.
- "Encaixe" (o `encaixe` de `checkConflict`) permite sobreposição deliberada — qual papel pode
  criar um encaixe?
- O passo da grade (`STEP=30` no protótipo, [`:2533`](../interface/Movimento.dc.html#L2533)) e
  a duração padrão (`DUR=50`) são fixos por clínica ou por tipo de atendimento?

---

## 4. Fatias seguintes, por risco × valor

A ordem abaixo ataca risco cedo e respeita dependências. Cada fatia continua sendo vertical.
Onde uma fatia depende de uma resposta de produto ainda em aberto (tabela em §8 e em
[00-decisoes.md](00-decisoes.md)), isso está marcado como bloqueio.

### Fatia 2 — Ciclo de vida do atendimento (remarcar · concluir · faltar · cancelar)

**Escopo.** As transições de um agendamento já existente, ainda **sem** efeito sobre pacote
(pacote é a Fatia 3). Remarcar por arrasto; marcar concluído; marcar falta; cancelar.

**Por que agora (risco).** Duas coisas de alto risco estreiam aqui. Primeiro, o **relógio
injetável passa a ter consequência de negócio**: os botões Concluir/Faltou só liberam depois
que o atendimento começou, e isso no protótipo depende do `NOW` congelado
([`:2533`](../interface/Movimento.dc.html#L2533)). É a primeira vez que ADR-009 vira regra
observável. Segundo, remarcar é a **corrida de remarcação simultânea** — locking otimista por
`version` no `Appointment`, com `409` e mensagem "fulano moveu este agendamento enquanto você
editava" ([04-arquitetura.md](04-arquitetura.md) §7.3). Ações nomeadas, não CRUD genérico
(`:reschedule`, `:mark_completed`, `:mark_no_show`), conforme [04-arquitetura.md](04-arquitetura.md) §3.

**Critério de pronto.** Concluir/Faltar só habilitam após o início, com tempo injetado e
testável. Dois usuários arrastando o mesmo bloco: o segundo recebe 409 e o estado atual, não
uma sobrescrita silenciosa. Cancelar remove da agenda e emite evento de PubSub.

**GAPs que fecha.** Elimina o `NOW` fixo como fonte de "já começou". Introduz o locking
otimista que o protótipo não tem.

**Perguntas de produto ANTES.** Cancelar tem motivo obrigatório? Cancelamento libera a vaga
para a fila automaticamente (antecipa a Fatia 4)? Remarcação para o passado é permitida (para
corrigir registro) ou proibida?

### Fatia 3 — Pacotes, série de sessões e débito (+ falta punitiva + retomada)

**Escopo.** O pacote como unidade central de uma clínica de fisioterapia: geração da série de
sessões, débito ao concluir/faltar, e retomada após pausa.

**Por que agora (risco × valor).** Valor altíssimo — pacote é como a clínica pensa o serviço —
e risco alto de lógica. Três motores de complexidade real:
- **`computeSerie`** — geração da série
  ([`Movimento.dc.html:1081`](../interface/Movimento.dc.html#L1081) — `computeSerie(d)`),
  o `Movimento.Packages.Series` de [04-arquitetura.md](04-arquitetura.md) §2. Uma série de N
  sessões gera N agendamentos; isso roda fora da transação de request, via Oban
  ([04-arquitetura.md](04-arquitetura.md) §6).
- **Débito com falta punitiva** — "concluído sempre debita; falta debita conforme a *falta
  punitiva* do pacote", verificado no comentário do protótipo em
  [`Movimento.dc.html:1100-1101`](../interface/Movimento.dc.html#L1100). É aqui que a transição
  "faltar" da Fatia 2 ganha efeito econômico.
- **Retomada de pacote** — `pkgResume`
  ([`Movimento.dc.html:561`](../interface/Movimento.dc.html#L561) — `pkgResume(pid,pkgId)`)
  hoje devolve as sessões nas datas originais, já no passado
  ([04-arquitetura.md](04-arquitetura.md) §6). Corrigir isso é reprojetar a série para o
  futuro, com relógio injetado.

**Critério de pronto.** Criar um pacote materializa a série (via job) sem travar o request.
Concluir debita uma sessão; faltar debita ou não conforme a regra punitiva do pacote. Pausar
e retomar reprojeta as sessões restantes para datas futuras, nunca para o passado.

**GAPs que fecha.** O bug de retomada em datas passadas ([`:561`](../interface/Movimento.dc.html#L561)).
A ausência de um débito de sessão consistente e transacional.

**Perguntas de produto ANTES — RESPONDIDAS (2026-07-10).** Pacote **sem validade** (D6); **não
há renovação** ([ADR-011](00-decisoes.md)) — o total de sessões é editável (+/−) a qualquer
momento, sempre no mesmo pacote. Schema de pacote destravado.

### Fatia 4 — Fila de espera + reserva de vaga (hold)

**Escopo.** A fila de espera e a oferta de vaga com reserva atômica.

**Por que agora (risco).** Fecha a **primeira das duas corridas reais** do sistema (ADR-004).
No protótipo, `filaVagas` busca vagas
([`Movimento.dc.html:2531`](../interface/Movimento.dc.html#L2531) — `filaVagas(f)`) e
`offerVaga` apenas pré-preenche um modal
([`Movimento.dc.html:2596`](../interface/Movimento.dc.html#L2596) — `offerVaga(f,slot){ ... openModal ... }`),
sem reservar nada: dois atendentes oferecem o mesmo horário e o segundo colide sem aviso. A
correção é o recurso **`SlotHold`** com TTL de 5 min, exclusion constraint sobre
`(professional_id, intervalo)` filtrada por holds não expirados, `409` imediato com o nome de
quem segurou, e um job Oban varrendo expirados
([04-arquitetura.md](04-arquitetura.md) §7.2 e §6). Depende do motor de disponibilidade da
Fatia 1 (`Movimento.Waitlist.SlotFinder`).

**Critério de pronto.** Dois atendentes tentam oferecer a mesma vaga; um segura, o outro
recebe 409 com o nome do primeiro. Hold abandonado expira e a vaga volta. Tópico
`clinic:<id>:waitlist` propaga holds em tempo real.

**GAPs que fecha.** A ausência total de reserva entre oferecer e confirmar
([04-arquitetura.md](04-arquitetura.md) §7.2, primeira corrida).

**Perguntas de produto ANTES.** Qual o TTL do hold (5 min é chute do desenho)? A fila tem
prioridade (ordem de chegada, urgência clínica)? `fila.obs` contém queixa clínica — e queixa
clínica é dado sensível (ADR-007), então ler/exibir `obs` já exige field policy mesmo antes da
Fatia 6.

### Fatia 5 — Grupo/turma com presença por participante

**Escopo.** Atendimento em turma, com **presença marcada por participante**, não pela turma
inteira de uma vez.

**Por que aqui.** Risco médio, mas **bloqueada por decisão de produto**. O protótipo já modela
turma com `patientIds` num mesmo agendamento (verificado em
[`Movimento.dc.html:1068`](../interface/Movimento.dc.html#L1068)) e rotula "em grupo" na UI
([`:1815`](../interface/Movimento.dc.html#L1815)), mas a presença individual por participante é
uma **correção proposta**, não um fato do protótipo — e [00-decisoes.md](00-decisoes.md) a
lista explicitamente entre as decisões em aberto ("Presença individual em turma (a correção
proposta) confirma-se como requisito?"). Depende da Fatia 3 porque presença por participante
implica débito de sessão por participante.

**Critério de pronto.** Numa turma, cada participante pode ser marcado presente/ausente
independentemente, e o débito de sessão de pacote acontece por participante.

**GAPs que fecha.** A presença coletiva do protótipo vira presença individual (a correção
proposta), fechando o gap listado em [00-decisoes.md](00-decisoes.md).

**Perguntas de produto ANTES (bloqueia schema).** Presença individual em turma confirma-se
como requisito? Se sim, cada participante tem seu próprio registro de presença e de débito, o
que muda o schema de agendamento de turma.

Há um **segundo gap de produto embutido na turma**, e ele bloqueia esta fatia tanto quanto o
primeiro. O protótipo já permite que participantes da mesma turma estejam em **pacotes
diferentes**: cada agendamento de turma carrega um mapa `pkgOf` que liga cada `patientId` ao
seu pacote — `pkgAppts` filtra por `a.pkgOf && Object.values(a.pkgOf).includes(pk.id)`
([`Movimento.dc.html:330`](../interface/Movimento.dc.html#L330)) e o ingresso na turma grava
`pkgOf:{...(g.pkgOf||{}),[d.patientId]:pkId}`
([`Movimento.dc.html:350`](../interface/Movimento.dc.html#L350)). Mas o **ajuste em massa
resolve um único pacote**: `apptPkg` percorre `pkgOf` e **retorna o primeiro** que encontra
(o "dono"), ignorando os demais
([`Movimento.dc.html:1110`](../interface/Movimento.dc.html#L1110) e
[`:1113`](../interface/Movimento.dc.html#L1113) —
`if(pk) return {pk,patient:p,ownerId:pid,pkgId};`), e `massaAffected` monta a lista a alterar
com `this.pkgAppts(info.pk)` — as sessões **daquele** pacote apenas
([`Movimento.dc.html:1145`](../interface/Movimento.dc.html#L1145)). O resultado é que uma
mudança em massa (mudar profissional/horário de "as próximas") afeta o pacote de um
participante e **ignora em silêncio** os pacotes dos outros. Decidir o comportamento correto —
o ajuste em massa deve alcançar todos os pacotes da turma ou só o do agendamento âncora, e como
a UI comunica isso — é pré-requisito desta fatia. A decisão está registrada em §8.

### Fatia 6 — Paciente / ficha (v1) · prontuário completo é v2

> **Revisado por [ADR-013](00-decisoes.md) (2026-07-10).** A v1 **não tem prontuário** — só a
> **ficha do paciente** (dados cadastrais/contato). Todos os papéis visualizam o paciente; o
> profissional é somente-leitura. Tudo que esta seção descreve abaixo (tags clínicas, anexos,
> consentimento versionado, LGPD Art. 11) é **v2**. Três sub-decisões da ficha v1 seguem abertas
> (ADR-013): a ficha inclui médico/CRM/convênio? CPF precisa de cifra + índice cego? `fila.obs`
> é observação operacional ou campo protegido?

**Escopo (v2 — quando o prontuário entrar).** O prontuário de verdade: tags clínicas, anexos
(laudos/exames), encaminhamento médico, consentimento versionado. Substitui o paciente-mínimo
da Fatia 1.

**Por que aqui.** Valor alto, **custo de conformidade alto**, e por isso atrás do **gate de
dado real de paciente** (§6). Esta é a fatia que o ADR-007 governa: no protótipo, diagnóstico
é texto indexável (`patient.tags` com `'hérnia de disco'`, `'gestante'`), anexos são laudos
sem proteção, `medico`/`crm` é encaminhamento, e o consentimento é um booleano solto
(`lgpd:true`, verificado em [`Movimento.dc.html:109`](../interface/Movimento.dc.html#L109); a
seção de consentimento existe como aba em [`:2035`](../interface/Movimento.dc.html#L2035)).
Nada disso pode ir a produção sem: `AshCloak` nos campos catalogados, `AshPaperTrail` sobre
acesso e mutação, `field_policies` por papel, anexos em object storage privado com URL
assinada de vida curta, consentimento versionado com finalidade e revogação, e política de
retenção (ADR-007, seis pontos).

**Critério de pronto.** Todos os campos sensíveis catalogados criptografados; toda leitura e
mutação de prontuário auditada; anexos só acessíveis por URL assinada de curta duração;
consentimento com data, finalidade e trilha de revogação. O gate §6 está satisfeito.

**GAPs que fecha.** Consentimento como booleano solto → consentimento versionado. Anexos sem
proteção → object storage privado. Diagnóstico como texto livre indexável → campo sensível
com field policy.

**Perguntas de produto ANTES.** Quais papéis leem quais campos do prontuário? Qual a política
de retenção por tipo de dado? Como se dá a exportação/eliminação a pedido do titular (o job de
purga LGPD de [04-arquitetura.md](04-arquitetura.md) §6)?

### Fatia 7 — Profissionais e horários editáveis + `futureConflicts`

**Escopo.** Tornar **editáveis** as camadas de disponibilidade que a Fatia 1 apenas leu do
seed: horário do profissional e suas exceções.

**Por que aqui.** Risco médio-alto por causa de um motor sutil. Mudar o horário de um
profissional pode invalidar agendamentos futuros já marcados — é o `futureConflicts`
([`Movimento.dc.html:864`](../interface/Movimento.dc.html#L864) —
`futureConflicts(afterFn,filterFn)`), o `Movimento.Scheduling.ImpactAnalysis` de
[04-arquitetura.md](04-arquitetura.md) §2. A tela precisa mostrar o impacto retroativo antes
de confirmar a mudança. É a contraparte de escrita da Fatia 1: lá lemos a disponibilidade,
aqui a editamos com análise de impacto.

**Critério de pronto.** Alterar o horário de um profissional exibe os agendamentos futuros
que passariam a conflitar, e exige uma decisão explícita sobre eles antes de salvar.

**GAPs que fecha.** A edição de horário sem análise de impacto.

**Perguntas de produto ANTES.** Ao mudar o horário, os agendamentos futuros conflitantes são
bloqueados, remarcados ou apenas sinalizados? **Atenção de escopo:** o formulário de
profissional do protótipo já coleta chave PIX e uma string livre de remuneração
("Ex.: 60/40 por sessão", verificado em
[`Movimento.dc.html:3140`](../interface/Movimento.dc.html#L3140)) que **ninguém lê**. Esses
campos são v2 (§5) — nesta fatia ou não os coletamos, ou os coletamos e explicitamente não os
usamos, mas nunca implementamos repasse por palpite.

### Fatia 8 — Configuração da clínica

**Escopo.** Tornar editáveis o horário da clínica, os feriados, o timezone canônico (ADR-009)
e os tipos de atendimento — as camadas de topo da precedência do `dayPeriods` que, até aqui,
vieram do seed.

**Por que aqui.** Risco menor que as anteriores porque a lógica dura (a precedência de 4
camadas) já foi construída e testada na Fatia 1; esta fatia só dá superfície de edição a ela.
Fica atrás das fatias operacionais porque a clínica consegue operar com config seeded, mas não
consegue operar sem agenda, transições e pacotes.

**Critério de pronto.** Alterar horário da clínica, feriados e timezone reflete corretamente
na disponibilidade calculada, e uma mudança de horário da clínica também dispara a análise de
impacto da Fatia 7.

**Perguntas de produto ANTES.** O timezone é por clínica (ADR-009 diz que sim) — pode mudar
depois de existirem agendamentos? Feriado é bloqueio absoluto ou permite exceção por
profissional (isso é a precedência de camadas do `dayPeriods`)?

### Fatia 9 — Relatórios

**Escopo.** Ocupação, sessões consumidas, faltas — os agregados que a recepção e a gestão
leem. A tela existe no protótipo (`renderRelatorios` em
[`Movimento.dc.html:1316`](../interface/Movimento.dc.html#L1316)).

**Por que aqui.** Baixo risco técnico, e depende de que as fatias anteriores já estejam
produzindo os dados que ele agrega. Usa agregados/calculations empurrados para o SQL (ADR-002)
e um snapshot noturno via Oban para não varrer a tabela de agendamentos ao vivo
([04-arquitetura.md](04-arquitetura.md) §6).

**Critério de pronto.** Os números batem com a agenda real de um período; o relatório lê do
snapshot, não faz varredura ao vivo.

**Perguntas de produto ANTES.** Quais métricas importam de fato (ocupação por profissional?
sessões consumidas por pacote? taxa de falta?) e em que granularidade de tempo.

### Fatia 10 — Membros e convite

**Escopo.** O fluxo de administração de equipe: convidar um novo membro, aceitar convite,
atribuir papel (`admin`/`profissional`/`membro`). A tela de membro existe no protótipo
(`modalMembro` em [`Movimento.dc.html:1926`](../interface/Movimento.dc.html#L1926)).

**Por que por último.** O **mecanismo** de RBAC já existe desde a Fatia 1 (é o
`Ash.Policy.Authorizer` que toda fatia usa); o que falta é só a **UI de autoatendimento** para
convidar e gerenciar papéis. Enquanto isso, a equipe pode ser seedada. Baixo risco, e nenhuma
outra fatia depende dele — por isso vai para o fim sem prejudicar o programa.

**Critério de pronto.** Um `owner`/`admin` convida alguém por **magic link**; o convidado aceita
(magic link/Google), recebe papel, e o papel é imediatamente respeitado pelas policies de todas
as fatias. O usuário com mais de um `Membership` **troca de clínica** e o escopo muda com ele.

**Perguntas de produto — RESOLVIDAS (2026-07-11).** Profissional multi-clínica: **SIM** (modelo
Vercel, [ADR-014](00-decisoes.md)). Login: **Google + Magic Link, sem senha** ([ADR-015](00-decisoes.md));
o convite/magic link expira (ex.: 72 h). Quem convida: **`owner` e `admin`** ([ADR-016](00-decisoes.md));
gestão de owners e "≥1 owner por tenant" são exclusivas de `owner`.

---

## 5. Explicitamente FORA da v1

Cortar escopo é uma decisão de projeto, não um esquecimento. Fica de fora da v1, com motivo:

- **Faturamento, guias de convênio, nota fiscal.** Listado como v2 em
  [00-decisoes.md](00-decisoes.md). É um subdomínio inteiro (preço por convênio/particular/
  reembolso, guia, glosa) que não é pré-requisito para operar a agenda e os pacotes. Puxá-lo
  para a v1 dobraria a superfície de risco.

- **Repasse ao profissional.** Depende de faturamento e de uma regra de remuneração que hoje
  nem sequer é estruturada: o formulário de profissional coleta banco, PIX e uma **string
  livre** de remuneração que ninguém lê ([`Movimento.dc.html:3140`](../interface/Movimento.dc.html#L3140),
  verificado; também citado em [04-arquitetura.md](04-arquitetura.md) §8). Coletar um dado não
  é implementá-lo. Repasse é v2.

- **Salas e equipamentos como recurso com capacidade.** Hoje o conflito é só por profissional
  (`checkConflict`, [`:834`](../interface/Movimento.dc.html#L834)). Se sala virar recurso, a
  exclusion constraint deixa de ser "por profissional" e vira "por recurso" — é a mudança de
  schema mais cara da lista ([04-arquitetura.md](04-arquitetura.md) §8). Não fazer por palpite.

- **Multi-unidade *dentro* de um mesmo tenant.** Diferente de multi-clínica (que é v1: cada
  unidade é um tenant **isolado**, [ADR-014](00-decisoes.md)): aqui seria a mesma pessoa jurídica
  com filiais **compartilhando** pacientes/equipe sob um único schema. v2.
- **Visão consolidada cross-tenant.** Um `owner` com várias unidades vê/opera **uma de cada vez**
  (troca de tenant estilo Vercel). Relatório/faturamento agregando várias unidades atravessaria
  schemas ([ADR-014](00-decisoes.md)) — v2.

Nada disso significa "nunca". Significa que a v1 entrega uma clínica que agenda, atende,
debita pacote, gerencia fila e prontuário com conformidade — e para por aí, de propósito.

---

## 6. Marcos e portões (gates)

Os marcos do programa são os critérios de pronto das fatias. Sobre eles há **portões
obrigatórios** que não podem ser atravessados por conveniência.

### Gate G0 — Pipeline provado

Não se começa a Fatia 1 antes da Fatia 0 estar pronta pelo seu critério: deploy real com
trace ponta-a-ponta. Escrever regra de negócio sobre um pipeline não-provado é acumular risco
escondido — exatamente o que a fatia vertical existe para evitar.

### Gate G1 — Antes de tocar em dado real de paciente (obrigatório)

**Nenhum dado real de paciente entra no sistema antes que todos os pré-requisitos abaixo
estejam satisfeitos.** Até lá, todo ambiente roda com o seed sintético derivado do protótipo
(PRNG determinístico, `Movimento.dc.html:43-263`), que é realista e legalmente inerte
([04-arquitetura.md](04-arquitetura.md) §12). A lista deriva do ADR-007 e do ADR-008; o
detalhamento operacional **já está escrito** e reparte-se por assunto. Os pré-requisitos de
proteção do dado do paciente — criptografia de campo, trilha de auditoria, consentimento
versionado, field policies e retenção/purga — pertencem a
[06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md), que é o documento que governa a LGPD Art. 11
deste gate; a verificação de região/réplicas do Postgres e a telemetria de produção que também
condicionam o gate ficam em
[05-observabilidade-e-producao.md](05-observabilidade-e-producao.md).

> **Revisado por [ADR-013](00-decisoes.md) (2026-07-10).** Como a **v1 não tem prontuário** (só a
> ficha do paciente), o peso deste gate cai na v1: sem tags clínicas, anexos e consentimento
> versionado, os pré-requisitos **1–6** (que protegem dado clínico Art. 11) **não bloqueiam as
> fatias da v1** — voltam integralmente na **v2**, quando o prontuário entrar. Ressalva: a ficha
> v1 ainda pode conter dado sensível (CPF, médico/CRM, `fila.obs`), e o que disso exige proteção
> na v1 depende das três sub-decisões abertas do ADR-013. O item **7** (região/réplicas do
> Postgres) e a telemetria seguem valendo para **qualquer** dado real de paciente, inclusive a ficha.

Pré-requisitos (todos do ADR-007, salvo indicação):
1. Criptografia de campo (`AshCloak`) ativa nos campos sensíveis catalogados.
2. Trilha de auditoria (`AshPaperTrail`) sobre acesso e mutação de prontuário.
3. `field_policies` restringindo leitura de campo sensível por papel.
4. Anexos em object storage privado com URL assinada de vida curta — nunca URL persistida como
   no protótipo.
5. Consentimento versionado e datado, com finalidade e revogação — não o booleano solto atual.
6. Política de retenção e rotina de exportação/eliminação a pedido do titular (job de purga
   LGPD, [04-arquitetura.md](04-arquitetura.md) §6).
7. **Região e réplicas do Postgres verificadas** (ADR-008): dado de saúde de titulares
   brasileiros exige confirmar `gru` e a localização de qualquer réplica **antes** do primeiro
   dado real. Staging nunca recebe cópia de produção ([04-arquitetura.md](04-arquitetura.md) §12).

Este gate é a razão pela qual a Fatia 6 (prontuário) fica atrás das fatias operacionais: elas
rodam inteiras sobre seed sintético e não precisam esperar o gate; o prontuário precisa.

---

## 7. Riscos do programa e mitigação

| Risco | Por que dói | Mitigação |
|---|---|---|
| **Port React → Svelte 5 não é mecânico, e as regras estão emaranhadas com a renderização** (o maior) | O protótipo é uma classe única de 3.501 linhas onde `this.state` é objeto plano mesclado por `setState` com updaters imutáveis (`map`/`filter`/spread), enquanto runes mutam proxies `$state` direto (ADR-006). Pior: motores de regra como `filaVagas` e `layoutAppts` estão entrelaçados com JSX e milhares de estilos inline computados de `theme()`. Portar por transcrição literal carrega os bugs junto. | Separar regra de renderização por construção: os motores `dayPeriods`, `futureConflicts`, `filaVagas`→`SlotFinder` e `computeSerie` migram para **domínio puro no servidor** ([04-arquitetura.md](04-arquitetura.md) §2), testados isoladamente contra o comportamento do protótipo. Só `layoutAppts` fica no cliente, como função pura isolada da UI. Onde houver espelho de validação no front, ele compartilha a função pura por contrato de teste, nunca por cópia ([04-arquitetura.md](04-arquitetura.md) §2). |
| **Concorrência subestimada** | Duas corridas reais (oferta de vaga sem hold; remarcação simultânea) só aparecem com >1 usuário e passam despercebidas em teste single-user. | Atacar cedo: locking otimista na Fatia 2, hold com exclusion constraint na Fatia 4. Garantia final sempre no banco (constraint), não em validação de aplicação ([04-arquitetura.md](04-arquitetura.md) §7). |
| **Tempo congelado vazando para produção** | O congelamento não está em "~dez" pontos: por `grep -o` no protótipo, `hoje()` aparece **22 vezes** (1 definição em [`:1098`](../interface/Movimento.dc.html#L1098) e 21 chamadas), a constante `NOW` **7 vezes** (2 definições — [`:130`](../interface/Movimento.dc.html#L130), `const NOW=702; // 11:42`, e [`:2533`](../interface/Movimento.dc.html#L2533) — e 5 usos) e o literal `702` **8 vezes**. Todos contaminam regra que depende de passado/futuro (ADR-009); portá-los por transcrição literal quebraria cada uma. | Relógio injetável desde a Fatia 0; nenhuma regra lê o relógio do sistema. Testes usam tempo determinístico de propósito. |
| **Regra de produto ainda em aberto travando schema** | Validade de pacote, presença em turma, "renovar", salas — cada resposta muda schema (tabela §8). Adivinhar hoje custa migração de dado sensível depois. | Cada fatia lista as perguntas que precisam de resposta ANTES de começar. Fatia não inicia sem elas. |
| **Segurança tratada como fase, não como critério** | A tentação de "colocar LGPD depois" é como o protótipo ficou sem proteção nenhuma. | Gate G1 obrigatório; segurança é critério de aceitação da fatia que toca prontuário (ADR-007), não um marco separado. |
| **Contrato de erro sem campo** | Erros do Ash que não pertencem a um campo (conflito de agenda, turma cheia) não aparecem no formulário — armadilha descrita em [.claude/rules/ash_phoenix.md](../.claude/rules/ash_phoenix.md) e em [04-arquitetura.md](04-arquitetura.md) §3. | Canal de erro global no front desde a Fatia 1, além dos erros por campo. |

---

## 8. Decisão de produto → o que bloqueia → quando precisamos dela

As linhas puxam as decisões em aberto verificadas na seção final de
[00-decisoes.md](00-decisoes.md) e as perguntas que cada fatia levantou acima. "Quando" é
expresso em fatia, não em data.

| Decisão de produto (aberta) | O que ela bloqueia | Quando precisamos (fatia) |
|---|---|---|
| Pacote tem validade? Renovar? | ✅ **Resolvido:** sem validade (D6); **sem renovação**, total editável (+/−) a qualquer momento ([ADR-011](00-decisoes.md)) | — |
| Cancelamento libera a vaga para a fila automaticamente? | ✅ **Resolvido:** motivo opcional + libera automático (D4) | — |
| TTL e prioridade da fila de espera | ✅ **Resolvido:** TTL 10 min; prioridade + ordem de chegada (D8/D9) | — |
| Presença individual em turma confirma-se como requisito? | ✅ **Resolvido:** sim, por participante (D10) | — |
| Turma multi-pacote: ajuste em massa afeta todos ou só o âncora? | ✅ **Resolvido:** **não existe "pacote de turma"** — ajuste sempre por (paciente, pacote) (D11) | — |
| Quais papéis leem quais campos do prontuário? Retenção? | ⚠️ **Revisado ([ADR-013](00-decisoes.md)):** v1 não tem prontuário, só ficha (todos veem, profissional só lê). Sub-decisões da ficha abertas: médico/CRM, cifra do CPF, `fila.obs` | Antes da ficha / Fatia 4 |
| Ao mudar horário, futuros conflitantes bloqueados/remarcados/sinalizados? | ✅ **Resolvido:** bloqueiam a mudança (D12 — já é o do protótipo) | — |
| Timezone muda após agendamentos? Feriado admite exceção por profissional? | ✅ **Resolvido:** timezone só Brasília, imutável (D13); feriado = bloqueio absoluto (D14) | — |
| Um profissional pode existir em mais de uma clínica? | ✅ **Resolvido (revisado 2026-07-11):** **SIM na v1** — identidade global multi-tenant estilo Vercel ([ADR-014](00-decisoes.md), reverte ADR-012) | — |
| Estratégia de login? Papéis? Owner? | ✅ **Resolvido:** Google + Magic Link, sem senha ([ADR-015](00-decisoes.md)); papéis `owner·admin·profissional·recepcao`, ≥1 owner/tenant ([ADR-016](00-decisoes.md)) | — |
| Salas/equipamentos como recurso com capacidade | Forma da exclusion constraint (por profissional → por recurso); é a mudança de schema mais cara | v2 — **não** decidir por palpite na v1 |
| Preço por convênio/particular/reembolso; há repasse ao profissional? | Subdomínio de faturamento e repasse; os campos banco/PIX/remuneração ([`:3140`](../interface/Movimento.dc.html#L3140)) hoje coletados e não lidos | v2 |
| Multi-unidade dentro da mesma clínica | Modelo de filial (horários/salas por unidade) | v2 |

---

## 9. Catálogo provisório de GAPs (para o 02)

O documento [02-regras-e-lacunas.md](02-regras-e-lacunas.md) — o catálogo formal de regras e
lacunas — **ainda não existe** (verificado nesta revisão). Enquanto ele não é escrito, esta
tabela fixa a numeração de GAPs que o restante deste roadmap pressupõe, cada um ancorado em
evidência verificada do protótipo. **Esta é a numeração que o 02 deve adotar**; onde o 02
divergir, é o 02 que se alinha a esta lista, porque foi instruído a lê-la primeiro. Cada GAP é
fechado pela fatia indicada (§3 e §4). "Evidência" cita linhas conferidas com `sed`/`grep`.

| GAP | Protótipo (o que existe hoje) → produção (o que a fatia estabelece) | Evidência | Fatia que fecha |
|---|---|---|---|
| **GAP-01** | Clínica única, login mock, sem tenant nem autorização → **identidade global multi-tenant** (`User`↔N `Membership`, troca de tenant), Google+Magic Link, RBAC via policy (`owner·admin·profissional·recepcao`) | ADR-003/014/015/016; papéis em [`:203`](../interface/Movimento.dc.html#L203) | Fatia 1 |
| **GAP-02** | `checkConflict` roda em memória sobre lista local → exclusion constraint no Postgres (garantia final de não-sobreposição por profissional) | [`:834`](../interface/Movimento.dc.html#L834); [04 §7.1](04-arquitetura.md) | Fatia 1 |
| **GAP-03** | Relógio congelado: `hoje()`='2026-06-25', `NOW=702` → relógio injetável, timezone por clínica | [`:1098`](../interface/Movimento.dc.html#L1098), [`:130`](../interface/Movimento.dc.html#L130), [`:2533`](../interface/Movimento.dc.html#L2533); ADR-009 | Fatia 0 (padrão) · Fatia 2 (consequência) |
| **GAP-04** | Remarcação sem controle de concorrência → locking otimista por `version`, `409` no perdedor | [04 §7.3](04-arquitetura.md) | Fatia 2 |
| **GAP-05** | Débito de sessão sem transação consistente → concluir/faltar debita conforme falta punitiva, transacionalmente | `wouldConsume` [`:1104`](../interface/Movimento.dc.html#L1104); comentário [`:1100`](../interface/Movimento.dc.html#L1100) | Fatia 3 |
| **GAP-06** | `pkgResume` devolve sessões em datas **passadas** → reprojeção da série para o futuro | [`:561`](../interface/Movimento.dc.html#L561) | Fatia 3 |
| **GAP-07** | Oferta de vaga (`offerVaga`) só abre modal, sem reservar nada → `SlotHold` com TTL + exclusion constraint + `409` | [`:2596`](../interface/Movimento.dc.html#L2596); [04 §7.2](04-arquitetura.md) | Fatia 4 |
| **GAP-08** | Presença é coletiva por turma → presença individual por participante (correção proposta) | `patientIds` num só agendamento [`:1068`](../interface/Movimento.dc.html#L1068); [00-decisoes.md](00-decisoes.md) | Fatia 5 |
| **GAP-09** | Turma multi-pacote: `pkgOf` liga cada participante a pacotes distintos, mas ajuste em massa afeta **um só** e ignora os demais em silêncio → decisão de escopo + schema explícito | `pkgOf` [`:330`](../interface/Movimento.dc.html#L330)/[`:350`](../interface/Movimento.dc.html#L350); `apptPkg` [`:1110`](../interface/Movimento.dc.html#L1110); `massaAffected` [`:1145`](../interface/Movimento.dc.html#L1145) | Fatia 5 (bloqueio de produto, §8) |
| **GAP-10** | Consentimento é booleano solto (`lgpd:true`) → consentimento versionado, datado, com finalidade e revogação | [`:109`](../interface/Movimento.dc.html#L109); ADR-007 | Fatia 6 (Gate G1) |
| **GAP-11** | Anexos sem proteção → object storage privado com URL assinada de vida curta | ADR-007 | Fatia 6 (Gate G1) |
| **GAP-12** | Diagnóstico como texto livre indexável (`patient.tags`) → campo sensível criptografado com field policy | ADR-007; aba de consentimento [`:2035`](../interface/Movimento.dc.html#L2035) | Fatia 6 (Gate G1) |
| **GAP-13** | Edição de horário do profissional sem análise de impacto → `futureConflicts` mostra conflitos retroativos antes de salvar | [`:864`](../interface/Movimento.dc.html#L864); [04 §2](04-arquitetura.md) | Fatia 7 |
| **GAP-14** | Camadas de topo da precedência do `dayPeriods` (horário da clínica, feriado, tipo) só vêm do seed → superfície de edição | [`:854`](../interface/Movimento.dc.html#L854) | Fatia 8 |

Os campos banco/PIX/**string livre de remuneração** ([`:3140`](../interface/Movimento.dc.html#L3140))
não recebem GAP de v1: são escopo v2 (§5), coletados e não lidos, e não devem virar repasse por
palpite. Salas/equipamentos como recurso e multi-unidade idem — estão na tabela de §8 como v2.

---

## Resumo em uma frase

Começamos pelo **andaime** (provar o pipeline até produção com telemetria, sem regra de
negócio), depois pela **agenda do dia em leitura + criação**, porque ela concentra o maior
risco técnico do sistema — tenancy, RBAC, disponibilidade, conflito, raias e o primeiro evento
de tempo real — e risco se ataca cedo. Tudo em fatias verticais, com um portão intransponível
antes do primeiro dado real de paciente.

---

## Correções desta revisão

Esta revisão corrigiu defeitos de proveniência e de referência, sem alterar a estratégia (as
fatias verticais, a Fatia 0 de andaime e os gates permanecem).

1. **Link quebrado e referência de segurança repartida (Gate G1).** A referência apontava para
   `05-observabilidade-seguranca-producao.md`, arquivo que não existe. O documento real é
   [05-observabilidade-e-producao.md](05-observabilidade-e-producao.md), e a parte de segurança
   virou um documento separado, [06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md). A referência
   do gate foi repartida por assunto: os pré-requisitos de proteção do dado do paciente
   (criptografia, auditoria, consentimento, field policies, retenção) apontam para o **06**, que
   governa a LGPD Art. 11; a verificação de região/réplicas e a telemetria de produção, para o
   **05**.

2. **Claim temporal desatualizado.** O texto tratava 05 e 06 como "ainda não escritos". Ambos
   **já existem** (verificado com `ls docs/`); a nota de proveniência e o Gate G1 foram
   reescritos para referenciá-los como fontes reais.

3. **Estimativa "~dez lugares" substituída por contagem.** O congelamento de tempo foi contado
   com `grep -o` no protótipo: `hoje()` aparece 22 vezes (1 definição em [`:1098`](../interface/Movimento.dc.html#L1098)
   e 21 chamadas), a constante `NOW` 7 vezes (2 definições em [`:130`](../interface/Movimento.dc.html#L130)
   e [`:2533`](../interface/Movimento.dc.html#L2533), 5 usos) e o literal `702` 8 vezes. A
   quantificação vaga saiu da tabela de riscos (§7).

4. **Referências de seção ao 04 corrigidas.** As citações de concorrência apontavam para "§5"
   (que é **Autenticação** na numeração atual de [04-arquitetura.md](04-arquitetura.md)). A
   concorrência é a **§7**: exclusion constraint → §7.1, `SlotHold`/hold → §7.2, locking otimista
   → §7.3. Também as duas citações a "§7" que na verdade descreviam seed sintético e "staging
   nunca recebe cópia de produção" foram corrigidas para **§12 (Ambientes)**, onde esse conteúdo
   de fato mora ([04 §12](04-arquitetura.md), linhas de ambientes verificadas).

5. **Documentos 01/02/03 confirmados como inexistentes.** `ls docs/` confirma que
   [01-dominio-ash.md](01-dominio-ash.md), [02-regras-e-lacunas.md](02-regras-e-lacunas.md) e
   [03-frontend-sveltekit.md](03-frontend-sveltekit.md) ainda não foram escritos. As referências
   a eles permanecem como destinos futuros, explicitamente marcados na nota de proveniência. O
   único link de arquivo quebrado era o do item 1; os demais links de arquivo foram conferidos
   (`grep` sobre os alvos): 00, 04, 05 e 06 existem e resolvem.

6. **Catálogo provisório de GAPs (novo §9).** Como o 02 ainda não existe e foi instruído a
   adotar a numeração deste roadmap, esta revisão materializou a lista de GAPs que o documento
   pressupunha em prosa numa tabela numerada (**GAP-01 … GAP-14**), cada um com evidência
   verificada e a fatia que o fecha. É a numeração que o 02 deve honrar.

7. **Novo GAP-09 — turma multi-pacote.** Acrescentado ao escopo, à Fatia 5 e à tabela de decisão
   de produto (§8). O protótipo permite que participantes da mesma turma estejam em pacotes
   diferentes (`pkgOf`, [`:330`](../interface/Movimento.dc.html#L330)/[`:350`](../interface/Movimento.dc.html#L350)),
   mas um ajuste em massa resolve **um só** pacote — `apptPkg` retorna apenas o do dono
   ([`:1110`](../interface/Movimento.dc.html#L1110)) e `massaAffected` filtra por
   `pkgAppts(info.pk)` ([`:1145`](../interface/Movimento.dc.html#L1145)) — ignorando os demais
   participantes em silêncio. É decisão de produto que precisa ser tomada **antes** da fatia de
   grupo/turma.
