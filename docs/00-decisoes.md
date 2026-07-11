# Decisões de Arquitetura (ADR)

Registro das decisões travadas para levar o Movimento do protótipo (`interface/Movimento.dc.html`) até produção.
Cada decisão tem contexto, alternativas descartadas e consequências. **Uma decisão só muda por um novo ADR.**

Status possíveis: `Aceita` · `Proposta` · `Substituída por ADR-nn`

---

## ADR-001 — O protótipo é a especificação de origem

**Status:** Aceita

**Contexto.** `interface/Movimento.dc.html` são 3.501 linhas numa única classe React (`class Component extends DCLogic`), servida por um runtime próprio (`interface/support.js`). Não é um mock: contém quatro motores de regra reais — resolução de disponibilidade por precedência (`dayPeriods`), detecção de impacto retroativo em mudanças de horário (`futureConflicts`), busca de vagas na fila de espera (`filaVagas`) e coloração de grafo de intervalos para o layout da agenda (`layoutAppts`).

**Decisão.** O protótipo é tratado como **especificação executável e fonte de proveniência**. Toda regra de negócio implementada em produção cita a linha de origem no protótipo. Divergências deliberadas são registradas como `GAP-nn` em [02-regras-e-lacunas.md](02-regras-e-lacunas.md).

**Consequências.** O protótipo é congelado como referência: não recebe features novas. Os 79 screenshots em `interface/screenshots/` viram baseline visual de QA.

---

## ADR-002 — Backend em Elixir + Ash, exposto como API REST

**Status:** Aceita

**Contexto.** O produto é um sistema de gestão de clínica com dado de saúde (LGPD Art. 11), papéis de acesso, agenda colaborativa e agregados pesados (ocupação, faturamento, sessões consumidas). O frontend será SvelteKit, então o backend precisa ser um serviço separado com contrato explícito.

**Decisão.** Elixir + **Ash Framework 3.x** + **AshPostgres**, hospedado num app Phoenix, expondo **AshJsonApi** (JSON:API sobre REST). Phoenix serve também os Channels de tempo real (ADR-004).

**Alternativas descartadas.**

| Alternativa | Por que não |
|---|---|
| SvelteKit fullstack (Node + Drizzle/Prisma) | Um runtime só e deploy mais simples, mas exigiria reimplementar à mão RBAC, criptografia de campo, auditoria e agregados — exatamente as quatro coisas que este domínio mais precisa e que o Ash entrega declarativamente. |
| Phoenix LiveView | Elimina o frontend separado, mas o usuário quer SvelteKit e o protótipo tem interações (drag-and-drop com ghost, pan, layout de raias) que são mais naturais em cliente rico. |
| AshGraphql em vez de AshJsonApi | Melhor para queries de shape variável, mas adiciona codegen e camada de cache no front. O conjunto de telas é fechado e conhecido; REST com `include` do JSON:API basta. **Reavaliar** se a agenda exigir loads aninhados profundos. |

**Consequências.** Ganhamos de graça: `Ash.Policy.Authorizer` para RBAC, `field_policies` para dado sensível, `AshCloak` para criptografia de campo, `AshPaperTrail` para auditoria, e agregados/calculations empurrados para o SQL. Pagamos: dois runtimes, dois deploys, e um contrato de API para manter.

---

## ADR-003 — SaaS multi-clínica desde o primeiro commit

**Status:** Aceita

**Contexto.** O protótipo assume clínica única: `hours`, `holidays` e `settings` são singletons globais no estado. A sidebar, porém, já cita "Centro" como unidade.

**Decisão.** Toda entidade nasce escopada a uma **clínica (tenant)**. A estratégia concreta de multitenancy do AshPostgres (`strategy :context` com schema-por-tenant vs. `strategy :attribute` com `clinic_id`) está detalhada e recomendada em [01-dominio-ash.md](01-dominio-ash.md).

