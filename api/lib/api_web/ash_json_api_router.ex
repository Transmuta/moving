defmodule ApiWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Api.Meta],
    open_api: "/open_api"
end
