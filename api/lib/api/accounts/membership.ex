defmodule Api.Accounts.Membership do
  @moduledoc """
  Vínculo pessoa↔clínica com papel isolado por tenant — a peça central do modelo
  Vercel (ADR-014). Liga um `User` global a uma `Clinic`, com papel por-clínica. A
  mesma pessoa tem N memberships (é assim que um profissional atende em mais de uma
  clínica e uma dona tem mais de uma unidade). `professional_id` é um UUID mole que
  aponta o `Professional` daquele tenant (sem FK entre schemas).
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Accounts,
    data_layer: AshPostgres.DataLayer

  # Global: o vínculo vive no schema público (liga entidades globais User<->Clinic),
  # sem bloco `multitenancy`. FKs para users e clinics (ambos públicos).
  postgres do
    table "memberships"
    repo Api.Repo

    references do
      reference :user, on_delete: :delete
      reference :clinic, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    # Convite: cria pendente; ativa no primeiro acesso (magic link/Google, ADR-015).
    create :invite do
      accept [:papel, :professional_id]
      argument :user_id, :uuid, allow_nil?: false
      argument :clinic_id, :uuid, allow_nil?: false
      change manage_relationship(:user_id, :user, type: :append)
      change manage_relationship(:clinic_id, :clinic, type: :append)
    end

    update :update do
      accept [:papel, :professional_id]
      require_atomic? false
    end

    update :accept_invite do
      accept []
      require_atomic? false
      change set_attribute(:status, :ativo)
    end

    destroy :revoke_access do
      require_atomic? false
    end
  end

  # ADR-016 — invariante ">=1 owner por tenant" (não-atômica; ver o módulo).
  validations do
    validate {Api.Accounts.Membership.Validations.NotLastOwner, []}, on: [:update, :destroy]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :papel, Api.Accounts.Role, allow_nil?: false, default: :recepcao, public?: true

    attribute :status, Api.Accounts.MemberStatus,
      allow_nil?: false,
      default: :pendente,
      public?: true

    # Opcional e único por clínica: aponta um membro :profissional ao seu Professional
    # no schema do tenant. UUID mole (sem FK entre schemas).
    attribute :professional_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :user, Api.Accounts.User, allow_nil?: false
    belongs_to :clinic, Api.Accounts.Clinic, allow_nil?: false
  end

  identities do
    identity :unique_user_per_clinic, [:user_id, :clinic_id]
    # profId único por clínica (nulos são distintos no Postgres — vários sem prof ok).
    identity :unique_professional_link, [:clinic_id, :professional_id]
  end
end