**Justificativa.** Adicionar tenancy depois de existirem dados de saúde em produção é caro e arriscado: exige migração de dados sensíveis, reescrita de todas as policies e revisão de todo índice. Fazer agora custa pouco.

**Consequências.** Toda leitura e escrita passa a exigir tenant no escopo. Um profissional pode existir em mais de uma clínica — isso é uma regra nova, sem precedente no protótipo, e está especificada em [02-regras-e-lacunas.md](02-regras-e-lacunas.md), Parte 3.

---

## ADR-004 — Agenda colaborativa em tempo real via Phoenix Channels

**Status:** Aceita

**Contexto.** O caso normal de uma recepção de clínica são duas ou mais pessoas na mesma agenda ao mesmo tempo. O protótipo não trata disso, e a consequência é concreta: em `filaVagas` → `offerVaga` → `createAppt` não existe reserva entre oferecer uma vaga e confirmá-la, então dois atendentes podem oferecer o mesmo horário ao mesmo tempo.

**Decisão.** Phoenix Channels sobre WebSocket, com `Phoenix.PubSub` alimentado por notificações do Ash. O cliente Svelte usa o pacote npm `phoenix` diretamente, sem passar pelo BFF.

**Consequências.** Precisamos definir granularidade de tópico, reserva de vaga com TTL e locking otimista em remarcação. Está tudo em [02-regras-e-lacunas.md](02-regras-e-lacunas.md), Parte 3, e a arquitetura em [04-arquitetura.md](04-arquitetura.md).

---

## ADR-005 — SvelteKit como BFF, nunca como cliente de banco

**Status:** Aceita

**Contexto.** SvelteKit tem servidor próprio (`+page.server.ts`, form actions). A tentação é ele falar com o Postgres direto.

**Decisão.** SvelteKit roda com `adapter-node` e atua como **Backend-for-Frontend**: seus `load` e `actions` chamam a API do Phoenix, portando o cookie de sessão. **Não existe conexão de banco no serviço web.** A única exceção ao caminho BFF é o WebSocket dos Channels, que o browser abre direto contra o Phoenix.

**Consequências.** Um único lugar aplica as policies do Ash. O BFF pode compor e cachear respostas, e o browser nunca vê um token de API de longa duração. Custo: um salto de rede a mais no SSR — mitigado por colocar os dois serviços na mesma região.

---

## ADR-006 — Frontend em Svelte 5 (runes) + TypeScript

**Status:** Aceita

