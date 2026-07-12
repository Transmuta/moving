# Resumo consolidado — decisões e regras de negócio

Mapa de navegação de tudo que está **travado** (ADRs), **decidido** (produto v1) e
**catalogado** (regras do protótipo), com as **correções** do que estava mal-entendido em
destaque no topo. Revisado em 2026-07-10.

> Este documento é um **índice/mapa**, não a fonte. A fonte canônica das regras de negócio é
> [02-regras-e-lacunas.md](02-regras-e-lacunas.md); das decisões de arquitetura,
> [00-decisoes.md](00-decisoes.md); das decisões de produto v1,
> [10-decisoes-de-produto-v1.md](10-decisoes-de-produto-v1.md).

---

## 1. Correções — o que estava mal-entendido

Priorizado porque muda o plano e porque alguns pontos **contradiziam um ADR travado ou o
protótipo**. As contradições com ADRs já foram **reconciliadas** (1.3 → [ADR-011](00-decisoes.md),
1.4 → [ADR-012](00-decisoes.md), 1.2 → [ADR-013](00-decisoes.md)); restavam só as sub-decisões da
ficha (escopo médico/CRM/convênio, cifra do CPF, natureza da `fila.obs`), **resolvidas em
2026-07-11** (D17–D19).

### 1.1 Os docs 01, 02 e 03 já existem  ⚠️ plano mudou

Foi dito, na sessão de faseamento, que `01-dominio-ash`, `02-regras-e-lacunas` e
`03-frontend-sveltekit` "ainda não existiam", e propôs-se um bloco de sessões para
escrevê-los. **Eles existem e são densos**: o `02` tem 60 regras (RN-01…RN-60) e 16 lacunas;
o `01` tem o modelo Ash inteiro (7 domínios, enums, recursos, migration). A afirmação de
inexistência veio de uma **nota de proveniência desatualizada do roadmap**
([08-roadmap.md](08-roadmap.md)). Consequência: o "Bloco A — fundação escrita" **sai do
plano**.

### 1.2 "v1 sem prontuário" reduz, mas não zera, a LGPD  ✅ núcleo resolvido em [ADR-013](00-decisoes.md)

Concluiu-se que, sem prontuário, o **Gate G1 inteiro** (AshCloak, field policies, purga)
sairia do caminho crítico da v1. **Forte demais.** Mesmo **só a ficha** carrega, no modelo do
[01 §4.6](01-dominio-ash.md): CPF, RG, telefone, e-mail (todos `sensitive?`) e **médico/CRM**
(encaminhamento — revela tratamento, é sensível no [06](06-seguranca-e-lgpd.md)). E a fila tem
`obs` = queixa clínica cifrada. O que precisa decidir de fato:

- A ficha v1 inclui **médico/CRM/convênio** (sensível) ou só nome + contato?
- **CPF** ainda precisa de cifra + índice cego para a busca?

A LGPD encolhe, não desaparece.

**Resolvido em 2026-07-11 (D17–D19, [10](10-decisoes-de-produto-v1.md)):** ficha **completa**
(todos os campos, inclusive `medico`/`crm`), **opção A** — entram `field_policies` sobre
`medico`/`crm` na v1 (único resíduo de dado sensível); **CPF sem cifra** na v1 (AshCloak → v2);
**`fila.obs` operacional**. A v1 fica com uma proteção mínima de campo, sem AshCloak/Gate G1.

### 1.3 Não há renovação de pacote  ⚠️ divergência deliberada · resolvido em [ADR-011](00-decisoes.md)

Decisão **D7**, refinada pelo usuário: **não existe "renovação"**. O pacote tem um `total` de
sessões que se **aumenta ou diminui a qualquer momento**, no mesmo registro. O **protótipo faz
outra coisa**: renovar cria um **pacote-sucessor** com `renovadoDe` e marca o anterior como
`:renovado` (RN-22). A decisão é uma **divergência deliberada do ADR-001** — registrada no
[ADR-011](00-decisoes.md), que remove o status `:renovado`, a relação `renovado_de` e a ação
`:renew`. Docs `01` e `08` já sincronizados.

### 1.4 Profissional multi-clínica — identidade global estilo Vercel  ✅ resolvido em [ADR-014](00-decisoes.md) (reverte ADR-012)

