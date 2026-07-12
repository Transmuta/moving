defmodule Api.Secrets do
  @moduledoc """
  Secrets do AshAuthentication (ADR-015): segredo de assinatura dos tokens e as
  credenciais do Google OAuth. Todos resolvidos de `Application.get_env(:api, ...)`,
  que em prod vem de variáveis de ambiente (ver `runtime.exs`).
  """
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Api.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:api, :token_signing_secret)
  end

  def secret_for([:authentication, :strategies, :google, key], Api.Accounts.User, _opts, _context)
      when key in [:client_id, :client_secret, :redirect_uri] do
    :api
    |> Application.get_env(:google_oauth, [])
    |> Keyword.fetch(key)
  end
end
