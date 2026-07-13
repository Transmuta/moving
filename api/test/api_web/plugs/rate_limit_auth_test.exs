defmodule ApiWeb.Plugs.RateLimitAuthTest do
  @moduledoc """
  Rate limiting dos endpoints de auth (auditoria doc 13, causa A). A enforcement é gated a
  produção (`config :api, rate_limit_enabled`); aqui ligamos a flag para exercitar o plug pelo
  pipeline real. Janela deslizante por e-mail: o 6º pedido do mesmo e-mail em 60s é barrado.
  """
  use ApiWeb.ConnCase, async: false

  setup do
    Application.put_env(:api, :rate_limit_enabled, true)
    on_exit(fn -> Application.put_env(:api, :rate_limit_enabled, false) end)
    :ok
  end

  test "magic-link: 5 pedidos passam e o 6º do mesmo e-mail é barrado (429)", %{conn: conn} do
    email = "flood-#{System.unique_integer([:positive])}@example.com"

    for _ <- 1..5 do
      resp = post(build_conn(), ~p"/api/auth/magic-link", %{email: email})
      assert json_response(resp, 200) == %{"ok" => true}
    end

    barrado = post(conn, ~p"/api/auth/magic-link", %{email: email})
    assert json_response(barrado, 429) == %{"error" => "rate_limited"}
  end

  test "o limite é por e-mail: um endereço novo não herda a contagem do outro", %{conn: conn} do
    quente = "quente-#{System.unique_integer([:positive])}@example.com"
    for _ <- 1..5, do: post(build_conn(), ~p"/api/auth/magic-link", %{email: quente})
    assert post(conn, ~p"/api/auth/magic-link", %{email: quente}).status == 429

    novo = "novo-#{System.unique_integer([:positive])}@example.com"

    assert json_response(post(conn, ~p"/api/auth/magic-link", %{email: novo}), 200) == %{
             "ok" => true
           }
  end

  test "brute force no mesmo e-mail de IPs diferentes: o limite por e-mail barra mesmo assim", %{
    conn: _conn
  } do
    email = "teste-#{System.unique_integer([:positive])}@example.com"

    # 5 pedidos, cada um de um IP diferente (X-Forwarded-For, como o BFF repassa).
    for i <- 1..5 do
      resp =
        build_conn()
        |> put_req_header("x-forwarded-for", "10.0.0.#{i}")
        |> post(~p"/api/auth/magic-link", %{email: email})

      assert json_response(resp, 200) == %{"ok" => true}
    end

    # 6º, de mais um IP novo: barrado. Rotacionar IP não ajuda — o key é o e-mail.
    barrado =
      build_conn()
      |> put_req_header("x-forwarded-for", "10.0.0.99")
      |> post(~p"/api/auth/magic-link", %{email: email})

    assert json_response(barrado, 429) == %{"error" => "rate_limited"}
  end

  test "desligado (default fora de prod): não barra", %{conn: _conn} do
    Application.put_env(:api, :rate_limit_enabled, false)
    email = "sem-limite-#{System.unique_integer([:positive])}@example.com"

    for _ <- 1..8 do
      resp = post(build_conn(), ~p"/api/auth/magic-link", %{email: email})
      assert json_response(resp, 200) == %{"ok" => true}
    end
  end
end
