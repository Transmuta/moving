defmodule ApiWeb.AuthStrategyControllerTest do
  @moduledoc """
  Callbacks do hand-off OAuth (Assent/Google, ADR-015). Exercita success/failure/sign_out
  diretamente (sem simular o Assent): sucesso assina a sessão e volta ao web; falha
  redireciona ao login com erro; sign_out limpa a sessão.
  """
  use ApiWeb.ConnCase, async: false

  alias Api.Accounts
  alias ApiWeb.AuthStrategyController

  defp create_user do
    email = "user-#{System.unique_integer([:positive])}@example.com"
    :ok = Accounts.request_magic_link(email)
    assert_receive {:email, mail}, 1_000
    [_, token] = Regex.run(~r/token=([\w.\-]+)/, mail.text_body)
    {:ok, user} = Accounts.sign_in_with_magic_link(token)
    user
  end

  test "success/4 assina a sessão e redireciona ao app web", %{conn: conn} do
    user = create_user()

    conn =
      conn
      |> init_test_session(%{})
      |> AuthStrategyController.success(nil, user, nil)

    assert redirected_to(conn) == "http://localhost:5173"
    # A sessão passou a ter o token do usuário (store_in_session).
    assert get_session(conn, "user_token")
  end

  test "failure/3: 401 com location para o login (erro=oauth)", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> AuthStrategyController.failure(nil, :invalid_credentials)

    assert conn.status == 401
    assert [location] = get_resp_header(conn, "location")
    assert location =~ "/login?erro=oauth"
  end

  test "sign_out/2 limpa a sessão e redireciona ao app web", %{conn: conn} do
    user = create_user()

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> AuthStrategyController.sign_out(%{})

    assert redirected_to(conn) == "http://localhost:5173"
    assert get_session(conn, "user_token") == nil
  end
end
