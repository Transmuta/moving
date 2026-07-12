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
    data_layer: AshPostgres.DataLayer

  # A Clinic é o registry de tenants: a tabela em si é GLOBAL (schema público, sem
  # bloco `multitenancy`). O `manage_tenant` abaixo é o que provisiona o schema
  # `tenant_<uuid>` (e roda as tenant migrations nele) quando uma clínica é criada.
  postgres do
    table "clinics"
    repo Api.Repo

    manage_tenant do
      template ["tenant_", :id]
    end
  end

  actions do
    defaults [:read]

    # ADR-016: na fatia de auth, o `onboard` também cria o Membership `owner` do
    # usuário atual (na mesma transação). Sem auth ainda, cria só a clínica.
    create :onboard do
      accept [:nome, :timezone, :cap_turma_padrao, :falta_consome_padrao, :slot_minutos]
    end

    update :update_settings do
      accept [:nome, :timezone, :cap_turma_padrao, :falta_consome_padrao, :slot_minutos]
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
end
