# Decisões de produto — v1 (fechadas em 2026-07-10)

> **Revisão de 2026-07-11 — modelo de identidade estilo Vercel.** Uma sessão posterior
> **reverteu D15** e adicionou as decisões de **identidade, tenant e acesso** (bloco no fim
> deste doc): `User` global multi-tenant, profissional/owner **multi-clínica**, papéis
> `owner·admin·profissional·recepcao` com capabilities embarcadas, e login por **Google +
> Magic Link** (sem senha). Ver [ADR-014/015/016](00-decisoes.md). Onde este doc ainda disser
> "membro", leia **`recepcao`** (mesmo papel); `owner` é o novo papel no topo.

Este documento fixa as **decisões de produto que estavam em aberto** em
[00-decisoes.md](00-decisoes.md) (seção "Decisões ainda em aberto") e nas seções
"Perguntas de produto ANTES" de cada fatia do [08-roadmap.md](08-roadmap.md). Foram
respondidas pelo usuário numa sessão dedicada, antes de qualquer schema, para evitar
retrabalho de migração de dado depois.

**Esta é a fonte das decisões que o [02-regras-e-lacunas.md](02-regras-e-lacunas.md),
Parte 4, deve absorver quando for escrito** — do mesmo modo que o §9 do roadmap fixou
provisoriamente a numeração de GAPs. Onde o 02 divergir, é o 02 que se alinha a este doc.

Cada decisão marca a fatia que ela destrava e a consequência de schema/policy.

---

## Fatia 1 — Agenda

- **D1 · Visibilidade da agenda.** Profissional vê **só a própria** agenda; **admin** e
  **membro (recepção)** veem a clínica inteira.
  → *Policy de leitura* de `Appointment` filtra por actor quando `papel == :profissional`;
  admin/membro sem filtro de profissional. Não é `clinic_id` do cliente — resolvido pela
  sessão (ADR-005).

- **D2 · Encaixe (sobreposição deliberada).** Criado **apenas por admin e membro
  (recepção)**. Profissional não cria encaixe.
  → *Policy de criação* com `encaixe: true` exige papel `admin` ou `membro`. A exclusion
  constraint de não-sobreposição (GAP-02) precisa da exceção para `encaixe`.

- **D3 · Grade e duração.** O **passo da grade** (`STEP`) é por **clínica**; a **duração**
  (`DUR`) é por **tipo de atendimento**.
  → **Consequência de escopo:** o recurso **`AppointmentType`** entra já na **Fatia 1**
  (o protótipo o tratava como config tardia). O tipo carrega a duração padrão; a clínica
  carrega o passo da grade.

---

## Fatia 2 — Ciclo de vida do atendimento

- **D4 · Cancelamento.** Motivo é **opcional**; cancelar **libera a vaga para a fila
  automaticamente**.
  → Liga Fatia 2 ↔ Fatia 4 desde cedo: a ação `:cancel` emite o evento que oferta a vaga.
  Sem campo de motivo obrigatório no schema.

- **D5 · Ações no passado.** Remarcar / concluir / faltar com **data no passado é permitido
  para todos os papéis** (corrigir registro).
  → O relógio injetável (ADR-009) continua sendo a fonte de "já começou", mas as transições
  **não** ficam presas ao `agora`. Os **relatórios (Fatia 9) devem tolerar registro
  retroativo** — a data do fato pode ser anterior à data de lançamento.

---

## Fatia 3 — Pacotes

- **D6 · Validade.** Pacote **não tem validade**. Vale até as sessões acabarem, sem data
  limite.
  → Schema de pacote **sem** campo de expiração. Como não há validade, **pausar não estende
  nada**; a retomada (`pkgResume`, GAP-06) apenas reprojeta as sessões restantes para o
  futuro, nunca para o passado.

- **D7 · Renovar.** Renovar é **continuar o mesmo pacote** — há **um único fluxo** de ajuste
  que **diminui ou acrescenta sessões no mesmo registro**. Não há pacote-sucessor.
  → Schema **enxuto**: sem vínculo pacote→pacote, sem histórico de "compra nova". O débito
  acumula num único registro por pacote.

---

## Fatia 4 — Fila de espera + hold

- **D8 · TTL do `SlotHold`.** **10 minutos.**
  → Job Oban de varredura de expirados usa 10 min; exclusion constraint sobre
  `(professional_id, intervalo)` filtrada por holds não expirados (GAP-07).

- **D9 · Prioridade da fila.** **Prioridade + ordem de chegada**: um nível de urgência
  reordena a fila; empate resolvido por ordem de chegada.
  → Schema da fila com **campo de prioridade** e regra de ordenação `(prioridade, inserted_at)`.

---

## Fatia 5 — Turma

- **D10 · Presença individual.** **Sim** — cada participante tem **presença e débito de
  sessão próprios** (a correção proposta no roadmap; GAP-08).
  → Schema do agendamento de turma com **registro de presença por participante**; o débito de
  pacote acontece por participante.

