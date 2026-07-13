defmodule Api do
  @moduledoc """
  Api keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  URL do app web (BFF SvelteKit), destino dos redirects de login e base dos links de e-mail
  (ADR-005). Fonte única — antes estava duplicada em três módulos (auditoria doc 13, causa I).
  Vem do config (`:web_app_url`), que em prod resolve de env no `runtime.exs`.
  """
  @spec web_app_url() :: String.t()
  def web_app_url, do: Application.get_env(:api, :web_app_url, "http://localhost:5173")
end
