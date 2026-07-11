defmodule Movimento.Meta do
  use Ash.Domain, otp_app: :movimento, extensions: [AshJsonApi.Domain]

  json_api do
    routes do
      base_route "/pings", Movimento.Meta.Ping do
        index :read
        get :read
        post :create
      end
    end
  end

  resources do
    resource Movimento.Meta.Ping
  end
end
