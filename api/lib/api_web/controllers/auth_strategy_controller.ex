defmodule ApiWeb.AuthStrategyController do
  @moduledoc """
  Recebe o resultado do hand-off OAuth (Google, ADR-015) do `AshAuthentication.Phoenix`.
  As rotas `/api/auth/strategy/...` (montadas por `auth_routes` no router) despacham para
  a estratégia via Assent e chamam `success/4` ou `failure/3` aqui. No sucesso, assina a
  sessão e redireciona ao app web; na falha, redireciona ao login com erro.
  """
  use ApiWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias AshAuthentication.Plug.Helpers

  @impl true
  def success(conn, _activity, user, _token) do
    conn
    |> Helpers.store_in_session(user)
    |> redirect(external: Api.web_app_url())
  end

  @impl true
  def failure(conn, _activity, _reason) do
    conn
    |> put_status(:unauthorized)
    |> redirect(external: Api.web_app_url() <> "/login?erro=oauth")
  end

  @impl true
  def sign_out(conn, _params) do
    conn
    |> clear_session(:api)
    |> redirect(external: Api.web_app_url())
  end
end
