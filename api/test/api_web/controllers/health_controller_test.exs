defmodule ApiWeb.HealthControllerTest do
  @moduledoc "Liveness/readiness — responde sem exigir autenticação."
  use ApiWeb.ConnCase, async: false

  test "GET /api/health: 200 com status ok", %{conn: conn} do
    conn = get(conn, ~p"/api/health")
    assert json_response(conn, 200) == %{"status" => "ok", "service" => "api"}
  end
end
