defmodule Api.Accounts.Clinic do
  @moduledoc """
  A clínica — o **tenant** (ADR-014). Recurso global (schema público) que serve de
  registry de tenants e provisiona o schema `tenant_<uuid>` via `manage_tenant`.
  Reúne o que o protótipo mantinha como singletons globais (hours/settings), agora
  escopado por clínica.
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # A Clinic é o registry de tenants (schema público). Com tenancy por atributo
  # (ADR-017), a clínica não provisiona schema nenhum — os recursos por-tenant
  # carregam a coluna `clinic_id` apontando para aqui.
  postgres do
    table "clinics"
    repo Api.Repo
  end

  actions do
    defaults [:read]

    # ADR-016: o `onboard` cria a clínica E o Membership `owner` do usuário atual, na
    # mesma transação (ver o change). Garante a invariante "≥1 owner por tenant".
    create :onboard do
      accept [:nome, :timezone, :cap_turma_padrao, :falta_consome_padrao, :slot_minutos]
      change Api.Accounts.Clinic.Changes.CreateOwnerMembership
    end

    update :update_settings do
      accept [:nome, :timezone, :cap_turma_padrao, :falta_consome_padrao, :slot_minutos]
    end
  end

  # ADR-016: leitura só para membros ativos; onboard para qualquer autenticado (vira
  # owner); ajuste de settings só para owner/admin. Papel derivado do Membership do tenant.
  policies do
    policy action_type(:read) do
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and status == :ativo))
    end

    policy action(:onboard) do
      authorize_if actor_present()
    end

    policy action(:update_settings) do
      authorize_if expr(
                     exists(
                       memberships,
                       user_id == ^actor(:id) and papel in [:owner, :admin] and status == :ativo
                     )
                   )
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :nome, :string, allow_nil?: false, public?: true

    # ADR-009: timezone canônico da clínica. "Hoje"/"já começou" resolvem aqui.
    attribute :timezone, :string, allow_nil?: false, default: "America/Sao_Paulo", public?: true

    # settings do protótipo: {capPilates:4, noShowConsome:false, slot:15}
    attribute :cap_turma_padrao, :integer, allow_nil?: false, default: 4, public?: true
    attribute :falta_consome_padrao, :boolean, allow_nil?: false, default: false, public?: true
    attribute :slot_minutos, :integer, allow_nil?: false, default: 15, public?: true

    timestamps()
  end

  relationships do
    # Usada pelas policies (quem é membro/owner desta clínica). Membership é global.
    has_many :memberships, Api.Accounts.Membership
  end
end