- **D11 · GAP-09 redefinido — não existe "pacote de turma".** O ajuste em massa é **sempre
  por (paciente, pacote)**. Turma = **vários pacientes no mesmo horário**, cada um com o seu
  próprio pacote. Não há um pacote compartilhado pela turma.
  → O modelo de `apptPkg`/`massaAffected` do protótipo deixa de ser "afeta todos vs. âncora":
  a mudança em massa opera **sempre sobre o pacote de um único paciente**, explicitamente. O
  GAP-09 do roadmap (§9) deve ser reescrito nesse sentido — some a ambiguidade do "ignora os
  demais em silêncio" porque não há "demais pacotes da turma" a considerar.

---

## Fatia 7 — Horários editáveis

- **D12 · Conflito futuro ao mudar horário do profissional.** Os agendamentos futuros que
  passariam a conflitar **bloqueiam a mudança** — não deixa salvar enquanto houver futuro
  conflitante.
  → `futureConflicts` (o `Movimento.Scheduling.ImpactAnalysis`) é um **gate de escrita**: a
  tela mostra os conflitos e a mudança só salva depois que eles forem resolvidos. Nada é
  remarcado automaticamente.

---

## Fatia 8 — Configuração da clínica

- **D13 · Timezone.** v1 opera **só em horário de Brasília** (`America/Sao_Paulo`) e ele é
  **imutável** após o cadastro.
  → O relógio segue injetável (ADR-009), mas com **fuso único** na v1. Simplifica: não há
  rotina de reinterpretação de agendamentos históricos.

- **D14 · Feriado.** **Bloqueio absoluto** — feriado fecha a clínica para todos, sem exceção
  por profissional.
  → Simplifica a precedência de camadas do `dayPeriods`: a camada de feriado **não** tem
  override individual do profissional.

---

## Fatia 10 — Equipe

- **D15 · Profissional multi-clínica.** ~~**Não** — cada profissional pertence a uma única
  clínica.~~ **REVERTIDA (2026-07-11) → SIM.** Um profissional pode atender em **mais de uma
  clínica** e uma dona pode ter **mais de uma unidade** (modelo Vercel, [ADR-014](00-decisoes.md)).
  → Vínculo profissional ↔ clínica é **por-`Membership`**: 1 `User` global → N memberships → N
  registros `Professional` (um por schema). `strategy :context` **mantida**. Ver o bloco
  **"Identidade, tenant e acesso"** abaixo.

---

## Identidade, tenant e acesso  🆕 (2026-07-11)

Decisões do modelo Vercel, que destravam a fatia de identidade/tenant e alimentam
[ADR-014/015/016](00-decisoes.md).

- **D20 · Identidade global multi-tenant.** Um `User` é global e pertence a **vários** tenants,
  com **papel isolado por tenant**. Troca entre clínicas com um seletor (estilo Vercel).
  → `User` no schema público; `Membership` por-tenant carrega o papel; tenant ativo na sessão
  ([ADR-014](00-decisoes.md)).

- **D21 · "Unidade" = tenant próprio.** Cada unidade de uma mesma dona é uma **clínica/tenant
  isolado** (pacientes, equipe e catálogo separados); ela tem um `owner` em cada e troca entre
  elas. **Sem visão consolidada cross-tenant na v1** (relatório/faturamento agregando unidades
  → v2). Multi-unidade *dentro* de um mesmo tenant (endereços que compartilham dados) também é v2.

- **D22 · Papéis com capabilities embarcadas.** Quatro perfis **fixos**:
  `owner · admin · profissional · recepcao`. Não há papéis customizados; o mapa
  papel→o-que-pode é fixo em código ([ADR-016](00-decisoes.md)).

- **D23 · Owner obrigatório.** Todo tenant tem **≥1 owner**. O criador da clínica vira owner;
  só owner gerencia owners, faturamento e exclusão da clínica; **não se remove/rebaixa o último
  owner** ([ADR-016](00-decisoes.md)).

- **D24 · Login sem senha: Google + Magic Link.** Só **Google OAuth** e **Magic Link**; sem
  `hashed_password`, sem reset/política de senha. Convite de membro = magic link para um
  `Membership` pendente ([ADR-015](00-decisoes.md)).

---

## Fatia 6 — Prontuário / LGPD  ⚠️ MUDANÇA DE ESCOPO

- **D16 · v1 NÃO tem prontuário.** Existe apenas a **ficha do paciente** (dados
  cadastrais/contato). **Todos os papéis visualizam** o paciente; o **profissional é
  somente-leitura** na ficha.

### Consequências (precisam de revisão de ADR e roadmap)

1. **Sem dado sensível de Art. 11 na v1.** Sem diagnóstico/tags clínicas, sem anexos/laudos,
   sem prontuário — a ficha carrega **dado pessoal comum** (nome, contato), não **categoria
   especial** da LGPD (Art. 11).

