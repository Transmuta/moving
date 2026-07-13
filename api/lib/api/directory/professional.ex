defmodule Api.Directory.Professional do
  @moduledoc """
  O profissional que atende — recurso **por-tenant** via **atributo** (`strategy
  :attribute`, ADR-017): mora na tabela única `professionals`, com a coluna `clinic_id`.
  O Ash injeta `WHERE clinic_id = <tenant ativo>` em toda query e preenche o `clinic_id`
  na criação a partir do tenant do escopo.

  Uma pessoa que atende em 2 clínicas é 2 registros `Professional` (um por `clinic_id`),
  ligados ao mesmo `User` via `Membership.professional_id`.

  Fatia de fundação: mínimo (só o nome) — o suficiente para provar o isolamento por
  atributo. Agenda/disponibilidade/preço entram nas fatias seguintes.
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Directory,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "professionals"
    repo Api.Repo

    # Apagar a clínica apaga seus profissionais (decisão da auditoria doc 13, causa D):
    # o tenant é a clínica; sem ela o Professional não tem sentido.
    references do
      reference :clinic, on_delete: :delete
    end

    # A RLS injeta `WHERE clinic_id = <tenant>` em TODA query desta tabela (ADR-018) — e
    # `clinic_id` não é indexado por padrão. Sem este índice, cada leitura por-tenant é seq
    # scan conforme a tabela cresce (auditoria doc 13, causa C).
    custom_indexes do
      index [:clinic_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:nome]
    end

    update :update do
      accept [:nome]
    end
  end

  # ADR-016: leitura para qualquer membro ativo do tenant; escrita só owner/admin. O
  # `clinic_id` vem do tenant ativo (escopo), nunca do corpo. Isolamento entre clínicas
  # já é garantido pelo filtro por atributo + RLS (ADR-017/018); a policy adiciona o RBAC.
  policies do
    policy action_type(:read) do
      authorize_if {Api.Accounts.Checks.HasClinicRole, roles: :any, clinic_from: :tenant}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Api.Accounts.Checks.HasClinicRole,
                    roles: [:owner, :admin], clinic_from: :tenant}
    end
  end

  # Por-tenant por atributo: o tenant é o `clinic_id`. Toda ação exige o tenant no
  # escopo; o Ash filtra por clinic_id (isolamento lógico) e o preenche no create.
  multitenancy do
    strategy :attribute
    attribute :clinic_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :nome, :string, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    # clinic_id é a coluna de tenant (FK -> clinics.id, garante integridade).
    belongs_to :clinic, Api.Accounts.Clinic, allow_nil?: false
  end
end
