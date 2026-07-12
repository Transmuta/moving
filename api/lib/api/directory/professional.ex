defmodule Api.Directory.Professional do
  @moduledoc """
  O profissional que atende — recurso **por-tenant** (`strategy :context`, ADR-014):
  vive dentro do schema da clínica. Uma pessoa que atende em 2 clínicas é 2 registros
  `Professional` (um por schema), ligados ao mesmo `User` via `Membership.professional_id`.

  Fatia de fundação: mínimo (só o nome) — o suficiente para provar o isolamento por
  schema. Agenda/disponibilidade/preço entram nas fatias seguintes.
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Directory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "professionals"
    repo Api.Repo
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

  # Por-tenant: sem `global?`. Toda ação exige o tenant no escopo; a query roda
  # dentro do schema `tenant_<uuid>`, então não há linha de outra clínica alcançável.
  multitenancy do
    strategy :context
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :nome, :string, allow_nil?: false, public?: true
    timestamps()
  end
end
