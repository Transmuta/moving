defmodule MovimentoWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Movimento.Meta],
    open_api: "/open_api"
end
