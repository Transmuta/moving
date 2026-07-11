defmodule Api.Meta.Ping do
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Meta,
    extensions: [AshJsonApi.Resource],
    data_layer: AshPostgres.DataLayer

  json_api do
    type "ping"
  end

  postgres do
    table "pings"
    repo Api.Repo
  end

  actions do
    defaults [:read, create: [:message]]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :message, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end
end
