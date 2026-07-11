defmodule ApiWeb.HealthController do
  use ApiWeb, :controller

  # Liveness/readiness simples. Também serve de alvo p/ verificar hot reload.
  def show(conn, _params) do
    json(conn, %{status: "ok", service: "api"})
  end
end
