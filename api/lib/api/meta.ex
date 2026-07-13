defmodule Api.Meta do
  @moduledoc """
  Domínio de metadados/operacional da API, exposto via AshJsonApi.

  Vazio por ora: o recurso de scaffold `Ping` (health de ponta-a-ponta) foi **removido** na
  auditoria (doc 13) por publicar leitura **e escrita anônimas** em `/api/json/pings` — o
  recurso não tinha `Ash.Policy.Authorizer` e o domínio roteava `post :create` sem auth.

  A plumbing do AshJsonApi.Domain fica de pé para os recursos que serão expostos aqui adiante.
  Regra herdada da auditoria: **todo recurso roteado no AshJsonApi tem authorizer + policy**.
  """
  use Ash.Domain, otp_app: :api, extensions: [AshJsonApi.Domain]

  json_api do
    routes do
    end
  end

  resources do
  end
end
