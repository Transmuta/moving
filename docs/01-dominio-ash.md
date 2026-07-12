# Domínio Ash — recursos, ações e a primeira migration

Este é o documento de proveniência do modelo de dados do Movimento. Os demais
documentos do conjunto apontam para cá como fonte de verdade da modelagem: os nomes de
recurso, os enums, as ações nomeadas e — sobretudo — a **decisão de multitenancy** (§2)
que a arquitetura (`04-arquitetura.md` §7.1), a observabilidade (`05`) e a segurança
(`06`) citam como "definida em 01".

## Como ler este documento

**Proveniência.** Toda regra de negócio referencia a linha do protótipo
(`interface/Movimento.dc.html`, ADR-001) de onde vem. As linhas foram conferidas com
`sed`/`grep` no arquivo real antes de escritas. Onde o texto diz "verificado em `:NNN`",
o conteúdo daquela linha foi aberto.

**Relógio congelado.** O protótipo congela o tempo: `hoje()` retorna a string literal
`'2026-06-25'` (verificado em [`:1098`](../interface/Movimento.dc.html#L1098)) e o "agora"
é a constante `NOW = 702` (11:42), embutida em `filaVagas`
([`:2533`](../interface/Movimento.dc.html#L2533)). Nenhuma ação de domínio aqui lê o
relógio do sistema: o tempo entra pelo escopo da ação, resolvido no timezone da clínica
(ADR-009). Onde uma regra depende de "hoje"/"já começou", isso está anotado.

**Marcação de API não-verificada.** Não existe projeto Elixir compilado neste repositório.
Todo bloco que usa API de biblioteca escrita de memória (`AshCloak`, `AshPaperTrail`,
`AshAuthentication`, `AshJsonApi`, `Ash.Type.Enum`, blocos `multitenancy`/`global?`,
`FilterCheck`, `Oban`) traz o comentário `# NAO-VERIFICADO: confirmar contra hexdocs ao
scaffoldar`. O que está autorizado pelas regras do repositório
(`.claude/rules/ash.md`, `.claude/rules/ash_postgres.md`) — `policies`, `field_policies`,
`aggregates`, `calculations`, `manage_relationship`, `strategy :attribute` (tenancy por
`clinic_id`, ADR-017) — é afirmado sem marca.

---

## 1. Domínios (bounded contexts)

Sete domínios Ash. A fronteira segue a coesão de invariantes, não a tela: `Scheduling`
concentra tudo que a *exclusion constraint* de não-sobreposição toca; `Records` concentra
tudo que a LGPD Art. 11 toca.

| Domínio | Recursos | Escopo de tenant |
|---|---|---|
| `Movimento.Accounts` | `User`, `Clinic`, `Membership` | **global** (registry de tenants + login) |
| `Movimento.Directory` | `Professional`, `AppointmentType`, `PriceVersion` | por-tenant |
| `Movimento.Scheduling` | `Appointment`, `Attendance`, `ClinicHours`, `ProfessionalHours`, `ScheduleException`, `SlotHold` | por-tenant |
| `Movimento.Packages` | `Package`, `PackageSchedule` | por-tenant |
| `Movimento.Waitlist` | `WaitlistEntry`, `AvailabilityRule` | por-tenant |
| `Movimento.Records` | `Patient`, `Attachment`, `ClinicalTag`, `Consent` | por-tenant |
| `Movimento.Reporting` | modelos de leitura / snapshots (§4.7) | por-tenant |

`ProfessionalHours` é um recurso que o protótipo não tinha como entidade separada — ele
resolve a sobrecarga de significado de `prof.avail` (correção **g**, §5). Ele vive em
`Scheduling` porque alimenta o motor de disponibilidade, junto de `ClinicHours` e
`ScheduleException`.

---

## 2. Multitenancy — a decisão

**Decisão: `strategy :attribute` (coluna `clinic_id`) do AshPostgres** ([ADR-017](00-decisoes.md)).
Uma tabela única por recurso por-tenant, com a coluna `clinic_id`; o Ash injeta
`WHERE clinic_id = <tenant ativo>` em toda query e preenche `clinic_id` na criação.
`User`, `Clinic` e `Membership` seguem **globais** (schema público, **sem** bloco
`multitenancy`). *(Histórico: a v1 começou em `strategy :context` — schema-por-tenant — e
migrou para `:attribute` em [ADR-017](00-decisoes.md), enquanto o custo era mínimo. A tabela
abaixo é a comparação que embasou a troca.)*

O AshPostgres oferece duas estratégias (`.claude/rules/ash_postgres.md`): `strategy
:context` (schema-por-tenant) e `strategy :attribute` (uma coluna `clinic_id` em cada
linha, uma tabela só). A escolha toca todo índice, toda policy e a garantia de
não-sobreposição. Os fatores concretos:

| Fator | `:context` (schema-por-tenant) | `:attribute` (`clinic_id`) — **escolhido** |
|---|---|---|
| **Custo de migration** | Maior: cada migration roda em N schemas (`--tenants`, `all_tenants/0`, `tenant_migrations`). | **Menor: uma migration, uma tabela.** Sem provisionar schema no onboarding. |
| **Visão consolidada cross-tenant** | Atravessa schemas; difícil (empurrada p/ v2). | **Query normal** — a dona vê as unidades somadas; viabiliza a v1. |
| **Observabilidade** | O tenant vem do `search_path`, não de uma coluna — complica o span do OTel. | Tenant é atributo/coluna — trivial de anexar ao span. |
| **Nº esperado de clínicas** | Pequeno; poucos schemas é barato. | Escala para muitos tenants (não é gargalo aqui). |
| **Dado de saúde (LGPD Art. 11)** | Isolamento **físico**: clínicas distintas jamais compartilham tabela. | Isolamento **lógico**: todo dado convive na mesma tabela, filtrado por `clinic_id`. |
| **Risco de IDOR entre tenants** | Estruturalmente baixo: a query roda dentro do schema. | Real, porém **contido pelo Ash** (auto-filtra e exige tenant nos recursos por-atributo). Escapes: query manual via Repo/Ecto, `authorize?: false` sem tenant. Mitigado por teste de IDOR obrigatório ([06 §6](06-seguranca-e-lgpd.md)). |
| **Restore/exclusão de UMA clínica** | Trivial: `pg_dump`/`drop` de um schema. | DELETE/extração por `clinic_id`, cuidando das FKs. |
| **Exclusion constraint da agenda** (`04` §7.1) | Naturalmente por-clínica (uma tabela por schema). | **Continua correta sem `clinic_id`** no nosso modelo: `Professional` é por-tenant, então `professional_id` é único globalmente e a sobreposição já é por-clínica. `clinic_id` na constraint fica como defesa-em-profundidade opcional. |

O que decidiu a troca: o custo de migration (único ponto fraco real do `:attribute`) some,
e em troca ganhamos **visão consolidada cross-tenant** (alinhada ao owner multi-unidade do
[ADR-014](00-decisoes.md)) e ops mais simples. O preço — isolamento lógico em vez de físico —
é pago com três disciplinas: **(1)** nunca ler dado por-tenant fora do Ash; **(2)** um **teste
de IDOR obrigatório no CI** (injetar `clinic_id` não vaza); **(3)** `clinic_id` como 1ª coluna
dos índices sensíveis ([§9](#9-índices)). Como só existia um recurso por-tenant (`Professional`)
quando a decisão foi tomada, a troca custou quase nada.

```elixir
# Recurso por-tenant (padrão para Directory, Scheduling, Packages, Waitlist, Records).
# VERIFICADO contra o código (Api.Directory.Professional).
multitenancy do
  strategy :attribute
  attribute :clinic_id
end

postgres do
  table "appointments"
  repo Api.Repo
end

relationships do
  # clinic_id é a coluna de tenant (FK -> clinics.id).
  belongs_to :clinic, Api.Accounts.Clinic, allow_nil?: false
end
```

```elixir
# Recursos GLOBAIS (Accounts: User, Clinic, Membership): vivem no schema público e
# NÃO levam bloco `multitenancy` nenhum. VERIFICADO: `strategy :context, global? true`
# fazia o AshPostgres criar a tabela DENTRO de cada schema de tenant (duplicada) — errado.
postgres do
  table "users"
  repo Api.Repo
end
```

**Consequência para o resto do conjunto.** Sem `manage_tenant`, sem `Repo.all_tenants/0`,
sem `tenant_migrations` — um único conjunto de tabelas no schema público. `04` §7.1 mantém a
constraint sem `clinic_id` (ver a nuance na tabela). `06` §6 troca a "segurança estrutural"
do schema por policies de tenant + o teste de IDOR obrigatório. `05` anexa o `clinic_id`
como atributo de span diretamente.

---

## 3. Enums (`Ash.Type.Enum`)

Cada enum fechado vira um módulo `Ash.Type.Enum`. Os valores abaixo foram **contados no
protótipo**, não presumidos.

```elixir
# NAO-VERIFICADO: confirmar a macro `use Ash.Type.Enum, values: [...]` do Ash 3.x

# Ciclo de vida do slot de agendamento.
# 6 valores, verificados em statusMeta [:810]-[:818].
defmodule Movimento.Scheduling.AppointmentStatus do
  use Ash.Type.Enum,
    values: [:agendado, :confirmado, :em_atendimento, :concluido, :faltou, :cancelado]
end

# Desfecho de presença POR PARTICIPANTE (correção d, §5). Recurso novo Attendance.
# `prevista` = ainda vai acontecer; os desfechos espelham concluido/faltou/cancelado do slot.
defmodule Movimento.Scheduling.AttendanceStatus do
  use Ash.Type.Enum, values: [:prevista, :concluida, :faltou, :cancelada]
end

# Estado do pacote. 4 valores PERSISTIDOS: ativo/pausado/concluido nos dados-semente
# [:117]-[:124], 'cancelado' em cancelarPkg. 'concluido' NÃO é derivado — além dos dados-semente,
# é produzido em runtime por archivePkg [:576] (ação :archive, §4.4). O 'renovado' do protótipo
# ([:362]) NÃO existe na produção:
# não há renovação — o total de sessões é editável a qualquer momento (ADR-011).
defmodule Movimento.Packages.PackageStatus do
  use Ash.Type.Enum, values: [:ativo, :pausado, :cancelado, :concluido]
end

# Estado de uma sessão dentro da série do pacote.
# 6 valores. Cinco verificados nos dados-semente [:117]-[:121]:
# concluida, feriado, falta, proxima, segurada (segurada = pacote pausado, fora da agenda).
# :agendada é DERIVADO por pkgSessions [:391] (fallback de toda sessão futura agendada/confirmada
# após a próxima; renderizado em pkgDot [:400] e na legenda [:642]). :feriado só vem das arrays
# de seed, não da derivação — o conjunto real é a união (6), igual ao mapa de pkgEstadoLabel [:385].
defmodule Movimento.Packages.SessionState do
  use Ash.Type.Enum, values: [:proxima, :agendada, :concluida, :falta, :feriado, :segurada]
end

# Tipo de atendimento comercial do paciente. Verificado no seletor [:2146]
# ([['particular','Particular'],['reembolso','Reembolso'],['convenio', …]]) e no seed [:107].
defmodule Movimento.Records.AttendanceType do
  use Ash.Type.Enum, values: [:particular, :reembolso, :convenio]
end

# Prioridade na fila de espera. 4 valores no <select> de cadastro [:2230] e no filtro da fila
# [:1457]; os seeds [:163]-[:166] exercitam apenas 3 (baixa não aparece na semente).
defmodule Movimento.Waitlist.Priority do
  use Ash.Type.Enum, values: [:urgente, :alta, :normal, :baixa]
end

# Janela de preferência de horário na fila. Verificado no seed [:163]-[:165].
defmodule Movimento.Waitlist.TimeWindow do
  use Ash.Type.Enum, values: [:manha, :tarde, :qualquer]
end

# Forma de uma regra de disponibilidade na fila. Verificado no seed [:163]:
# tipo 'semana' (dows recorrentes) | 'data' (data específica).
defmodule Movimento.Waitlist.RuleType do
  use Ash.Type.Enum, values: [:semana, :data]
end

# Papel do membro por tenant (RBAC). ADR-016: 4 perfis fixos, capabilities embarcadas.
# `owner` é novo (dona da clínica; >=1 por tenant). `recepcao` = o `membro` do protótipo
# [:203]-[:207] (roleMeta [:2408] descrevia 3 papéis; owner é acréscimo do modelo Vercel).
defmodule Movimento.Accounts.Role do
  use Ash.Type.Enum, values: [:owner, :admin, :profissional, :recepcao]
end

# ADR-016: as capabilities são um MAPA FIXO EM CÓDIGO (não dado de tenant, não papel
# customizável). As policies leem deste módulo; a UI usa `can_*?` do code interface.
# NAO-VERIFICADO: forma exata do módulo ao scaffoldar — o essencial é ser estático.
defmodule Movimento.Accounts.Capabilities do
  # owner ⊃ admin ⊃ recepcao (agenda de todos); profissional é um recorte (só a própria).
  #   owner:        tudo + :manage_billing, :delete_clinic, :manage_owners
  #   admin:        :manage_members (exceto owners), :manage_config, :manage_all_agendas, :view_reports
  #   recepcao:     :manage_all_agendas (sem :manage_config)
  #   profissional: :manage_own_agenda, :read_own_patients
  # def can?(role, capability), do: capability in for_role(role)
end

# Situação do acesso do membro. Verificado no seed [:206] (pendente) / [:203] (ativo).
defmodule Movimento.Accounts.MemberStatus do
  use Ash.Type.Enum, values: [:ativo, :pendente]
end

# Tipo de exceção de data (feriado da clínica OU folga do profissional — correção f).
# 2 valores verificados: holidays [:169]-[:170] e prof.exc [:66]-[:68] usam
# tipo 'fechado' (dia inteiro fechado) | 'horario' (horário especial via `periods`).
defmodule Movimento.Scheduling.ExceptionKind do
  use Ash.Type.Enum, values: [:fechado, :horario]
end

# Vínculo contratual do profissional. Verificado no seed [:53]-[:57]:
# 'PJ' | 'CLT' | 'Autônomo'.
defmodule Movimento.Directory.ContractType do
  use Ash.Type.Enum, values: [:pj, :clt, :autonomo]
end
```

> Nota sobre `atendTipo` como "público". O enum `AttendanceType` é categoria comercial e
> não é dado sensível (concordando com `06` §1.1, que o classifica público). Já `convenio`,
> `carteirinha`, `medico`, `crm` que o acompanham **são** PII/sensível (§6).

---

## 4. Recursos

Convenções: tipos são tipos Ash; `allow_nil?` explícito onde importa; `timestamps()`
subentendido em todos. Ações são **nomeadas de domínio**, casando com o catálogo de
`09-contrato-api.md` §3 (divergências no Apêndice A).

### 4.1 `Movimento.Accounts` — global

#### `User` — identidade de login

Separado de `Professional`: o seed distingue "membros da organização (acesso/login)" de
"profissionais", e nota que Thiago (p4) e Carla (p5) são profissionais **sem** acesso
([`:201`](../interface/Movimento.dc.html#L201)). **`User` é a identidade global**
(ADR-014): uma pessoa = um `User`, no schema público, ligada a N clínicas por N
`Membership`s. Não há `Professional` global — o profissional é por-schema e é alcançado a
partir do `User` via `Membership.professional_id`.

```elixir
# ADR-015: SEM senha. Estratégias = Google OAuth + Magic Link.
# NAO-VERIFICADO: AshAuthentication (oauth2/google, magic_link, tokens) — confirmar contra hexdocs
defmodule Movimento.Accounts.User do
  use Ash.Resource,
    domain: Movimento.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id
    attribute :nome, :string, allow_nil?: false
    attribute :email, :ci_string, allow_nil?: false   # case-insensitive
    # SEM hashed_password (ADR-015). last_sign_in_at atualizado pela sessão (ver nota `acesso`).
  end

  # authentication do strategies do magic_link ... ; oauth2 :google ... end; tokens do ... end end

  identities do
    identity :unique_email, [:email]
  end

  relationships do
    has_many :memberships, Movimento.Accounts.Membership
  end
end
```

Ações (delegadas à AshAuthentication, ADR-015): `:sign_in_with_magic_link` /
`:request_magic_link` e o registro/sign-in via **Google OAuth**. **Não** há
`sign_in_with_password` nem reset de senha. Casam com o request de magic link, os callbacks
e `GET /auth/me` do [09 §8](09-contrato-api.md). Primeiro acesso via magic link/Google
cria (ou vincula) o `User` pelo e-mail.

#### `Clinic` — o tenant

Reúne o que o protótipo mantinha como singletons globais (`hours`, `holidays`, `settings`,
[`:172`](../interface/Movimento.dc.html#L172), [`:270`](../interface/Movimento.dc.html#L270))
— agora escopado, um por clínica.

```elixir
defmodule Movimento.Accounts.Clinic do
  # ... use Ash.Resource, domain: Movimento.Accounts, data_layer: AshPostgres.DataLayer
  attributes do
    uuid_primary_key :id
    attribute :nome, :string, allow_nil?: false
    # ADR-009: timezone canônico da clínica. "Hoje"/"já começou" resolvem aqui.
    attribute :timezone, :string, allow_nil?: false, default: "America/Sao_Paulo"
    # settings do protótipo [:270]: {capPilates:4, noShowConsome:false, slot:15}
    attribute :cap_turma_padrao, :integer, allow_nil?: false, default: 4
    attribute :falta_consome_padrao, :boolean, allow_nil?: false, default: false
    attribute :slot_minutos, :integer, allow_nil?: false, default: 15
  end

  actions do
    defaults [:read]
    create :onboard          # cria a clínica (tenancy por atributo, ADR-017: sem schema)
    update :update_settings
  end
end
```

#### `Membership` — vínculo pessoa↔clínica com papel

Corresponde a `membros` ([`:203`](../interface/Movimento.dc.html#L203)) e é a **peça central
do modelo Vercel** (ADR-014): liga um `User` global a uma `Clinic`, com **papel isolado por
clínica**. A mesma pessoa tem **N memberships** — é assim que um profissional atende em mais
de uma clínica e uma dona tem mais de uma unidade. O vínculo com um `Professional` (que vive
**dentro** do schema do tenant) é um UUID mole (`professional_id`), sem FK entre schemas — e
é **por-membership**, então há um `Professional` distinto por clínica.

```elixir
defmodule Movimento.Accounts.Membership do
  # ... global? true (ver §2)
  attributes do
    uuid_primary_key :id
    attribute :papel, Movimento.Accounts.Role, allow_nil?: false, default: :recepcao
    attribute :status, Movimento.Accounts.MemberStatus, allow_nil?: false, default: :pendente
    # opcional e único: aponta um membro `:profissional` ao seu Professional no tenant.
    attribute :professional_id, :uuid, allow_nil?: true
  end

  relationships do
    belongs_to :user, Movimento.Accounts.User, allow_nil?: false
    belongs_to :clinic, Movimento.Accounts.Clinic, allow_nil?: false
  end

  identities do
    identity :unique_user_per_clinic, [:user_id, :clinic_id]
    identity :unique_professional_link, [:clinic_id, :professional_id]  # profId único por clínica
  end

  actions do
    defaults [:read]
    create :invite            # cria pendente (09: POST /members/invite ← saveMembro [:2500])
    update :update            # papel/vínculo (09: PATCH /members/:id)
    update :accept_invite     # pendente → ativo (via magic link/Google, ADR-015)
    destroy :revoke_access    # 09: DELETE /members/:id ← [:2509]
  end

  # ADR-016 — invariante "≥1 owner por tenant". `update` (rebaixar owner) e
  # `revoke_access` (remover owner) falham se deixariam a clínica sem nenhum owner.
  # NAO-VERIFICADO: validação atômica que conta owners restantes no tenant ao scaffoldar.
  # validations do
  #   validate {Movimento.Checks.NotLastOwner, []}, on: [:update, :destroy]
  # end
end
```

> **Owner (ADR-016).** O `onboard` da `Clinic` cria, na mesma transação, o `Membership`
> `owner` do criador. Só `owner` promove/rebaixa owner; `admin` gerencia os demais membros,
> **exceto** owners. A gestão de owners e o faturamento são capabilities exclusivas de `owner`.

> **`acesso` (último acesso) — não modelado como atributo de domínio.** Cada membro do seed
> carrega um `acesso` (string de "último acesso"/login,
> [`:203`](../interface/Movimento.dc.html#L203)-[`:207`](../interface/Movimento.dc.html#L207);
> `saveMembro` o inicializa `acesso:null`, [`:2504`](../interface/Movimento.dc.html#L2504)) que
> **não** é persistido nem em `User` nem em `Membership`. É dado apresentacional/vestigial —
> nunca lido nem renderizado na UI — e conceitualmente um dado global de sessão/autenticação. Se
> mantido, mora no `User` como `:ultimo_acesso`/`last_sign_in_at` (atualizado pela estratégia de
> sessão do AshAuthentication), **nunca** no `Membership` (que é o vínculo por-clínica). A
> afirmação "Corresponde a `membros`" acima omite deliberadamente este único campo da semente.

### 4.2 `Movimento.Directory`

#### `Professional`

Seed em [`:52`](../interface/Movimento.dc.html#L52)-[`:57`](../interface/Movimento.dc.html#L57).
Dados bancários (`banco`/`agencia`/`conta`/`pix`) do formulário
([`:3130`](../interface/Movimento.dc.html#L3130)) são segredo (§6, `06` §1.4).

```elixir
defmodule Movimento.Directory.Professional do
  # ... por-tenant; authorizers: [Ash.Policy.Authorizer]; extensions: [AshCloak]
  attributes do
    uuid_primary_key :id
    attribute :nome, :string, allow_nil?: false
    # Identificação pessoal (renderProfForm seção 'ident' [:3007], inputs [:3076]-[:3084]).
    attribute :nome_exibicao, :string           # como aparece na agenda (nomeExib [:3076])
    attribute :nascimento, :date                # nasc [:3078]
    attribute :cpf, :string, sensitive?: true   # PII cifrado — mesmo tratamento do Patient (§6)
    attribute :rg, :string, sensitive?: true    # PII cifrado (§6)
    attribute :estado_civil, :string            # [:3084]
    # Contato & localização (seção 'contato' [:3008], inputs [:3090]-[:3107]); seed [:53]-[:57].
    attribute :tel, :string                     # [:3090]
    attribute :email, :string, sensitive?: true # usuário de login do sistema [:3091]
    attribute :cep, :string
    attribute :endereco, :string
    attribute :numero, :string
    attribute :complemento, :string
    attribute :bairro, :string
    attribute :cidade, :string                  # localização — distinto de registro_uf (conselho)
    attribute :uf, :string
    # Contato de emergência do profissional (dado de TERCEIRO, [:3106]-[:3107]).
    attribute :emergencia_nome, :string, sensitive?: true
    attribute :emergencia_tel, :string, sensitive?: true
    # Profissão/formação (seção 'tecnicos' [:3009], select [:3114]); seed profissao [:53].
    attribute :profissao, :string
    attribute :sub, :string          # especialidade curta ("Ortopedia")
    attribute :crefito, :string, allow_nil?: false
    attribute :registro_uf, :string
    attribute :ano_conclusao, :string
    attribute :especialidades, {:array, :string}, default: []
    attribute :vinculo, Movimento.Directory.ContractType
    # Índice de cor da agenda (ci) — editável e persistido na seção "Cor & status" (savePayload
    # [:3055]); consumido por profColor. Coerente com 06 §1.1 (público) e 03 §4.5.
    attribute :cor_indice, :integer             # ci [:53]/[:3012]
    attribute :ativo, :boolean, allow_nil?: false, default: true
    # correção g: booleano explícito que decide o SIGNIFICADO das horas semanais (§4.3).
    attribute :segue_horario_clinica, :boolean, allow_nil?: false, default: true
    # Dados PJ (seção 'contrato' [:3010], inputs [:3127]/[:3128]/[:3137]); condicionais a vínculo=PJ.
    attribute :razao_social, :string                 # razaoSocial [:3127]
    attribute :cnpj, :string, sensitive?: true       # PII PJ / segredo (06 §1.4)
    attribute :conta_tipo, :string, sensitive?: true # contaTipo [:3137] — segredo bancário (06 §1.4)
    # Segredos bancários (ADR-007, cifrados — ver §6).
    attribute :banco, :string, sensitive?: true
    attribute :agencia, :string, sensitive?: true
    attribute :conta, :string, sensitive?: true
    attribute :pix, :string, sensitive?: true
    # remuneracao [:3140] NÃO modelada: repasse ao profissional é escopo v2 (00-decisoes).
  end

  relationships do
    has_many :appointments, Movimento.Scheduling.Appointment
    has_many :weekly_hours, Movimento.Scheduling.ProfessionalHours
    has_many :exceptions, Movimento.Scheduling.ScheduleException  # folgas do profissional
  end

  actions do
    defaults [:read]
    create :create           # 09: POST /professionals (admin)
    update :update           # 09: PATCH /professionals/:id (campos bancários por field policy)
    update :deactivate
  end
end
```

#### `AppointmentType` — **sem `preco`** (correção a)

Seed [`:69`](../interface/Movimento.dc.html#L69)-[`:74`](../interface/Movimento.dc.html#L74):
`{id, nome, dur, cor, icon, grupo, cap, sigla}`. **Não há campo de preço no tipo.** O preço
está *hardcoded no relatório*: `const price={t1:180,t2:120,t3:130,t4:70,t5:90};`, verificado
em [`:3339`](../interface/Movimento.dc.html#L3339). Modelamos preço com histórico de
vigência num recurso separado (`PriceVersion`).

```elixir
defmodule Movimento.Directory.AppointmentType do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :nome, :string, allow_nil?: false
    attribute :sigla, :string           # 'AVA','SES','RPG','PIL','REA'
    attribute :duracao_minutos, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :cor, :string
    attribute :icon, :string
    attribute :grupo, :boolean, allow_nil?: false, default: false   # turma?
    attribute :capacidade, :integer, allow_nil?: true               # só quando grupo (cap [:341])
  end

  validations do
    # invariante: capacidade só faz sentido em turma (§8). cap default vem de settings [:341].
    validate present(:capacidade), where: [attribute_equals(:grupo, true)]
    validate absent(:capacidade),  where: [attribute_equals(:grupo, false)]
  end

  relationships do
    has_many :price_versions, Movimento.Directory.PriceVersion
  end

  calculations do
    # preço vigente hoje (resolvido no timezone da clínica, ADR-009)
    calculate :preco_vigente, :decimal, Movimento.Directory.Calculations.PrecoVigente
  end

  actions do
    defaults [:read]
    create :create           # 09: POST /appointment-types (admin)
    update :update
    destroy :destroy
  end
end
```

#### `PriceVersion` — preço com vigência (correção a)

Substitui a tabela hardcoded [`:3339`](../interface/Movimento.dc.html#L3339). Uma linha por
faixa de vigência (e, opcionalmente, por convênio — dimensão em aberto, ver Apêndice B).

```elixir
defmodule Movimento.Directory.PriceVersion do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :valor, :decimal, allow_nil?: false, constraints: [greater_than: 0]
    attribute :vigencia_inicio, :date, allow_nil?: false
    attribute :vigencia_fim, :date, allow_nil?: true    # nil = vigente
    # PRODUTO EM ABERTO (00-decisoes): preço varia por convênio? nil = tabela particular base.
    attribute :convenio, :string, allow_nil?: true
  end

  relationships do
    belongs_to :appointment_type, Movimento.Directory.AppointmentType, allow_nil?: false
  end

  actions do
    defaults [:read]
    create :set_price        # abre nova vigência, fecha a anterior (vigencia_fim)
  end
end
```

### 4.3 `Movimento.Scheduling`

#### `Appointment` — o slot

O protótipo mistura, no mesmo objeto, o **slot** (profissional, horário, tipo, encaixe) e
a **presença** (`status`, `patientId`/`patientIds`). A correção **d** separa presença num
recurso filho (`Attendance`). O `Appointment` guarda o ciclo de vida do slot; os desfechos
por paciente vivem em `Attendance`.

```elixir
defmodule Movimento.Scheduling.Appointment do
  # ... por-tenant; authorizers: [Ash.Policy.Authorizer]; extensions: [AshPaperTrail]
  attributes do
    uuid_primary_key :id
    # tempo absoluto (não minuto-do-dia como no protótipo). Alimenta a tstzrange da constraint.
    attribute :starts_at, :utc_datetime, allow_nil?: false
    attribute :ends_at, :utc_datetime, allow_nil?: false
    attribute :status, Movimento.Scheduling.AppointmentStatus, allow_nil?: false, default: :agendado
    # encaixe: sobreposição DELIBERADA. checkConflict retorna null p/ encaixe [:835] e ignora
    # encaixes existentes [:837]. É o predicado da exclusion constraint (04 §7.1).
    attribute :encaixe, :boolean, allow_nil?: false, default: false
    # locking otimista (04 §7.3): reschedule exige a versão lida.
    attribute :version, :integer, allow_nil?: false, default: 1
    attribute :cancel_reason, :string, allow_nil?: true
  end

  relationships do
    belongs_to :professional, Movimento.Directory.Professional, allow_nil?: false
    belongs_to :appointment_type, Movimento.Directory.AppointmentType, allow_nil?: false
    has_many :attendances, Movimento.Scheduling.Attendance
    belongs_to :package, Movimento.Packages.Package, allow_nil?: true  # sessão de série
  end

  aggregates do
    count :participantes, :attendances do
      filter expr(status != :cancelada)
    end
  end

  actions do
    defaults [:read]

    # 09: POST /appointments ← createAppt [:1048]. Cria o slot + a(s) Attendance(s).
    create :schedule do
      argument :patient_ids, {:array, :uuid}   # 1 = individual; N = turma
      argument :from_waitlist_id, :uuid, allow_nil?: true
      # manage_relationship materializa uma Attendance por paciente
      change manage_relationship(:patient_ids, :attendances, type: :create)
    end

    # 09: POST /appointments/:id/reschedule ← locking otimista (04 §7.3)
    update :reschedule do
      argument :expected_version, :integer, allow_nil?: false
      change atomic_update(:version, expr(version + 1))
    end

    update :mark_confirmed    # 09: /confirm  → status :confirmado
    update :mark_in_progress  # 09: /start    → status :em_atendimento
    update :cancel            # 09: /cancel   → status :cancelado; apaga do índice da constraint

    # complete/no_show/justify — efeito de consumo de pacote (§4.4 e 09 §2.2).
    # Individual: aplica à única Attendance. Turma: exige patient_id (correção d).
    update :mark_completed    # 09: /complete
    update :mark_no_show      # 09: /no_show
    update :justify_absence   # 09: /justify_absence ← justificarFalta [:1121]

    # turma: 09 POST/DELETE /appointments/:id/participants
    update :add_participant
    update :remove_participant
  end
end
```

#### `Attendance` — presença por participante (correção d + e)

**A mudança central.** Hoje a turma tem status único: marcar `faltou` num bloco de grupo
pune todos os `patientIds` de uma vez (`justificarFalta` percorre
`a0.patientIds` e debita cada paciente,
[`:1123`](../interface/Movimento.dc.html#L1123)). Pior, o mapa **`pkgOf`**
(`{patientId → pkgId}`) permite que participantes da MESMA turma estejam em pacotes
DIFERENTES — mas `apptPkg` ([`:1110`](../interface/Movimento.dc.html#L1110)) só devolve o
**primeiro** pacote encontrado no laço `for` sobre as chaves de `pkgOf`
([`:1113`](../interface/Movimento.dc.html#L1113): `for(let k=0; …) { … if(pk) return
{pk,patient:p,ownerId:pid,pkgId}; }` — retorna no primeiro acerto). Consequência: o ajuste
em massa e o débito operam sobre **um dono só** e ignoram os demais em silêncio. Nenhum
outro documento do conjunto menciona `pkgOf` — é uma armadilha não catalogada.

`Attendance` resolve as duas: cada participante é uma linha, com seu **próprio**
`status` e seu **próprio** `package_id`. `pkgOf` deixa de existir — ele vira a coluna
`Attendance.package_id`. `apptPkg` deixa de "escolher o primeiro": cada `Attendance` sabe
seu pacote.

```elixir
defmodule Movimento.Scheduling.Attendance do
  # ... por-tenant; extensions: [AshPaperTrail] (acesso a prontuário auditado)
  attributes do
    uuid_primary_key :id
    attribute :status, Movimento.Scheduling.AttendanceStatus, allow_nil?: false, default: :prevista
    # substitui a.faltaJustificada [:1123] — agora por participante, não por bloco.
    attribute :falta_justificada, :boolean, allow_nil?: false, default: false
  end

  relationships do
    belongs_to :appointment, Movimento.Scheduling.Appointment, allow_nil?: false
    belongs_to :patient, Movimento.Records.Patient, allow_nil?: false
    # ANTES: a.pkgOf[patientId]. AGORA: a coluna que dissolve o mapa (correção e).
    belongs_to :package, Movimento.Packages.Package, allow_nil?: true
  end

  identities do
    identity :one_per_patient_per_appt, [:appointment_id, :patient_id]
  end

  actions do
    defaults [:read]
    create :create
    update :complete    # → :concluida  (debita pacote se punitivo, 09 §2.2)
    update :no_show     # → :faltou
    update :justify     # alterna falta_justificada (deixa de debitar / de contar)
    destroy :destroy
  end
end
```

> **Regra de consumo (wouldConsume, [`:1104`](../interface/Movimento.dc.html#L1104)).**
> "concluído sempre debita; falta debita conforme a falta punitiva do pacote
> (`pkgPunitivo`, [`:1103`](../interface/Movimento.dc.html#L1103)), a menos que a falta
> esteja justificada." No modelo novo, esse predicado avalia por `Attendance`, olhando
> `attendance.package.falta_punitiva` e `attendance.falta_justificada`.

#### `ClinicHours` — horário semanal da clínica

`hours` do protótipo ([`:172`](../interface/Movimento.dc.html#L172)): cada dia da semana é
uma lista de períodos (`[['08:00','12:00'],['13:00','18:00']]`); `null` = fechado. Uma linha
por dia-da-semana da clínica.

```elixir
defmodule Movimento.Scheduling.ClinicHours do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :dow, :integer, allow_nil?: false, constraints: [min: 0, max: 6]  # 0=dom
    # períodos como pares "HH:MM"; [] ou nil = fechado nesse dia.
    attribute :periods, {:array, {:array, :string}}, allow_nil?: false, default: []
  end

  identities do
    identity :one_per_dow, [:dow]   # implícito por-tenant (schema do tenant)
  end

  actions do
    defaults [:read]
    # 09: PATCH /clinic-hours — checagem prévia de futureConflicts [:864] antes de aplicar.
    update :update do
      argument :confirm, :boolean, default: false   # 2º request confirma (09 §3.5)
    end
  end
end
```

#### `ProfessionalHours` — a grade do profissional (correção g)

`prof.avail` tem **dois significados** conforme `followClinic`
(`profWeek`, [`:840`](../interface/Movimento.dc.html#L840)): se `followClinic !== false`,
`avail` guarda só **exceções por dia-da-semana** (um override, ou `null` = fechado naquele
dia), caindo no horário da clínica para os demais; se `followClinic === false`, `avail` é a
**grade inteira** do profissional. Verificado no seed: `profs[3].followClinic=false` com
uma grade completa ([`:64`](../interface/Movimento.dc.html#L64)), enquanto os demais têm
`followClinic=true, avail={}` ([`:61`](../interface/Movimento.dc.html#L61)).

Separamos em uma representação única e explícita: `Professional.segue_horario_clinica`
(§4.2) decide o *default*, e `ProfessionalHours` guarda o que difere, com um `modo`
explícito por dia-da-semana — nunca mais um mapa cujo sentido depende de outra flag.

```elixir
defmodule Movimento.Scheduling.ProfessionalHours do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :dow, :integer, allow_nil?: false, constraints: [min: 0, max: 6]
    # :herda   = usa o horário da clínica nesse dia (profWeek cai em hours[dow])
    # :custom  = usa `periods` deste registro
    # :fechado = profissional não atende nesse dia (o `null` do avail[dow])
    attribute :modo, :atom, allow_nil?: false, constraints: [one_of: [:herda, :custom, :fechado]]
    attribute :periods, {:array, {:array, :string}}, default: []
  end

  relationships do
    belongs_to :professional, Movimento.Directory.Professional, allow_nil?: false
  end

  identities do
    identity :one_per_prof_dow, [:professional_id, :dow]
  end
end
```

#### `ScheduleException` — feriado **ou** folga (correção f)

`holidays` da clínica ([`:169`](../interface/Movimento.dc.html#L169)) e `prof.exc`
([`:66`](../interface/Movimento.dc.html#L66)-[`:67`](../interface/Movimento.dc.html#L67))
têm a **mesma forma**: `{id, data, nome, tipo, periods}`, com `tipo ∈ {fechado, horario}`.
Um recurso, polimórfico pelo dono: `professional_id` nulo = feriado da clínica; preenchido =
folga/horário pontual do profissional. A precedência de `dayPeriods`
([`:854`](../interface/Movimento.dc.html#L854)) é: exceção de data da clínica *que fecha*
tranca o dia para todos; senão exceção do profissional; senão horário especial da clínica;
senão horário semanal.

```elixir
defmodule Movimento.Scheduling.ScheduleException do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :data, :date, allow_nil?: false
    attribute :nome, :string
    attribute :tipo, Movimento.Scheduling.ExceptionKind, allow_nil?: false  # :fechado | :horario
    attribute :periods, {:array, {:array, :string}}, default: []            # só quando :horario
  end

  relationships do
    # nil ⇒ exceção da clínica (feriado). preenchido ⇒ exceção do profissional (folga).
    belongs_to :professional, Movimento.Directory.Professional, allow_nil?: true
  end

  validations do
    validate present(:periods), where: [attribute_equals(:tipo, :horario)]
  end

  actions do
    defaults [:read]
    # 09: POST/DELETE /holidays (clínica) e a exceção do profissional; ambas acionam
    # futureConflicts [:864] → checagem prévia com `confirm` (09 §3.5).
    create :create do
      argument :confirm, :boolean, default: false
    end
    destroy :destroy
  end
end
```

#### `SlotHold` — reserva de vaga com TTL (recurso novo; `04` §7.2)

Corrige a corrida `offerVaga → createAppt` sem reserva (ADR-004; `offerVaga` só pré-preenche
um modal hoje, [`:2596`](../interface/Movimento.dc.html#L2596)). **Atenção à regra de DDL:**
`now()` é `STABLE`, não `IMMUTABLE`; a exclusion constraint de holds **não** pode ter
`WHERE expires_at > now()` (o Postgres recusa) — a expiração vive na DML, nunca na
constraint (`04` §7.2, item corrigido).

```elixir
defmodule Movimento.Scheduling.SlotHold do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :starts_at, :utc_datetime, allow_nil?: false
    attribute :ends_at, :utc_datetime, allow_nil?: false
    attribute :expires_at, :utc_datetime, allow_nil?: false   # TTL curto (5 min, 04 §7.2)
  end

  relationships do
    belongs_to :professional, Movimento.Directory.Professional, allow_nil?: false
    belongs_to :waitlist_entry, Movimento.Waitlist.WaitlistEntry, allow_nil?: false
    belongs_to :held_by, Movimento.Accounts.User, allow_nil?: false
  end

  actions do
    defaults [:read]
    # 09: POST /waitlist/:id/offer. ANTES de inserir, na MESMA transação, apaga holds
    # vencidos do profissional (DELETE ... WHERE expires_at <= now()) — em DML now() é válido.
    create :offer
    destroy :release
  end
end
```

```sql
-- 04 §7.2 (DDL correto): constraint SEM predicado de tempo; expiração via DML.
ALTER TABLE slot_holds
  ADD CONSTRAINT slot_holds_no_overlap
  EXCLUDE USING gist (
    professional_id                     WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  );
```

### 4.4 `Movimento.Packages`

#### `Package` — máquina de estados; `usadas` é aggregate (correção c); sem validade, sem renovação

Seed [`:117`](../interface/Movimento.dc.html#L117). A coluna `usadas` é **vestigial**: o
protótipo já deriva o consumo em `pkgUsadas`
([`:326`](../interface/Movimento.dc.html#L326): `pkgUsadas(pk){ return
this.pkgAppts(pk).reduce((n,a)=>n+(this.wouldConsume(a,a.status,pk)?1:0),0); }`) e
`pkgRemaining` ([`:327`](../interface/Movimento.dc.html#L327)). Logo `usadas` vira
**aggregate**, não coluna.

**Sem validade ([ADR-013](00-decisoes.md)/D6) e sem renovação ([ADR-011](00-decisoes.md)).** O
protótipo não tem validade real (o `pkgPause` inventa um `retomaEm = hoje + 21 dias` decorativo,
[`:554`](../interface/Movimento.dc.html#L554)), e a produção também não terá: o pacote vale até
as sessões acabarem. E **não há renovação**: o `total` de sessões é **editável, para mais ou
para menos, a qualquer momento** (via `add_session`/`remove_session`), sempre sobre o mesmo
pacote. Somem, em relação ao desenho anterior, o campo `validade_ate`, a relação `renovado_de` e
a ação `:renew`.

```elixir
defmodule Movimento.Packages.Package do
  # ... por-tenant; authorizers: [Ash.Policy.Authorizer]; extensions: [AshPaperTrail]
  attributes do
    uuid_primary_key :id
    attribute :nome, :string
    attribute :total, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :status, Movimento.Packages.PackageStatus, allow_nil?: false, default: :ativo
    # falta punitiva do pacote (pkgPunitivo [:1103]); nil ⇒ cai no default da clínica.
    attribute :falta_punitiva, :boolean, allow_nil?: true
    # base do código legível SIGLA-AAMM (pkgBaseCode [:379]). No protótipo `criado` [:117] é a
    # data da 1ª sessão não-feriado, NÃO o created_at da linha — por isso coluna própria, não inserted_at.
    attribute :data_inicio, :date, allow_nil?: true
    # SEM validade (ADR-013/D6) e SEM renovado_de/renew (ADR-011): total editável a qualquer momento.
  end

  relationships do
    belongs_to :patient, Movimento.Records.Patient, allow_nil?: false
    belongs_to :appointment_type, Movimento.Directory.AppointmentType, allow_nil?: false
    has_one :schedule, Movimento.Packages.PackageSchedule                  # a "grade"
    has_many :appointments, Movimento.Scheduling.Appointment               # a série
  end

  aggregates do
    # correção c: usadas derivado. Conta sessões que consomem (concluída sempre;
    # falta só se punitiva e não justificada) — a regra de wouldConsume [:1104] em SQL.
    # SIMPLIFICAÇÃO: quando falta_punitiva é nil, wouldConsume/pkgPunitivo [:1103] cai no default
    # da clínica (settings.noShowConsome ⇒ falta_consome_padrao). Esse ramo de fallback NÃO está
    # expresso abaixo — referenciar um setting de nível-clínica dentro do filtro de um aggregate é
    # não-trivial; a reconciliar ao scaffoldar (senão usadas é
    # subcontado quando falta_punitiva=nil e a clínica é punitiva).
    count :usadas, :appointments do
      filter expr(
        status == :concluido or
          (status == :faltou and exists(attendances, falta_justificada == false) and
             (parent(falta_punitiva) == true))
      )
    end
  end

  calculations do
    # clamp em 0, espelhando Math.max(0, total-usadas) de pkgRemaining [:327].
    calculate :restantes, :integer, expr(if total - usadas > 0 do total - usadas else 0 end)
    calculate :acabando, :boolean, expr(status == :ativo and restantes > 0 and restantes <= 2)
    # código legível SIGLA-AAMM: pkgSigla [:378] + AAMM de data_inicio (pkgBaseCode [:379]), com
    # desambiguação "·N" por paciente (pkgCode [:380]). É a chave da busca de pacotes [:2677].
    calculate :codigo, :string, Movimento.Packages.Calculations.PkgCode
  end

  actions do
    defaults [:read]
    create :create_with_series   # 09: POST /packages ← computeSerie [:1081]
    # SEM :renew (ADR-011). Ajustar o total é add_session/remove_session (abaixo), a qualquer momento.
    update :pause                # 09: /pause ← pkgPause [:553]; sessões futuras → segurada (fora da agenda)
    update :resume               # 09: /resume ← pkgResume [:561] (reprojeta p/ o futuro — correção do 09)
    update :cancel               # 09: /cancel ← cancelarPkg [:568]
    update :archive              # ← archivePkg [:576]; status → :concluido, habilitada quando done (pkgDone [:329])
    update :adjust_grade         # 09: PATCH /packages/:id/grade ← pkgSaveGrade [:578]
    update :bulk_adjust          # 09: /bulk_adjust ← applyMassaPacote [:1149] (escopo esta|proximas|todas)
    update :bulk_cancel          # 09: /bulk_cancel ← cancelarMassaPacote [:1174]
    # aumenta o total (materializa 1 sessão na próxima data da grade, pulando feriados);
    # REATIVA pacote concluído (concluido → ativo, inverso de archivePkg [:541]); se pausado,
    # materializa a nova sessão já com pkgHold.
    update :add_session          # 09: POST /packages/:id/sessions ← pkgAddSession [:541]
    destroy :remove_session      # 09: DELETE /packages/:id/sessions/:appointment_id — diminui (só futura não consumida)
  end
end
```

> **`bulk_adjust` e o `pkgOf`.** `applyMassaPacote` ([`:1149`](../interface/Movimento.dc.html#L1149))
> opera sobre o pacote de **um** dono (via `apptPkg`, que devolve o primeiro). Com
> `Attendance.package_id` (correção e), o ajuste em massa passa a escopar por
> `package_id` das *attendances* — cada participante da turma é ajustado no **seu** pacote,
> não no primeiro. O `escopo` (`esta`|`proximas`|`todas`) e as flags
> `aplicar_profissional`/`aplicar_horario` permanecem os de `applyMassaPacote`.

#### `PackageSchedule` — a grade (dows + horários + profissional)

A `grade` do protótipo (`{dows, horarios, profId}`,
[`:117`](../interface/Movimento.dc.html#L117)) é o insumo de `computeSerie`
([`:1081`](../interface/Movimento.dc.html#L1081)): gera N sessões pulando feriados
(`this.state.holidays.some(h=>h.data===ds && h.tipo!=='horario')`,
[`:1090`](../interface/Movimento.dc.html#L1090)) e estendendo a série até completar N.

```elixir
defmodule Movimento.Packages.PackageSchedule do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :dows, {:array, :integer}, allow_nil?: false         # [1,3] = seg/qua
    attribute :horarios, :map, allow_nil?: false                   # {1:"08:00",3:"08:00"}
  end
  relationships do
    belongs_to :package, Movimento.Packages.Package, allow_nil?: false
    belongs_to :professional, Movimento.Directory.Professional, allow_nil?: false
  end
end
```

### 4.5 `Movimento.Waitlist`

#### `WaitlistEntry` — `dias` derivado de `inserted_at` (correção h)

Seed [`:163`](../interface/Movimento.dc.html#L163). O campo `dias` é **digitado à mão**
(`dias:8`, `dias:5`…) — vira **calculation** sobre `inserted_at` (dias na fila = hoje −
inserção, no timezone da clínica).

```elixir
defmodule Movimento.Waitlist.WaitlistEntry do
  # ... por-tenant; authorizers: [Ash.Policy.Authorizer]; extensions: [AshCloak] (obs sensível)
  attributes do
    uuid_primary_key :id
    attribute :prio, Movimento.Waitlist.Priority, allow_nil?: false, default: :normal
    attribute :janela, Movimento.Waitlist.TimeWindow, allow_nil?: false, default: :qualquer
    # obs = queixa clínica em texto livre. PII SENSÍVEL (06 §1.3) → cifrado.
    attribute :obs, :string, sensitive?: true
    # profIds preferidos [:163] — UUIDs de Professional (0..N).
    attribute :professional_ids, {:array, :uuid}, default: []
  end

  relationships do
    belongs_to :patient, Movimento.Records.Patient, allow_nil?: false
    has_many :rules, Movimento.Waitlist.AvailabilityRule
    has_many :holds, Movimento.Scheduling.SlotHold
  end

  identities do
    # "no máximo um item de fila por paciente" — addFila faz upsert-por-paciente [:1189].
    identity :one_entry_per_patient, [:patient_id]
  end

  calculations do
    # correção h: dias na fila derivado, não digitado.
    calculate :dias_na_fila, :integer, expr(date_diff(today(), fragment("date(?)", inserted_at), :day))
    # NAO-VERIFICADO: confirmar `today()`/date_diff no timezone do escopo (ADR-009)
  end

  actions do
    defaults [:read]
    create :enqueue do       # 09: POST /waitlist ← addFila (upsert-por-paciente [:1187]-[:1192])
      upsert? true
      upsert_identity :one_entry_per_patient
    end
    update :update           # 09: PATCH /waitlist/:id
    destroy :dequeue         # 09: DELETE /waitlist/:id ← [:1186]
    # 09: GET /waitlist/:id/slots — ação genérica (motor filaVagas [:2531]).
    action :find_slots, {:array, :map}
    update :offer            # 09: POST /waitlist/:id/offer ← cria SlotHold (offerVaga [:2596])
    update :convert_to_appointment  # 09: /convert ← createAppt com _fromFila [:1062]
  end
end
```

> **Ordenação de domínio, não `?sort` do cliente.** `filaVagas`
> ([`:2531`](../interface/Movimento.dc.html#L2531)) varre 14 dias (`DAYS=14`,
> [`:2533`](../interface/Movimento.dc.html#L2533)), casa `janela` + `regras`, e **prioriza
> vagas que abriram** por cancelamento/falta (`freed`): o `sort` final põe `freed` primeiro
> (`out.sort((a,b)=> (b.freed?1:0)-(a.freed?1:0) || …)`,
> [`:2591`](../interface/Movimento.dc.html#L2591)). Por isso `:find_slots` é ação genérica
> com ordem embutida (concorda com `09` §3.6).

#### `AvailabilityRule` — regra de disponibilidade da fila

`regras` do item de fila ([`:163`](../interface/Movimento.dc.html#L163)): `tipo ∈
{semana, data}`; `semana` traz `dows` + `periodos`; `data` traz uma `data` + `periodos`.

```elixir
defmodule Movimento.Waitlist.AvailabilityRule do
  # ... por-tenant
  attributes do
    uuid_primary_key :id
    attribute :tipo, Movimento.Waitlist.RuleType, allow_nil?: false   # :semana | :data
    attribute :dows, {:array, :integer}, default: []                  # quando :semana
    attribute :data, :date, allow_nil?: true                          # quando :data
    attribute :periodos, {:array, {:array, :string}}, allow_nil?: false, default: []
  end
  relationships do
    belongs_to :waitlist_entry, Movimento.Waitlist.WaitlistEntry, allow_nil?: false
  end
  validations do
    validate present(:dows), where: [attribute_equals(:tipo, :semana)]
    validate present(:data), where: [attribute_equals(:tipo, :data)]
  end
end
```

### 4.6 `Movimento.Records` — o núcleo sensível (LGPD Art. 11)

#### `Patient` — `faltas` é aggregate (correção b); CPF cifrado + índice cego (§6)

Seed [`:96`](../interface/Movimento.dc.html#L96)-[`:110`](../interface/Movimento.dc.html#L110).
A coluna `faltas` é **denormalizada** — o protótipo a mantém à mão em `justificarFalta`
(`faltas:Math.max(0,(p.faltas||0)+(next?-1:1))`,
[`:1126`](../interface/Movimento.dc.html#L1126)) e a semeia fixa
(`patients[4].faltas=2`, [`:112`](../interface/Movimento.dc.html#L112)). Vira **aggregate**
sobre `Attendance`.

```elixir
defmodule Movimento.Records.Patient do
  # ... por-tenant; authorizers: [Ash.Policy.Authorizer]; extensions: [AshCloak, AshPaperTrail]
  attributes do
    uuid_primary_key :id
    attribute :nome, :string, allow_nil?: false
    attribute :nome_social, :string
    # CPF cifrado (AshCloak) + índice cego determinístico p/ busca (§6, 06 §3.3).
    attribute :cpf, :string, sensitive?: true          # armazenamento cifrado
    attribute :cpf_hash, :binary, allow_nil?: true     # HMAC-SHA256(normalize(cpf)) — indexado
    attribute :rg, :string, sensitive?: true
    attribute :genero, :string
    attribute :estado_civil, :string
    attribute :nascimento, :date
    attribute :tel, :string, sensitive?: true
    attribute :tel_hash, :binary, allow_nil?: true     # índice cego do telefone (byDoc [:999])
    attribute :email, :string, sensitive?: true
    # endereço completo (PII comum, 06 §1.1)
    attribute :endereco, :string
    attribute :numero, :string
    attribute :complemento, :string
    attribute :bairro, :string
    attribute :cidade, :string
    attribute :uf, :string
    attribute :cep, :string
    # contato de emergência (dado de TERCEIRO, 06 §1.1)
    attribute :em_nome, :string, sensitive?: true
    attribute :em_parentesco, :string
    attribute :em_tel, :string, sensitive?: true
    attribute :responsavel, :string, sensitive?: true
    attribute :profissao, :string
    attribute :empresa, :string
    # atendimento comercial + convênio
    attribute :atend_tipo, Movimento.Records.AttendanceType, allow_nil?: false, default: :particular
    attribute :convenio, :string
    attribute :carteirinha, :string, sensitive?: true
    attribute :convenio_validade, :string
    # encaminhamento médico — SENSÍVEL (revela tratamento; dado de terceiro), 06 §1.1
    attribute :medico, :string, sensitive?: true
    attribute :crm, :string, sensitive?: true
    # canal de aquisição (comoConheceu [:107], comoPool [:88]) — NÃO sensível (marketing, não LGPD Art. 11).
    attribute :como_conheceu, :string
    attribute :prefs, {:array, :uuid}, default: []     # profissionais preferidos
    # índice de cor categórica na agenda (ci [:109]); 06 §1.1 classifica público.
    attribute :cor_indice, :integer
  end

  identities do
    identity :unique_cpf, [:cpf_hash]   # unicidade sobre o índice cego, não sobre o cifrado
  end

  relationships do
    has_many :packages, Movimento.Packages.Package
    has_many :attendances, Movimento.Scheduling.Attendance
    has_many :clinical_tags, Movimento.Records.ClinicalTag
    has_many :attachments, Movimento.Records.Attachment
    has_many :consents, Movimento.Records.Consent
  end

  aggregates do
    # correção b: faltas derivado — faltas não justificadas do paciente.
    count :faltas, :attendances do
      filter expr(status == :faltou and falta_justificada == false)
    end
  end

  actions do
    defaults [:read]
    create :create do            # 09: POST /patients — computa cpf_hash/tel_hash
      change Movimento.Records.Changes.ComputeBlindIndexes
    end
    update :update do            # 09: PATCH /patients/:id (genérico é aceitável aqui, 09 §3.3)
      change Movimento.Records.Changes.ComputeBlindIndexes
    end
    # busca por nome OU documento — byDoc [:999]. Usa o índice cego, nunca decifra em massa.
    read :search do
      argument :term, :string, allow_nil?: false
      # filtro combina nome (ilike) + cpf_hash/tel_hash == HMAC(normalize(digits))
      prepare Movimento.Records.Preparations.SearchByNameOrDoc
    end
  end
end
```

> **Busca versus cifra (o ponto crítico do `06`).** Cifrar `cpf`/`tel` quebraria a busca de
> `byDoc` ([`:999`](../interface/Movimento.dc.html#L999): filtra pacientes por
> `p.cpf`/`p.tel` limpos de máscara). A solução do `06` §3.3 (blind index / HMAC
> determinístico) está **refletida no schema acima**: coluna cifrada (`cpf`/`tel`) + coluna
> de índice cego (`cpf_hash`/`tel_hash`), com o índice sobre o hash (§9). A `read :search`
> compara o HMAC do termo, não o texto. Ver `06` §3.3 para as limitações (só igualdade
> exata; vaza igualdade entre registros — aceitável para deduplicar).

#### `ClinicalTag` — diagnósticos como recurso cifrado

`tags` do paciente ([`:108`](../interface/Movimento.dc.html#L108),
[`:115`](../interface/Movimento.dc.html#L115): `'pós-op joelho'`, `'reabilitação
esportiva'`). É diagnóstico clínico (o caso central de `06` §1.1). Cada tag é uma linha, com
o rótulo cifrado — dissolve o array indexável de texto de saúde e prepara diagnóstico
estruturado no futuro.

```elixir
defmodule Movimento.Records.ClinicalTag do
  # ... por-tenant; extensions: [AshCloak]
  attributes do
    uuid_primary_key :id
    attribute :label, :string, allow_nil?: false, sensitive?: true   # cifrado (diagnóstico)
  end
  relationships do
    belongs_to :patient, Movimento.Records.Patient, allow_nil?: false
  end
end
```

#### `Attachment` — laudos em storage privado, URL assinada (ADR-007 item 4)

`addAnexos` ([`:954`](../interface/Movimento.dc.html#L954)) guarda `{name, type, size, url,
date}` com `url = URL.createObjectURL(f)` ([`:957`](../interface/Movimento.dc.html#L957)) —
blob efêmero da aba, inseguro e sem servidor. **Os bytes nunca passam pela API** (`09` §3.9):
a API só troca metadados e assina URLs de vida curta; o cliente sobe/baixa direto do object
storage privado.

```elixir
defmodule Movimento.Records.Attachment do
  # ... por-tenant; extensions: [AshPaperTrail] (toda leitura de anexo é auditada, ADR-007)
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :content_type, :string, allow_nil?: false
    attribute :size_bytes, :integer
    attribute :storage_key, :string, allow_nil?: false   # chave no bucket privado (não URL blob)
  end
  relationships do
    belongs_to :patient, Movimento.Records.Patient, allow_nil?: false
  end
  actions do
    defaults [:read]
    create :request_upload   # 09: POST /patients/:id/attachments → URL assinada de upload
    action :signed_download, :string   # 09: GET /attachments/:id/url → URL assinada de download
    destroy :destroy
  end
end
```

#### `Consent` — consentimento versionado (ADR-007 item 5)

Hoje o consentimento é um `boolean` solto (`patient.lgpd`,
[`:109`](../interface/Movimento.dc.html#L109)), e há um segundo booleano separado para
contato (`comunicacao`, [`:109`](../interface/Movimento.dc.html#L109)). Vira registro
versionado, datado, com finalidade e revogação (ver `06` §2 para o texto legal).

```elixir
defmodule Movimento.Records.Consent do
  # ... por-tenant; extensions: [AshPaperTrail]
  attributes do
    uuid_primary_key :id
    # finalidade separa "tratamento de saúde" (lgpd) de "comunicação/WhatsApp" (comunicacao) —
    # base legal distinta (06 §1.1). Enum aberto por finalidade.
    attribute :finalidade, :atom, allow_nil?: false, constraints: [one_of: [:tratamento, :comunicacao]]
    attribute :versao, :string, allow_nil?: false     # versão do termo aceito
    attribute :concedido_em, :utc_datetime, allow_nil?: false
    attribute :revogado_em, :utc_datetime, allow_nil?: true
  end
  relationships do
    belongs_to :patient, Movimento.Records.Patient, allow_nil?: false
  end
  actions do
    defaults [:read]
    create :grant
    update :revoke
  end
end
```

### 4.7 `Movimento.Reporting`

Não introduz entidade de escrita nova. Expõe **uma ação genérica de agregação**
correspondente a `GET /reports/summary` (`09` §3.8), alimentada pelos KPIs verificados em
`reports2` (chamada por `renderRelatorios`) ([`:3339`](../interface/Movimento.dc.html#L3339) em diante: `ativos`,
`concluídos`, `taxa de falta`, `cancelamentos`). O preço deixa de ser o literal
[`:3339`](../interface/Movimento.dc.html#L3339) e passa a vir de `PriceVersion` (correção a).

```elixir
# NAO-VERIFICADO: forma de ação genérica read + agregados Ash empurrados ao SQL
defmodule Movimento.Reporting.Summary do
  # ... por-tenant; recurso de leitura (generic action :summary)
  actions do
    action :summary, :map do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false
      argument :professional_id, :uuid, allow_nil?: true
      # alimentado por snapshot noturno (Oban) p/ não varrer a tabela ao vivo (05, 04 §11).
    end
  end
end
```

---

## 5. Correções de modelagem (consolidado)

Todas verificáveis no protótipo. As linhas foram abertas.

| # | Correção | Origem no protótipo (verificada) | Onde no schema |
|---|---|---|---|
| a | `preco` não existe no tipo; tabela hardcoded no relatório | `const price={t1:180,t2:120,t3:130,t4:70,t5:90};` [`:3339`](../interface/Movimento.dc.html#L3339) | `PriceVersion` (§4.2), com histórico de vigência |
| b | `patient.faltas` denormalizada | gravada por `setStatus` [`:1038`](../interface/Movimento.dc.html#L1038) (±1 ao marcar/reverter `faltou`) e ajustada em `justificarFalta` [`:1126`](../interface/Movimento.dc.html#L1126); semeada [`:112`](../interface/Movimento.dc.html#L112) | aggregate `Patient.faltas` (§4.6) |
| c | `package.usadas` vestigial | derivada em `pkgUsadas` [`:326`](../interface/Movimento.dc.html#L326) | aggregate `Package.usadas` (§4.4) |
| d | presença por participante (turma pune todos) | status único no bloco; `justificarFalta` percorre `patientIds` [`:1123`](../interface/Movimento.dc.html#L1123) | recurso `Attendance` (§4.3) |
| e | `pkgOf` — pacotes distintos na mesma turma; `apptPkg` pega o primeiro | laço `for` que retorna no 1º acerto [`:1113`](../interface/Movimento.dc.html#L1113) | `Attendance.package_id` dissolve o mapa (§4.3) |
| f | `ScheduleException` unificado (feriado ≡ folga) | mesma forma em `holidays` [`:169`](../interface/Movimento.dc.html#L169) e `prof.exc` [`:66`](../interface/Movimento.dc.html#L66) | 1 recurso, `professional_id` nulo/preenchido (§4.3) |
| g | `prof.avail` com dois sentidos | `profWeek` [`:840`](../interface/Movimento.dc.html#L840); `followClinic=false` + grade cheia [`:64`](../interface/Movimento.dc.html#L64) | `segue_horario_clinica` + `ProfessionalHours.modo` (§4.2/§4.3) |
| h | `fila.dias` digitado | `dias:8` [`:163`](../interface/Movimento.dc.html#L163) | calculation `dias_na_fila` (§4.5) |
| i | pacote sem validade real; pausa +21 hardcoded | `rd.setDate(rd.getDate()+21)` [`:554`](../interface/Movimento.dc.html#L554) | **produção também sem validade** ([ADR-013](00-decisoes.md)/D6): não vira campo; pausa não estende (§4.4) |
| j | `SlotHold` novo; sem `now()` na constraint | `offerVaga` só abre modal [`:2596`](../interface/Movimento.dc.html#L2596); DDL em `04` §7.2 | recurso `SlotHold` (§4.3) |

---

## 6. LGPD no schema

Este documento **não duplica** `06-seguranca-e-lgpd.md`; ele reflete no schema o que o `06`
decide. Resumo operacional:

- **`AshCloak` (cifra de campo, marcados `sensitive?: true` acima).** Pacientes: `cpf`,
  `rg`, `tel`, `email`, `carteirinha`, `medico`, `crm`, contatos de emergência,
  `responsavel`. `ClinicalTag.label` (diagnóstico). `WaitlistEntry.obs` (queixa). Bancários
  do `Professional`: `banco`, `agencia`, `conta`, `pix`. Lista canônica e classes em
  `06` §1. **Marcação:** a forma exata do bloco `AshCloak` muda entre versões e não está nas
  regras do repositório.

  ```elixir
  # NAO-VERIFICADO: confirmar o bloco `cloak` (attributes cifrados, vault) contra hexdocs
  cloak do
    vault Movimento.Vault
    attributes [:cpf, :rg, :tel, :email, :medico, :crm, :carteirinha]
    # decrypt_by_default? conforme field_policies
  end
  ```

- **Índice cego (o conflito busca × cifra, `06` §3.3).** `Patient.cpf_hash`/`tel_hash` são
  `HMAC-SHA256(normalize(valor))`, calculados na criação/atualização por um `change`
  (`ComputeBlindIndexes`) e indexados (§9). A `read :search` compara o hash — reproduz
  `byDoc` ([`:999`](../interface/Movimento.dc.html#L999)) sem decifrar. A chave do HMAC é
  segredo separado da chave de cifra (`06` §3.3).

- **`AshPaperTrail` (auditoria).** Sobre `Patient`, `Attendance`, `Attachment` (toda leitura
  de anexo entra na trilha, ADR-007 item 4), `Consent`, `Package`, e dados bancários do
  `Professional`. **Marcação:** extensão não coberta pelas regras.

  ```elixir
  # NAO-VERIFICADO: confirmar `AshPaperTrail` (change_tracking, versão) contra hexdocs
  ```

- **`field_policies`.** Restringem leitura por papel — bancário só `admin`/próprio; `crm`,
  `medico`, `tags`, `obs` fora do alcance de quem não trata o paciente. `field_policies`
  estão autorizadas pelas regras (`.claude/rules/ash.md`) — afirmadas sem marca; o mapa
  campo→papel completo está em `06` §6.

  ```elixir
  field_policies do
    field_policy [:banco, :agencia, :conta, :conta_tipo, :pix, :cnpj] do
      authorize_if actor_attribute_equals(:papel, :admin)
      authorize_if Movimento.Checks.IsSelfProfessional   # o próprio profissional
    end
    field_policy :* do
      authorize_if always()
    end
  end
  ```

---

## 7. Policies por papel

Hoje os papéis são **apenas rótulos**: `roleMeta`
([`:2408`](../interface/Movimento.dc.html#L2408)) devolve um mapa de `{l, desc, bg, fg, ic}`
puramente descritivo — "Gerencia a própria agenda e seus pacientes"
([`:2412`](../interface/Movimento.dc.html#L2412)) é texto, **sem enforcement algum**. Vira
policy real (ADR-016). `owner` e `admin` são bypass; `recepcao` opera a agenda de todos, sem
configurações; o `profissional` é um **filtro** (`FilterCheck`) ao próprio.

> **De onde vem o `papel` do actor (ADR-014).** O actor das policies é o `User` (global),
> mas o papel mora no `Membership` (por-tenant). A sessão resolve o **tenant ativo** e carrega
> `actor.papel` + `actor.professional_id` a partir do `Membership` ativo **antes** de qualquer
> ação. Trocar de clínica troca esses valores. Nenhuma policy lê `clinic_id` do cliente — o
> tenant ativo é o `clinic_id` do escopo, filtrado pelo Ash (`strategy :attribute`, §2).

```elixir
# NAO-VERIFICADO: FilterCheck é autorizado pelas regras (ash.md), mas confirmar a
# resolução do professional_id a partir do actor/scope ao scaffoldar.
defmodule Movimento.Checks.OwnAgenda do
  use Ash.Policy.FilterCheck

  # "profissional vê só a própria agenda": filtra Appointment pelo professional_id do actor.
  def filter(actor, _authorizer, _opts) do
    expr(professional_id == ^actor.professional_id)
  end
end
```

```elixir
# Appointment — owner e admin veem/mexem tudo na PRÓPRIA clínica (tenant do escopo);
# recepcao opera a agenda de todos; profissional só a própria.
policies do
  bypass actor_attribute_in(:papel, [:owner, :admin]) do
    authorize_if always()
  end

  policy action_type(:read) do
    authorize_if actor_attribute_equals(:papel, :recepcao)  # opera a agenda de todos
    authorize_if Movimento.Checks.OwnAgenda                 # profissional: só a própria
  end

  policy action_type([:create, :update, :destroy]) do
    authorize_if actor_attribute_equals(:papel, :recepcao)
    authorize_if Movimento.Checks.OwnAgenda
  end
end
```

`Patient` usa o mesmo padrão via um `FilterCheck` "pacientes do profissional" (relaciona
paciente → attendances → appointments → professional_id do actor). Configurações
(`ClinicHours`, `AppointmentType`, `Professional.create`, `Membership`) exigem `owner`/`admin`
— o "sem configurações sensíveis" da `recepcao`
([`:2413`](../interface/Movimento.dc.html#L2413)). Faturamento, exclusão da clínica e gestão
de owners são **exclusivas de `owner`** (ADR-016).

---

## 8. Invariantes — onde cada um mora

Regra de alocação: **garantia de concorrência ou unicidade → banco** (constraint); **regra
de forma/entrada → validation Ash** (atômica quando possível, `.claude/rules/ash.md`);
**quem-pode → policy**.

| Invariante | Origem (verificada) | Mora em |
|---|---|---|
| `usadas ≤ total` | `pkgRemaining=max(0,total−usadas)` [`:327`](../interface/Movimento.dc.html#L327) | derivado (aggregate/calc §4.4); `check_constraint total >= 0` no banco |
| capacidade de turma | `cap=tp.cap||settings.capPilates||4` [`:341`](../interface/Movimento.dc.html#L341) | validation atômica em `add_participant` (conta `participantes` < `capacidade`); `422` |
| sessão dentro do expediente | `dayPeriods` [`:854`](../interface/Movimento.dc.html#L854) | validation Ash em `schedule`/`reschedule` (revalida `:availability`); `422` fora do expediente |
| disponibilidade do prof ⊆ horário da clínica | comentário [`:63`](../interface/Movimento.dc.html#L63); grade de Thiago [`:64`](../interface/Movimento.dc.html#L64) | validation Ash em `ProfessionalHours` (períodos custom ⊆ `ClinicHours[dow]`) |
| não-sobreposição por profissional | `checkConflict` [`:834`](../interface/Movimento.dc.html#L834) | **exclusion constraint** `appointments_no_overlap` (banco, 04 §7.1) |
| exceção do encaixe | `if(encaixe) return null` [`:835`](../interface/Movimento.dc.html#L835); `!b.encaixe` [`:837`](../interface/Movimento.dc.html#L837) | predicado parcial `WHERE (encaixe=false AND status<>'cancelado')` (04 §7.1) |
| `patientId` XOR `patientIds` | `apptPkg` ramifica em `a.patientIds`/`a.pkgId` [`:1112`](../interface/Movimento.dc.html#L1112)/[`:1116`](../interface/Movimento.dc.html#L1116) | **eliminado** pela correção d: sempre há `Attendance`(s); não há dois campos |
| `retomaEm` só se pausado | `pkgResume` [`:561`](../interface/Movimento.dc.html#L561) | validation Ash (`retoma_em` presente ⇒ `status == :pausado`) |
| convênio/carteirinha só se `atendTipo=convenio` | seed condicional `conv?…:''` [`:107`](../interface/Movimento.dc.html#L107) | validation Ash em `Patient` (`present(:carteirinha) where atend_tipo == :convenio`) |
| `cap` só se `type.grupo` | tipo `t4` é o único `grupo:true, cap:4` [`:73`](../interface/Movimento.dc.html#L73) | validation em `AppointmentType` (§4.2) |
| não-sobreposição de holds | `04` §7.2 | exclusion constraint `slot_holds_no_overlap` (SEM `now()`, §4.3) |
| CPF único (sobre índice cego) | `byDoc` [`:999`](../interface/Movimento.dc.html#L999) | `identity :unique_cpf [:cpf_hash]` + unique index (§9) |
| um item de fila por paciente | `addFila` faz upsert-por-paciente [`:1189`](../interface/Movimento.dc.html#L1189) | `identity :one_entry_per_patient [:patient_id]` + unique index (§9) |
| um membership por (user, clínica) | modelo Vercel, ADR-014 | `identity :unique_user_per_clinic [:user_id, :clinic_id]` (§Accounts) |
| **≥1 owner por tenant** | ADR-016 | validation Ash em `Membership` `update`/`destroy` (conta owners restantes; `422` ao rebaixar/remover o último) |

---

## 9. Índices

> **`clinic_id` primeiro (ADR-017).** Com tenancy por atributo, toda tabela por-tenant tem
> `clinic_id`, e o Ash filtra por ele em **toda** query. Por isso os índices por-tenant devem
> **liderar com `clinic_id`** (ex.: `(clinic_id, starts_at)`), tanto por performance quanto como
> a mitigação #3 do [§2](#2-multitenancy--a-decisão). Índices de igualdade exata sobre chave
> naturalmente única (ex.: `professional_id`, `cpf_hash`) já são seletivos, mas ganham `clinic_id`
> à frente quando servem a filtros de listagem. Os exemplos abaixo mostram a forma-alvo.

```sql
-- Agenda por (clínica, profissional, tempo) — clinic_id lidera (ADR-017).
CREATE INDEX appointments_clinic_prof_starts ON appointments (clinic_id, professional_id, starts_at);
-- (a não-sobreposição em si é a exclusion constraint GiST appointments_no_overlap, 04 §7.1)

-- Sessões de um pacote (pkgAppts [:330]).
CREATE INDEX appointments_package ON appointments (package_id);

-- Presença por paciente e por pacote (Attendance).
CREATE INDEX attendances_patient ON attendances (patient_id);
CREATE INDEX attendances_package ON attendances (package_id);
CREATE UNIQUE INDEX attendances_appt_patient ON attendances (appointment_id, patient_id);

-- Busca de paciente: índice CEGO de CPF/telefone (igualdade exata, 06 §3.3) + nome.
CREATE UNIQUE INDEX patients_cpf_hash ON patients (cpf_hash);
CREATE INDEX patients_tel_hash ON patients (tel_hash);
CREATE INDEX patients_nome_trgm ON patients USING gin (nome gin_trgm_ops);  -- ilike por nome

-- Fila e holds.
CREATE INDEX waitlist_prio ON waitlist_entries (prio);
CREATE UNIQUE INDEX waitlist_one_per_patient ON waitlist_entries (patient_id);  -- upsert addFila [:1189]
CREATE INDEX slot_holds_expires ON slot_holds (expires_at);   -- coletor DML/Oban (04 §7.2)
```

```sql
-- Exclusion constraint da agenda (04 §7.1). Reproduzida aqui como referência da migration.
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE appointments
  ADD CONSTRAINT appointments_no_overlap
  EXCLUDE USING gist (
    professional_id                        WITH =,
    tstzrange(starts_at, ends_at, '[)')    WITH &&
  )
  WHERE (encaixe = false AND status <> 'cancelado');
```

> **`pg_trgm`/`btree_gist`.** Ambas as extensões entram por `custom_statements`
> (`.claude/rules/ash_postgres.md`: `CREATE EXTENSION IF NOT EXISTS …`). O índice de nome é
> `gin_trgm_ops` para `ilike`; a busca por documento é igualdade sobre o hash, não trigrama.

---

## Apêndice A — Divergências com o `09`

1. **`complete`/`no_show` no nível do slot vs. da presença.** O `09` §3.1 mantém
   `POST /appointments/:id/complete` e `/no_show` no **agendamento**, isolando `attendance`
   como sub-recurso "para absorver a decisão sem reescrever a rota". Este documento vai um
   passo além e já modela `Attendance` como o portador do desfecho (correção d/e), porque
   `pkgOf` ([`:1113`](../interface/Movimento.dc.html#L1113)) prova que participantes de uma
   turma podem estar em pacotes diferentes — o débito **precisa** ser por participante.
   **Reconciliação:** as ações do slot permanecem (para o caso 1-a-1, que é a maioria); para
   turma, elas exigem `patient_id` e delegam à `Attendance` correspondente. Não há conflito
   de rota — há uma decisão de produto pendente ("presença individual em turma", em aberto no
   `00`) que este schema já suporta.

2. **Estados do pacote.** O `09` §3.4 lista `ativo, pausado, renovado, cancelado, concluido`. O
   `renovado` é verificado no protótipo (setado em `createPacote`, no ramo `d.renovadoDe`,
   [`:362`](../interface/Movimento.dc.html#L362); exibido em `pkgStatusMeta`,
   [`:334`](../interface/Movimento.dc.html#L334); note que `confirmRenovar`
   [`:590`](../interface/Movimento.dc.html#L590)/[`:600`](../interface/Movimento.dc.html#L600) é o
   fluxo distinto "continuar a mesma grade", que só acrescenta sessões e mantém `status:'ativo'`),
   mas **a produção o descarta**: por
   [ADR-011](00-decisoes.md) **não há renovação**, então `PackageStatus` (§3) tem **quatro**
   valores (`:renovado` removido). **Divergência deliberada** do protótipo, registrada no ADR-011;
   o `09` §3.4 precisa ser alinhado.

3. **`resume` reprojeta para o futuro.** O `09` §3.4 declara isso como "correção deliberada,
   não o espelho do protótipo" (o `pkgResume`, [`:561`](../interface/Movimento.dc.html#L561),
   devolveria sessões em datas já passadas). A ação `:resume` (§4.4) segue o `09`, não o
   protótipo. Registro explícito para o auditor: a divergência é **intencional e do `09`**.

4. **`GET /reports/summary` e o preço.** O `09` §3.8 aponta os KPIs de `renderRelatorios`.
   Este documento adiciona que o `preco` do relatório
   ([`:3339`](../interface/Movimento.dc.html#L3339)) deixa de ser literal e passa a
   `PriceVersion` (correção a). O contrato de resposta do `09` não muda; a **fonte** do valor
   muda.

5. **`professional_ids` na fila.** O `09` §3.6 fala em `profIds` preferidos. Modelado como
   `{:array, :uuid}` em `WaitlistEntry` (§4.5), coerente com o seed
   [`:164`](../interface/Movimento.dc.html#L164) (`profIds:['p4','p1']`). Sem divergência.

---

## Apêndice B — O que depende de resposta de produto (muda tabela)

Itens travados como "em aberto" no `00-decisoes.md` que alteram o schema — não o
comportamento das ações, mas as **colunas**:

1. **Preço por convênio / repasse ao profissional.** `PriceVersion.convenio` está nullable
   e a tabela base é particular. Se o preço variar por convênio, a `identity`/índice de
   vigência precisa incluir `convenio`; se houver repasse, entra um recurso
   `PriceSplit`/`Repasse` ligado a `Professional`. **Bloqueia** a forma final de
   `PriceVersion`.

2. ~~**Validade real do pacote e extensão por pausa.**~~ **RESOLVIDO ([ADR-013](00-decisoes.md)/D6):**
   pacote **não tem validade**; `validade_ate`/`pausado_em` **não existem**. Pausar não estende
   nada; `resume` apenas reprojeta a série restante para o futuro (§4.4).

3. **Salas / equipamentos como recurso com capacidade.** Hoje o conflito é **só por
   profissional** (`checkConflict` filtra `b.profId===profId`,
   [`:834`](../interface/Movimento.dc.html#L834)). Se sala/equipamento virar recurso com
   capacidade, entra `Room`/`Resource` e a exclusion constraint da agenda ganha uma **segunda**
   dimensão (`room_id WITH =`), ou uma constraint irmã. **Bloqueia** a modelagem de
   `Scheduling` e o DDL de `04` §7.1.

4. ~~**Renovar = continuar o mesmo pacote ou criar sucessor?**~~ **RESOLVIDO
   ([ADR-011](00-decisoes.md)):** **não há renovação**. Sem `renovado_de`, sem ação `:renew`, sem
   status `:renovado`. O `total` de sessões é **editável (+/−) a qualquer momento** via
   `add_session`/`remove_session`, sempre no mesmo pacote (§4.4).

5. **Presença individual em turma como requisito firme** (ver Apêndice A, item 1). Se
   confirmada, `complete`/`no_show` migram de vez para `Attendance` e o slot perde `concluido`/
   `faltou` do enum `AppointmentStatus` (passa a `AttendanceStatus`). **Muda o enum do slot.**

6. **Profissional em mais de uma clínica (ADR-003).** No modelo por-tenant (`clinic_id`,
   ADR-017), uma pessoa que atende em duas clínicas tem **dois** `Professional` (um por
   `clinic_id`), ligados por `Membership.professional_id` (global). Se produto exigir uma visão consolidada
   cross-clínica do profissional, entra um `Person` global acima dos `Professional` de
   tenant. **Bloqueia** o desenho de `Accounts` — hoje resolvido pelo `Membership` mole.