2. **O Gate G1 sai do caminho crítico da v1.** `AshCloak` (criptografia de campo),
   `field_policies` de campo sensível, `AshPaperTrail` de acesso a prontuário e o job de purga
   LGPD **não são pré-requisito de nenhuma fatia da v1**, porque não há dado sensível para
   proteger. Eles voltam **quando o prontuário entrar (v2)**.

3. **Contradiz o ADR-007.** O ADR-007 trata o prontuário como requisito v1. Esta decisão
   **exige um novo ADR** (ou revisão do ADR-007) rebaixando prontuário/LGPD-Art.11 para v2, e
   uma revisão da **Fatia 6 e do Gate G1** no [08-roadmap.md](08-roadmap.md). *(Pendência
   registrada — ver "A resolver" abaixo.)*

4. **Retenção/purga:** detalhar na micro-sessão da Fatia 6 (agora v2).

### ⚠️ Tensão resolvida — `fila.obs` é operacional (ver D19)

O protótipo põe **queixa clínica na fila** (`fila.obs`). Optou-se por **`fila.obs`
operacional (não-clínica)** — ver **D19** abaixo — então a fila **não** reintroduz dado
sensível e nenhuma proteção de campo entra na Fatia 4.

---

## Fatia 6 (revisitada) — Decisões da ficha (fechadas em 2026-07-11)

As três sub-decisões que o D16 deixou em aberto (escopo da ficha, cifra do CPF, natureza da
`fila.obs`) foram respondidas pelo usuário. Elas **destravam o schema do `Patient`**.

- **D17 · Ficha completa.** A ficha da v1 inclui **todos os campos do cadastro** do modelo
  `Patient` ([01 §4.6](01-dominio-ash.md)): identificação (nome, nome social, CPF, RG, gênero,
  estado civil, nascimento), contato (tel, e-mail), endereço completo, contato de emergência
  (nome/parentesco/tel + responsável), ocupação (profissão/empresa), comercial/convênio
  (`atend_tipo`, convênio, carteirinha, validade) e **encaminhamento médico (`medico`/`crm`)**.
  → **Consequência (opção A escolhida):** como `medico`/`crm` (e `carteirinha`) são
  **sensíveis**, a ficha v1 **volta a carregar dado sensível**. Entram **`field_policies`** no
  `Patient` (profissional só-leitura na ficha; encaminhamento médico restrito a admin/membro).
  Isso **não** traz AshCloak nem o resto do Gate G1 — só o bloco de field policies. Refina o
  D16: a v1 **não** fica 100% livre de dado sensível.

- **D18 · CPF sem cifra na v1.** O CPF é armazenado como **texto** (protegido por policies de
  acesso), **sem AshCloak** e sem índice cego obrigatório. A busca por documento opera direto
  sobre a coluna. A cifra do CPF fica para **v2**, junto do prontuário.
  → Schema do `Patient` **sem** `cpf` `sensitive?`/`AshCloak` e **sem** `cpf_hash` como
  pré-requisito. O doc [01 §4.6](01-dominio-ash.md) (que modelava CPF cifrado + índice cego)
  deve ser sincronizado.

- **D19 · `fila.obs` operacional.** A observação da fila é **operacional (não-clínica)** —
  logística ("prefere manhã", "retorno"), nunca queixa clínica. **Não** recebe proteção de
  campo.
  → Schema da fila com `obs` como texto comum. Nenhuma field policy na Fatia 4 por causa da
  fila.

**Estado após D17–D19:** o schema do `Patient` está **destravado**. O único resíduo de LGPD na
v1 é o par `field_policies` sobre `medico`/`crm` (D17/opção A). Próximo passo concreto: andaime
da Fatia 0 ([08 §2](08-roadmap.md)).

---

## A resolver (pendências abertas por esta sessão)

| Pendência | Origem | Quando |
|---|---|---|
| Novo ADR rebaixando prontuário/LGPD-Art.11 para v2; revisar ADR-007, Fatia 6 e Gate G1 | D16 | Antes de reescrever a Fatia 6 no roadmap |
| ~~Natureza de `fila.obs`~~ → **resolvido (D19): operacional** | D16 / Fatia 4 | ✅ 2026-07-11 |
| ~~Escopo da ficha (inclui médico/CRM? CPF cifra?)~~ → **resolvido (D17 ficha completa + opção A; D18 CPF sem cifra)** | D16 | ✅ 2026-07-11 |
| Sincronizar doc 01 §4.6: remover cifra/índice cego do CPF (D18); adicionar `field_policies` em `medico`/`crm` (D17) | D17/D18 | Antes do schema do `Patient` |
| Mapa fino campo × papel do prontuário e política de retenção | Fatia 6 (v2) | Micro-sessão da Fatia 6 |

---

## Ainda v2 (confirmado, não decidir por palpite)

Sem mudança em relação ao roadmap §5 e ao 00: faturamento/convênio/nota fiscal, repasse ao
profissional (campos banco/PIX/remuneração coletados e não lidos), salas/equipamentos como
recurso com capacidade, multi-unidade dentro da mesma clínica. Soma-se a eles agora o
**prontuário completo + LGPD Art. 11** (D16).