**Decisão.** SvelteKit 2.x, Svelte 5 com runes, TypeScript estrito, `adapter-node`. Testes e componentes em [03-frontend-sveltekit.md](03-frontend-sveltekit.md); **a estratégia de CSS foi substituída pelo [ADR-010](#adr-010--css-utilitário-com-tailwind-v4)**.

**Consequência principal.** O port de React para Svelte 5 não é mecânico. `this.state` é um objeto plano mesclado por `setState`, e todos os updaters usam `map`/`filter`/spread imutável; em runes você muta proxies `$state` diretamente. Além disso o protótipo tem 1.205 objetos de estilo inline computados a partir de `theme()` e nenhuma classe, que precisam ser reescritos — para utilitários Tailwind sobre uma camada de custom properties, na forma do [ADR-010](#adr-010--css-utilitário-com-tailwind-v4). Os riscos estão catalogados em [03-frontend-sveltekit.md](03-frontend-sveltekit.md), seção 9.

---

## ADR-007 — Dado de saúde é tratado como categoria especial da LGPD

**Status:** Aceita

**Contexto.** O protótipo guarda, sem nenhuma proteção especial: diagnósticos como texto indexável (`patient.tags` contém `'hérnia de disco'`, `'pós-op joelho'`, `'gestante'`), anexos que são laudos e exames (`anexos[patientId]`), queixa clínica na fila (`fila.obs`), encaminhamento médico (`medico`, `crm`) e dados bancários do profissional (`banco`, `agencia`, `conta`, `pix`).

**Decisão.** Estes campos são **dado pessoal sensível (LGPD, Art. 11)**. Consequências arquiteturais, todas obrigatórias para a v1:

1. Criptografia em nível de campo (`AshCloak`) para os campos catalogados em [01-dominio-ash.md](01-dominio-ash.md), seção 6.
2. Trilha de auditoria (`AshPaperTrail`) sobre acesso e mutação de prontuário.
3. `field_policies` do Ash restringindo leitura por papel.
4. Anexos em object storage privado com URL assinada de vida curta — nunca `URL.createObjectURL` persistido, como hoje.
5. Consentimento versionado e datado, com finalidade e revogação. Hoje é um booleano solto (`patient.lgpd`).
6. Política de retenção e rotina de exportação/eliminação a pedido do titular.

**Consequência.** Segurança não é uma fase do roadmap; é um critério de aceitação de cada fatia que toca prontuário.

---

## ADR-008 — Deploy em Fly.io, observabilidade via OpenTelemetry sem vendor lock

**Status:** Aceita

**Decisão.** Dois apps Fly (`movimento-api` em Elixir, `movimento-web` em Node), Postgres gerenciado, object storage compatível com S3 (Tigris ou Cloudflare R2). Instrumentação com **OpenTelemetry puro**; o backend de telemetria (Grafana Cloud, Honeycomb) é configuração, não código.

**Justificativa.** Clustering BEAM entre nós Fly deixa o `Phoenix.PubSub` distribuído praticamente de graça, o que o ADR-004 exige. OTel sem SDK proprietário mantém a porta aberta caso um requisito de jurisdição force VPS própria.

**Consequências e alertas.** Dado de saúde de titulares brasileiros: verificar a região do Fly (`gru`, São Paulo) e a localização das réplicas do Postgres antes de qualquer dado real. Detalhes em [05-observabilidade-e-producao.md](05-observabilidade-e-producao.md) e [06-seguranca-e-lgpd.md](06-seguranca-e-lgpd.md).

---

## ADR-009 — Relógio injetável, timezone por clínica

**Status:** Aceita

**Contexto.** O protótipo congela o tempo: `hoje()` retorna a string literal `'2026-06-25'` e o "agora" é a constante `NOW = 702` (11:42). Isso aparece em cerca de dez lugares e contamina toda regra que depende de passado ou futuro — liberar os botões Concluir/Faltou, debitar sessão, expirar regra de fila, calcular vagas.

**Decisão.** Nenhum módulo de domínio lê o relógio do sistema diretamente. O tempo entra como dependência (no Ash, via `Ash.Scope`/contexto da ação). Cada clínica tem um **timezone canônico** persistido; "hoje" e "já começou" são resolvidos nesse fuso, não em UTC nem no fuso do servidor.

**Consequências.** Regras de negócio ficam testáveis com tempo determinístico. Datas viajam pela API como ISO-8601 com offset explícito. O front nunca deriva "hoje" do relógio do browser para decisão de negócio — só para exibição.

---

## ADR-010 — CSS utilitário com Tailwind v4

**Status:** Aceita

**Substitui:** a recomendação de [03-frontend-sveltekit.md §1.1](03-frontend-sveltekit.md#11-css--tailwind-v4-em-duas-camadas) ("CSS vanilla + custom properties, **não** Tailwind") e a consequência de CSS do [ADR-006](#adr-006--frontend-em-svelte-5-runes--typescript).

**Contexto.** A recomendação anterior era CSS vanilla com custom properties e `<style>` scoped, e o argumento contra Tailwind era concreto: o protótipo não tem folha de estilo nem uma única classe — são **1.205 objetos de estilo inline** (`style=${{…}}`, contagem verificada), **zero** `class=`, e toda cor é expressão JS derivada de um switch `dark` via `theme()` ([`:301`](../interface/Movimento.dc.html#L301)) e `tint(hex,a)` ([`:314`](../interface/Movimento.dc.html#L314)). O único CSS real do protótipo são 19 linhas num `<style>` global (reset, 7 `@keyframes`, scrollbar, `focus-visible`). Portar isso para Tailwind seria "dois trabalhos": traduzir cada objeto **e** reconstruir a paleta como config.

**O que mudou.** Aquele argumento mira o Tailwind v3, onde a paleta vivia em `tailwind.config.js` — um arquivo JS divorciado das custom properties, de onde vinha a duplicação. No **v4 a paleta é CSS**: o bloco `@theme inline` emite as custom properties *e* gera os utilitários a partir delas, de uma fonte só. A objeção de "dois trabalhos" deixa de valer. Além disso o padrão mais repetido do protótipo — `tint(cor, alpha)`, 58 chamadas — mapeia direto para o modificador de opacidade (`bg-danger/10`), que é mais limpo que o `color-mix` que a proposta vanilla exigia.

**Decisão.** **Tailwind v4**, via `@tailwindcss/vite`, organizado em **duas camadas** num único `src/lib/styles/app.css`:

1. **Camada de proveniência** — custom properties `--mv-*` e `--cat-*` com os hex **verbatim** do protótipo, trocadas por `[data-theme]`. Preserva a relação auditável "esta cor do protótipo = esta variável" que motivava a decisão anterior.
2. **Camada de utilitários** — `@theme inline` mapeando aquelas variáveis para os namespaces do Tailwind. Como é `inline`, o utilitário gerado referencia `var(--mv-…)` em vez de copiar o valor, então a troca de tema em runtime continua sendo só um atributo no `<html>`.

Dark mode continua por `data-theme` (`@custom-variant dark`), não por `class` nem `prefers-color-scheme` puro — o SSR estampa o atributo e não há flash ([03 §4.4](03-frontend-sveltekit.md#44-dark-mode-via-data-theme-sem-flash)).

**Alternativas descartadas.**

| Alternativa | Por que não |
|---|---|
| Manter CSS vanilla + custom properties (a decisão anterior) | Continua correta e defensável. Perde o modificador de opacidade para os 58 `tint()`, e deixa o layout de cada componente num `<style>` scoped separado do markup. A escolha entre as duas é de preferência de equipe, não de viabilidade — foi feita a favor do utilitário. |
| Tailwind v3 | É exatamente o alvo do argumento original: paleta em `tailwind.config.js`, duplicada em relação às custom properties que o `data-theme` precisa. Reintroduz os "dois trabalhos". |
| Tailwind v4 **sem** a camada 1, hex direto no `@theme` | `@theme` não-`inline` congela o valor no utilitário gerado; a troca por `data-theme` pararia de funcionar. E perderia a proveniência hex→protótipo, que o [ADR-001](#adr-001--o-protótipo-é-a-especificação-de-origem) exige. |

**Consequências.**

- **O volume de trabalho do port não muda.** Os 1.205 objetos inline são reescritos à mão de qualquer forma; o ADR decide no que eles viram, não quantos são. Continua valendo a regra do risco 1 ([03 §9](03-frontend-sveltekit.md#9-riscos-do-port-react--svelte-5)): **não** transcrever objeto-a-objeto.
- **Duas coisas não viram utilitário, por construção.** (a) As cores categóricas: `profColor`/`patientColor` indexam `cat[]` com um `ci` calculado em runtime ([`:315`](../interface/Movimento.dc.html#L315)–[`:316`](../interface/Movimento.dc.html#L316)), e o Tailwind gera classes em build — ficam como custom property setada inline, consumida por `bg-(--var)`. (b) A densidade `--mv-ppm` é aritmética dentro de `calc()` ([`:1228`](../interface/Movimento.dc.html#L1228)), não um valor de escala — segue custom property pura.
- Uma dependência de build a mais e um plugin de formatação (`prettier-plugin-tailwindcss`) para a ordem das classes.
- **Não muda nada em QA visual.** Os 79 PNGs continuam oráculo de aceitação humana, nunca assert de pixel ([07 §7.3](07-estrategia-de-testes.md#73-regressão-visual-contra-os-79-screenshots--avaliação-honesta)) — o motivo é que o framework e o CSS são outros, e trocar vanilla por Tailwind só reforça isso.
- O `<style>` de 19 linhas do protótipo (reset, keyframes, scrollbar, focus) **não** é migrado: reset vem do `@import "tailwindcss"`, e os 7 `@keyframes` viram tokens `--animate-*`. O protótipo permanece congelado ([ADR-001](#adr-001--o-protótipo-é-a-especificação-de-origem)).

---

## ADR-011 — Não há renovação de pacote; o total de sessões é ajustável a qualquer momento

**Status:** Aceita (2026-07-10) · **Reconcilia:** decisão de produto **D7** ([10-decisoes-de-produto-v1.md](10-decisoes-de-produto-v1.md)) × comportamento do protótipo (RN-22, [02 §1.5](02-regras-e-lacunas.md))

**Contexto.** O único fluxo de "Renovar" **alcançável pela UI** — `openRenovar` ([`:336`](../interface/Movimento.dc.html#L336)) → `modalRenovar` ([`:606`](../interface/Movimento.dc.html#L606)) → `confirmRenovar` ([`:590`](../interface/Movimento.dc.html#L590)) — **adiciona sessões ao mesmo pacote**: soma ao `total` e mantém o status `ativo` ([`:600`](../interface/Movimento.dc.html#L600); texto do modal em [`:629`](../interface/Movimento.dc.html#L629), toast em [`:601`](../interface/Movimento.dc.html#L601)) — ou seja, já corresponde ao lado "aumentar" da Decisão. O mecanismo de **pacote-sucessor** — criar um novo pacote com `renovadoDe` e marcar o anterior como `renovado` ([`:358`](../interface/Movimento.dc.html#L358), [`:362`](../interface/Movimento.dc.html#L362); RN-22) — é **código vestigial e inalcançável**: nenhuma UI seta `renovadoDe` e, no único ponto do seed em que ele aparece ([`:108`](../interface/Movimento.dc.html#L108)), o predecessor fica `concluido`, nunca `renovado`. O documento de domínio [01 §4.4](01-dominio-ash.md) modelou esse ramo morto — relação `renovado_de` e o valor `:renovado` no enum `PackageStatus`. A real novidade da operação da clínica não é o acréscimo no mesmo pacote (que o protótipo já faz), e sim a capacidade de **diminuir (−)** o total: o total de sessões de um pacote é simplesmente **editável, para mais ou para menos, a qualquer momento**.

**Decisão.** **Não existe renovação.** Um pacote tem um `total` de sessões que pode ser **aumentado ou diminuído a qualquer momento**, sobre o mesmo registro. Aumentar materializa novas sessões na série (via `computeSerie`, [02 §1.5](02-regras-e-lacunas.md)); diminuir remove sessões futuras ainda não consumidas. O débito acumula sempre no mesmo pacote.

**Consequências.**
- `PackageStatus` perde o valor `:renovado` → fica `[:ativo, :pausado, :cancelado, :concluido]`.
- O `Package` perde a relação `belongs_to :renovado_de` ([01 §4.4](01-dominio-ash.md) a ser corrigido).
- **Não há ação `:renew`.** O ajuste do total vira `add_session`/`remove_session` (individuais ou em lote) sobre o mesmo pacote; `total` é editável enquanto o pacote está `:ativo`. Diminuir só alcança sessões **futuras e não consumidas** — sessões já concluídas/faltadas não são apagadas.
- **Divergência deliberada do [ADR-001](#adr-001--o-protótipo-é-a-especificação-de-origem)** (o protótipo é a spec). Registrada como tal: a produção **não** reproduz o sucessor do protótipo. Catalogar em [02](02-regras-e-lacunas.md) como GAP de renovação.

---

## ADR-012 — Profissional pertence a uma única clínica na v1

**Status:** Aceita (2026-07-10) · **Restringe:** [ADR-003](#adr-003--saas-multi-clínica-desde-o-primeiro-commit) (RN-52) · **Reconcilia:** decisão de produto **D15**

**Contexto.** O [ADR-003](#adr-003--saas-multi-clínica-desde-o-primeiro-commit) abriu explicitamente a porta para um **profissional existir em mais de uma clínica** (RN-52, [02 §3.1](02-regras-e-lacunas.md)) — uma regra nova, sem precedente no protótipo. Isso tornaria o vínculo profissional↔clínica um relacionamento, com agenda, disponibilidade e repasse **por vínculo**, não por pessoa.

**Decisão.** Na **v1**, um profissional pertence a **uma única clínica**. O multi-clínica de profissional fica para a **v2**.

**Justificativa.** Combina com a estratégia de tenancy escolhida — `strategy :context`, schema-por-tenant ([01 §2](01-dominio-ash.md)): um profissional vive dentro do schema do seu tenant, e `Membership.professional_id` permanece um UUID mole por clínica, sem FK entre schemas. Suportar a mesma pessoa em vários schemas exigiria um modelo de identidade de profissional global — custo que não se paga na v1.

**Consequências.**
- **Não anula o [ADR-003](#adr-003--saas-multi-clínica-desde-o-primeiro-commit):** o SaaS continua multi-clínica no nível de **tenant/organização**; apenas a cláusula "profissional em várias clínicas" é adiada.
- RN-52 passa a ser **v2**. O vínculo profissional↔clínica é simples (um por profissional).
- A exclusion constraint de não-sobreposição não precisa carregar `clinic_id` (já garantido pelo schema-por-tenant, [01 §2](01-dominio-ash.md)).

---

## ADR-013 — Prontuário clínico (LGPD Art. 11) é v2; a v1 tem apenas a ficha do paciente

**Status:** Aceita (2026-07-10) · **Restringe:** [ADR-007](#adr-007--dado-de-saúde-é-tratado-como-categoria-especial-da-lgpd) · **Reconcilia:** decisão de produto **D16**

**Contexto.** O [ADR-007](#adr-007--dado-de-saúde-é-tratado-como-categoria-especial-da-lgpd) trata o prontuário completo como requisito da v1: tags clínicas (diagnóstico), anexos (laudos/exames), encaminhamento, consentimento versionado — tudo LGPD Art. 11, com AshCloak, AshPaperTrail, field policies e purga (o Gate G1 do [08 §6](08-roadmap.md)). A decisão de produto **D16** reduz o escopo: **a v1 não tem prontuário — só a ficha do paciente** (dados cadastrais). Todos os papéis **visualizam** o paciente; o **profissional é somente-leitura** na ficha.

**Decisão.** O **prontuário clínico é v2**. A v1 modela apenas a **ficha** (identificação e contato do paciente). Ficam **fora da v1**: `ClinicalTag`, `Attachment`, `Consent` versionado, e o mapa fino campo×papel de leitura de dado clínico.

**⚠️ Consequência que corrige um exagero anterior — a LGPD encolhe, não desaparece.** Mesmo "só a ficha" carrega, no modelo do [01 §4.6](01-dominio-ash.md), dado **pessoal e alguns sensíveis**: CPF, RG, telefone, e-mail e — se mantidos — **médico/CRM** (encaminhamento revela tratamento) e **convênio/carteirinha**. E a fila de espera tem `obs` = **queixa clínica**. Portanto **não** se pode concluir que "sem prontuário ⇒ sem proteção LGPD". As proteções que **ainda podem valer na v1** dependem das sub-decisões abaixo.

**Sub-decisões que este ADR deixa explicitamente em aberto** (a resolver antes das fatias indicadas):
1. A ficha v1 inclui **médico/CRM/convênio** (sensível) ou **só nome + contato**? — antes de modelar a ficha.
2. **CPF** precisa de cifra (`AshCloak`) + **índice cego** para a busca por documento (`byDoc`, [01 §4.6](01-dominio-ash.md)) na v1? — antes de modelar a ficha.
3. **`fila.obs`**: vira observação **operacional** (não-clínica, sem proteção especial) ou **recebe field policy/cifra**? — antes da Fatia 4.

**Consequências.**
- O domínio `Movimento.Records` ([01 §4.6](01-dominio-ash.md)) encolhe para `Patient` (ficha); `Attachment`/`ClinicalTag`/`Consent` são v2.
- O **Gate G1** ([08 §6](08-roadmap.md)) perde a maior parte do peso na v1, mas **não** é eliminado: o que sobra depende das sub-decisões 1–3.
- A **Fatia 6** do roadmap ([08 §4](08-roadmap.md)) deixa de ser "prontuário completo" e passa a ser "ficha do paciente"; o prontuário migra para v2.
- Não anula o [ADR-007](#adr-007--dado-de-saúde-é-tratado-como-categoria-especial-da-lgpd): quando o prontuário entrar (v2), o ADR-007 volta a valer integralmente.

---

## Decisões ainda em aberto

Estas **não** estão travadas e precisam de resposta antes de fatias específicas. A lista completa e priorizada está em [02-regras-e-lacunas.md](02-regras-e-lacunas.md), Parte 4.

**Já resolvidas** (2026-07-10, ver [10-decisoes-de-produto-v1.md](10-decisoes-de-produto-v1.md) e ADRs 011–013):
- ~~Pacote tem validade real? Pausar estende?~~ → **D6: sem validade.**
- ~~Presença individual em turma confirma-se?~~ → **D10: sim, por participante.**
- ~~"Renovar" é continuar ou criar sucessor?~~ → **[ADR-011](#adr-011--não-há-renovação-de-pacote-o-total-de-sessões-é-ajustável-a-qualquer-momento): não há renovação; total editável a qualquer momento.**
- ~~Profissional em mais de uma clínica?~~ → **[ADR-012](#adr-012--profissional-pertence-a-uma-única-clínica-na-v1): um por clínica na v1.**
- ~~Prontuário/LGPD Art. 11 na v1?~~ → **[ADR-013](#adr-013--prontuário-clínico-lgpd-art-11-é-v2-a-v1-tem-apenas-a-ficha-do-paciente): v2; v1 só a ficha.**

**Ainda em aberto:**

| Tema | Bloqueia | Quando |
|---|---|---|
| Ficha v1 inclui médico/CRM/convênio (sensível) ou só nome+contato? CPF precisa de cifra + índice cego? | Schema da ficha ([ADR-013](#adr-013--prontuário-clínico-lgpd-art-11-é-v2-a-v1-tem-apenas-a-ficha-do-paciente)) | Antes da ficha |
| `fila.obs` (queixa clínica): observação operacional ou campo protegido? | Schema/policy da fila ([ADR-013](#adr-013--prontuário-clínico-lgpd-art-11-é-v2-a-v1-tem-apenas-a-ficha-do-paciente)) | Antes da Fatia 4 |
| Salas / equipamentos como recurso com capacidade (hoje conflito é só por profissional) | Schema | v2 |
| Preço varia por convênio/particular/reembolso? Há repasse ao profissional? | Subdomínio faturamento | v2 |
| Faturamento, guias de convênio, nota fiscal | Subdomínio faturamento | v2 |
| Multi-unidade dentro da mesma clínica | Modelo de filial | v2 |
| Profissional em mais de uma clínica (reaberto na v2) | Vínculo prof↔clínica ([ADR-012](#adr-012--profissional-pertence-a-uma-única-clínica-na-v1)) | v2 |
