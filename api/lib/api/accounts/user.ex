defmodule Api.Accounts.User do
  @moduledoc """
  A identidade global de login (ADR-014). Uma pessoa = um `User`, no schema público,
  ligada a N clínicas por N `Membership`s. Separado de `Professional` (que é por-schema).

  TODO(auth, ADR-015): adicionar `extensions: [AshAuthentication]` com as estratégias
  Google OAuth + Magic Link (sem senha) na próxima fatia. Por ora é só a identidade.
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Accounts,
    data_layer: AshPostgres.DataLayer

  # Global: o User é a identidade única e vive no schema público (sem `multitenancy`).
  postgres do
    table "users"
    repo Api.Repo
  end

  actions do
    defaults [:read]

    # Placeholder até a fatia de auth: cria/identifica o usuário pelo e-mail. Com
    # AshAuthentication, magic link/Google assumem o create real (upsert por e-mail).
    create :register do
      accept [:nome, :email]
      upsert? true
      upsert_identity :unique_email
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :nome, :string, allow_nil?: false, public?: true
    # case-insensitive; identidade de login.
    attribute :email, :ci_string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    has_many :memberships, Api.Accounts.Membership
  end

  identities do
    identity :unique_email, [:email]
  end
end
