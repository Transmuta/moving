defmodule Api.Meta do
  use Ash.Domain, otp_app: :api, extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/pings", Api.Meta.Ping do
        index :read
        get :read
        post :create
      end
    end
  end

  resources do
    resource Api.Meta.Ping
  end
end