**Revisado em 2026-07-11.** A decisão **D15** original ("cada profissional em uma única
clínica", [ADR-012](00-decisoes.md)) foi **revertida**: adotamos o **modelo de identidade
estilo Vercel** ([ADR-014](00-decisoes.md)). Um `User` global pertence a **vários** tenants,
com papel isolado em cada; um profissional atende em **mais de uma clínica** e uma dona tem
**mais de uma unidade**, trocando entre elas por um seletor. A RN-52 **volta para a v1**. O
`strategy :context` do `01` **sobrevive** porque a identidade global é o `User` (schema
público), não o `Professional` (por-schema, ligado via `Membership.professional_id`). Junto
vieram [ADR-015](00-decisoes.md) (login Google + Magic Link, sem senha) e
[ADR-016](00-decisoes.md) (papéis `owner·admin·profissional·recepcao`, ≥1 owner por tenant).

### 1.5 Bloquear conflito futuro já é o que o protótipo faz  ✅ alinhado

Na pergunta da Fatia 7, "sinalizar (decisão manual)" foi marcado como recomendado; o usuário
escolheu "bloqueia a mudança". A escolha do usuário é a **correta e a que o protótipo já
implementa**: `saveProf` bloqueia o salvamento quando há futuro conflitante (RN-15). A
recomendação anterior estava errada.

### 1.6 Numeração de GAP trocada  · nota

No doc 10, a turma multi-pacote foi chamada de "GAP-09" (numeração provisória do roadmap). O
número canônico no `02` é **GAP-07**. A decisão (D11) está **alinhada** à correção que o `01`
propõe: dissolver o mapa `pkgOf` em `Attendance.package_id`.

### 1.7 Dois ajustes finos de escopo  · nota

- **D6** (pacote sem validade) **confirma** a "correção i" do `01` (01:1142), que já registra
  "pacote sem validade" alinhada a [ADR-013](00-decisoes.md)/D6 — não propõe `validade_ate`. O
  campo `validade_ate` pertence ao **desenho anterior descartado** (01:758), não à correção i.
  Decisão **fiel ao ADR-001**.
- **D14** vale para **fechamento** (feriado `tipo:fechado` vence tudo, RN-08), mas o motor
  **ainda suporta folga/exceção do profissional** em geral (RN-09) — não ler D14 como
  "profissional nunca tem exceção".

---

## 2. Decisões de produto — v1

As 16 decisões fechadas, reconciliadas com as perguntas canônicas `P-01…P-20` do
[02 §4](02-regras-e-lacunas.md) e com o comportamento real do protótipo. Registro completo em
[10-decisoes-de-produto-v1.md](10-decisoes-de-produto-v1.md).

| # | Decisão | Resolve | Situação |
|---|---|---|---|
| D1 | Profissional vê só a própria agenda; admin e membro veem a clínica toda | P-08 | resolve |
| D2 | Encaixe criado só por admin e membro (recepção) | P-09 | resolve |
| D3 | Passo da grade por clínica; duração por tipo → `AppointmentType` na Fatia 1 | P-15 | bate c/ RN-02 |
| D4 | Cancelar: motivo opcional + libera vaga à fila automaticamente | P-10 | resolve |
| D5 | Remarcar/concluir/faltar no passado permitido a todos | P-10 | resolve |
| D6 | Pacote sem validade (confirma a "correção i" do doc 01) | P-01 | fiel ao protótipo |
| D7 | **Sem renovação;** total de sessões editável (+/−) a qualquer momento | P-02 | ADR-011 (contradiz RN-22) |
| D8 | TTL do SlotHold = 10 min | P-11 | docs diziam 5 |
| D9 | Fila: prioridade + ordem de chegada | P-11 | enum já existe |
| D10 | Presença individual por participante em turma | P-03 | confirma GAP-06 |
| D11 | Não há "pacote de turma"; massa por (paciente, pacote) | GAP-07 | alinha ao 01 |
| D12 | Conflito futuro bloqueia a mudança de horário | P-12 | já é RN-15 |
| D13 | Timezone só Brasília, imutável | P-16 | default do 01 |
| D14 | Feriado (fechado) = bloqueio absoluto, sem exceção por profissional | P-16 | bate c/ RN-08 |
| D15 | ~~Profissional em uma única clínica~~ → **multi-clínica SIM** (revisado 2026-07-11) | P-06 | **ADR-014** (reverte ADR-012; modelo Vercel) |
| D16 | v1 sem prontuário; só ficha; todos veem, profissional só lê | P-04 | ADR-013 (prontuário → v2) |
| D20–D24 | Identidade global multi-tenant; unidade=tenant; papéis+owner; login Google/Magic Link | — | **ADR-014/015/016** |

---

## 3. Decisões de arquitetura (ADR)

Travadas — só mudam por um novo ADR. Fonte: [00-decisoes.md](00-decisoes.md).

| ADR | Decisão |
|---|---|
| 001 | **O protótipo é a spec de origem.** Toda regra cita a linha do protótipo; divergências viram GAP-nn. Protótipo congelado; 79 screenshots são baseline de QA. |
| 002 | **Backend Elixir + Ash 3.x** sobre Phoenix, exposto como **AshJsonApi**. Ganha policies, field policies, AshCloak, AshPaperTrail, agregados no SQL. |
| 003 | **SaaS multi-clínica** desde o 1º commit; toda entidade escopada a um tenant. Um profissional pode estar em várias clínicas — **confirmado na v1 pelo [ADR-014](00-decisoes.md)** (identidade global estilo Vercel; ADR-012 revertido). |
| 014/015/016 | **Modelo de identidade Vercel:** `User` global multi-tenant, profissional/owner multi-clínica ([014](00-decisoes.md)); login **Google + Magic Link**, sem senha ([015](00-decisoes.md)); papéis `owner·admin·profissional·recepcao` c/ capabilities embarcadas e **≥1 owner por tenant** ([016](00-decisoes.md)). |
| 004 | **Agenda em tempo real** via Phoenix Channels + PubSub alimentado por notificações do Ash. Cliente Svelte usa o pacote `phoenix` direto. |
| 005 | **SvelteKit como BFF**, nunca cliente de banco. `load`/`actions` chamam a API Phoenix portando o cookie de sessão. |
| 006 | **Svelte 5 (runes) + TypeScript**, adapter-node. Port React→Svelte não é mecânico. |
| 007 | **Dado de saúde = LGPD Art. 11.** AshCloak, AshPaperTrail, field policies, anexos com URL assinada, consentimento versionado, retenção. **Revisado por [ADR-013](00-decisoes.md): prontuário → v2; v1 só a ficha.** |
| 008 | **Deploy Fly.io** (api Elixir + web Node), Postgres gerenciado, storage S3-compat, **OpenTelemetry puro**. Região `gru` a verificar antes de dado real. |
| 009 | **Relógio injetável, timezone por clínica.** Nenhum módulo lê o relógio do sistema. Substitui `hoje()`/`NOW=702`. |
| 010 | **CSS utilitário com Tailwind v4** (substitui CSS vanilla do 03/ADR-006). Paleta em `@theme inline` sobre `--mv-*`; dark por `data-theme`. |

---

## 4. Regras de negócio (RN-01…RN-60) — digest por domínio

O texto normativo completo das 60 regras é [02 §1 e §3](02-regras-e-lacunas.md). Aqui é o mapa.

- **Agenda & slots (RN-01…06).** Agendamento = `{prof, tipo, início, duração, status}`, tempo
  em minutos desde a meia-noite. Duração vem do **tipo** (RN-02). Status ∈ 6 valores. Sessão de
  pacote pausado (`pkgHold`) some da agenda e das contagens (RN-05).
- **Disponibilidade — `dayPeriods` (RN-07…10).** Precedência de **4 camadas, primeira decide**:
  (A) fechamento da clínica vence tudo; (B) exceção do profissional vence (C) horário especial
  da clínica; (D) horário semanal. **Sutileza:** `avail[dow]=null` presente (fecha) ≠ chave
  ausente (herda) → `Map.has_key?`, não `Map.get`.
- **Conflito & encaixe (RN-11…14).** Conflito **só por profissional** (sem sala — GAP-15).
  **Encaixe** é sobreposição deliberada, imune ao conflito nos dois sentidos. Disponibilidade e
  não-conflito são checagens independentes, ambas necessárias.
- **Impacto retroativo — `futureConflicts` (RN-15…17).** Entra só quem "cabia e deixou de
  caber". Compõe `dayPeriods`. O protótipo **bloqueia o salvamento** (= D12).
- **Pacotes (RN-18…28).** Cada sessão é um agendamento real ligado por `pkgId`. `computeSerie`
  gera N sessões e **pula + estende por feriado**. `usadas` é **derivado**, não coluna. Bugs:
  pausa +21 fixo e retomada em datas passadas (GAP-08).
- **Consumo & falta punitiva (RN-29…32).** **Concluído sempre debita.** **Falta debita só se
  punitiva e não justificada.** "Punitiva" é do pacote, com fallback global `noShowConsome`.
- **Turma (RN-33…36).** Agendamento com array `patientIds`. Hoje presença é do bloco (GAP-06),
  mas cada participante pode ter pacote próprio (`pkgOf`) e `apptPkg` só devolve o primeiro
  (GAP-07). Capacidade = `type.cap`; encaixe excede.
- **Fila de vagas — `filaVagas` (RN-37…43).** Varre 14 dias × profissionais preferidos, em duas
  passadas: (1) vagas que abriram por cancel/falta no horário exato; (2) 1ª brecha livre de cada
  período (passo 30 min). Corta o passado do dia. Teto 50. **Oferecer não reserva** (GAP-16).
- **Faltas & relatórios (RN-44…48).** `patient.faltas` é contador denormalizado (GAP-09).
  Relatório: taxa de falta, por tipo/prof/dia. Faturamento é preço hardcoded (GAP-10);
  **ocupação tem 3 definições divergentes** (GAP-11).
- **Papéis (RN-49…50).** Três papéis (admin/profissional/membro), hoje **sem enforcement**
  (GAP-12). Vínculo membro↔profissional opcional e único.
- **Regras novas dos ADRs (RN-51…60).** Tenant da sessão, nunca do cliente. Concorrência:
  exclusion constraint btree_gist (RN-53), SlotHold com TTL (RN-54, **now() é STABLE —
  expiração na DML, não na constraint**), locking otimista por version (RN-55). PubSub em 2
  resoluções. "Já começou" (start≤agora) ≠ "precisa de ação" (fim≤agora). Auditoria inclui
  **leitura** (RN-60).

---

## 5. Lacunas — protótipo → produção (GAP-01…16)

Fonte: [02 §2](02-regras-e-lacunas.md). A fatia que fecha cada uma está no roadmap.

| GAP | Protótipo hoje → produção |
|---|---|
| 01 | Relógio congelado (`hoje()`, `NOW=702`) → relógio injetável no fuso da clínica |
| 02 | `settings.slot` declarado e nunca lido; 15 min hardcoded → passo de config real |
| 03 | Arrasto valida conflito mas **não** disponibilidade → servidor checa ambos |
| 04 | `openMassaPacote` é fluxo órfão → decidir se entra na v1 |
| 05 | Faixa de almoço 12–13h hardcoded → derivar dos buracos entre períodos |
| 06 | Presença por turma → presença por participante (= D10) |
| 07 | **A mais séria:** `pkgOf` multi-pacote, `apptPkg` devolve só o 1º → 1-p/-muitos explícito (= D11) |
| 08 | Pausa +21 fixo, retomada em datas passadas → reprojeta a série para o futuro |
| 09 | `patient.faltas` denormalizado → agregado derivado do histórico |
| 10 | Preço hardcoded no relatório → v2 (faturamento); v1 no máximo preço simples |
| 11 | Três definições de ocupação → uma canônica (tempo agendado ÷ expediente real) |
| 12 | RBAC não aplicado → `Ash.Policy.Authorizer` + field policies; papéis `owner·admin·profissional·recepcao` (ADR-016) |
| 13 | Sem autenticação (botão Entrar só navega) → AshAuthentication **Google OAuth + Magic Link** (sem senha, ADR-015), sessão por cookie |
| 14 | Relatório sobre histórico sintético → snapshot noturno sobre dados reais |
| 15 | Sem salas/recursos (conflito só por prof) → v2, mudança de constraint mais cara |
| 16 | Sem reserva de vaga (corrida entre atendentes) → `SlotHold` com TTL (= D8) |

---

## 6. Pendências abertas depois desta sessão

O que ainda precisa de decisão antes de virar schema/código.

**Já reconciliado por ADR (2026-07-10):** ADR-011 (sem renovação), ~~ADR-012 (prof 1 clínica na
v1)~~ **revertido por ADR-014**, ADR-013 (prontuário = v2, v1 só ficha). Docs `00`, `01` e `08`
sincronizados.

**Reconciliado em 2026-07-11 (modelo Vercel):** ADR-014 (identidade global multi-tenant;
profissional/owner multi-clínica), ADR-015 (Google + Magic Link, sem senha), ADR-016
(papéis + owner obrigatório). Docs `00`, `01`, `06`, `09`, `10`, `11`, `12`, `04`, `08`
sincronizados.

**Ainda em aberto:**

**Resolvido em 2026-07-11 (D17–D19):** escopo da ficha (completa + opção A/field policies),
CPF sem cifra, `fila.obs` operacional. Schema do `Patient` destravado. Falta só sincronizar o
doc 01 §4.6 (remover cifra do CPF; adicionar field policies em `medico`/`crm`).

| Tema | Pergunta | Quando |
|---|---|---|
| **Sync doc 01** | Alinhar §4.6 a D17/D18 (field policies em médico/CRM; CPF sem cifra) | antes do schema do Patient |
| **Ocupação** | Definição canônica (GAP-11); métricas do relatório (P-13/P-14) | antes da Fatia 9 |
| **Ajuste em massa** | O fluxo órfão de ajuste em massa de pacote (GAP-04) entra na v1? | antes da Fatia 5 |

**Próxima sessão fechável.** Os ADRs de reconciliação (011–013) já foram escritos e os docs
sincronizados. As **sub-decisões da ficha** (escopo, cifra do CPF, natureza da `fila.obs`)
foram **resolvidas em 2026-07-11** (D17–D19): ficha completa + `field_policies` em
`medico`/`crm` (opção A), CPF sem cifra, `fila.obs` operacional. O schema do `Patient` está
**destravado**. Resta um **sync mecânico do doc 01 §4.6** e então parte-se para o **andaime da
Fatia 0**.
