defmodule ApiWeb.AuthControllerTest do
  @moduledoc """
  Endpoints de autenticação e sessão (ADR-015, contrato 09 §8) pelo pipeline real
  (`:authenticated` → load_from_session → VerifyTokenSubject → LoadScope). Cobre o que
  é sensível: resposta NEUTRA do magic link, exigência de sessão em `/me`, troca de
  tenant só com vínculo ativo, escopo do token de realtime e revogação no sign-out.
  """
  use ApiWeb.ConnCase, async: false

  alias Api.Accounts

  defp create_user do
    email = "user-#{System.unique_integer([:positive])}@example.com"
    :ok = Accounts.request_magic_link(email)
    assert_receive {:email, mail}, 1_000
    [_, token] = Regex.run(~r/token=([\w.\-]+)/, mail.text_body)
    {:ok, user} = Accounts.sign_in_with_magic_link(token)
    user
  end

  defp onboard(user, nome \\ nil) do
    nome = nome || "Clínica #{System.unique_integer([:positive])}"
    {:ok, clinic} = Accounts.onboard_clinic(nome, %{}, actor: user)
    clinic
  end

  # Estabelece a sessão exatamente como o callback faz (store_in_session).
  defp authed(conn, user) do
    conn
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  describe "POST /api/auth/magic-link (resposta neutra)" do
    test "e-mail válido: 200 {ok:true} e dispara o e-mail", %{conn: conn} do
      addr = "user-#{System.unique_integer([:positive])}@example.com"
      conn = post(conn, ~p"/api/auth/magic-link", %{email: addr})

      assert json_response(conn, 200) == %{"ok" => true}
      assert_receive {:email, mail}, 1_000
      assert [{_, ^addr}] = mail.to
    end

    test "e-mail em branco: ainda 200 {ok:true} e NÃO envia (não revela conta)", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/magic-link", %{email: ""})

      assert json_response(conn, 200) == %{"ok" => true}
      refute_receive {:email, _}, 200
    end
  end

  describe "GET /api/auth/magic-link/callback" do
    test "sem token: 400 missing_token", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/magic-link/callback")
      assert json_response(conn, 400) == %{"error" => "missing_token"}
    end

    test "token inválido: 401 com location para o login do web (erro=magic_link)", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/magic-link/callback?token=lixo")
      assert conn.status == 401
      assert [location] = get_resp_header(conn, "location")
      assert location =~ "/login?erro=magic_link"
    end
  end

  describe "GET /api/auth/me" do
    test "sem sessão: 401 not_authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/me")
      assert json_response(conn, 401) == %{"error" => "not_authenticated"}
    end

    test "autenticado com clínica: 200 com identidade, papel e memberships", %{conn: conn} do
      user = create_user()
      clinic = onboard(user)

      conn = conn |> authed(user) |> get(~p"/api/auth/me")
      body = json_response(conn, 200)

      assert body["user"]["email"] == to_string(user.email)
      assert body["active_clinic_id"] == clinic.id
      assert body["papel"] == "owner"
      assert [membership] = body["memberships"]
      assert membership["clinic_id"] == clinic.id
    end
  end

  describe "POST /api/auth/switch-tenant" do
    test "troca para clínica com vínculo ativo: 200 e o /me reflete", %{conn: conn} do
      user = create_user()
      _a = onboard(user, "Clínica A")
      b = onboard(user, "Clínica B")

      conn = conn |> authed(user) |> post(~p"/api/auth/switch-tenant", %{clinic_id: b.id})
      assert json_response(conn, 200)["active_clinic_id"] == b.id
    end

    test "clínica sem vínculo ativo: 403 no_active_membership", %{conn: conn} do
      user = create_user()
      _sua = onboard(user, "Sua Clínica")
      outro = create_user()
      alheia = onboard(outro, "Clínica Alheia")

      conn = conn |> authed(user) |> post(~p"/api/auth/switch-tenant", %{clinic_id: alheia.id})
      assert json_response(conn, 403) == %{"error" => "no_active_membership"}
    end

    test "sem clinic_id: 400 missing_clinic_id", %{conn: conn} do
      user = create_user()
      _c = onboard(user)

      conn = conn |> authed(user) |> post(~p"/api/auth/switch-tenant", %{})
      assert json_response(conn, 400) == %{"error" => "missing_clinic_id"}
    end
  end

  describe "GET /api/realtime/token" do
    test "com clínica ativa: 200 e o token traz user_id + clinic_id", %{conn: conn} do
      user = create_user()
      clinic = onboard(user)

      conn = conn |> authed(user) |> get(~p"/api/realtime/token")
      body = json_response(conn, 200)

      assert is_binary(body["token"])

      assert {:ok, %{user_id: uid, clinic_id: cid}} =
               Phoenix.Token.verify(ApiWeb.Endpoint, "realtime socket", body["token"],
                 max_age: 900
               )

      assert uid == user.id
      assert cid == clinic.id
    end

    test "autenticado sem clínica ativa: 409 no_active_clinic", %{conn: conn} do
      user = create_user()

      conn = conn |> authed(user) |> get(~p"/api/realtime/token")
      assert json_response(conn, 409) == %{"error" => "no_active_clinic"}
    end

    test "sem sessão: 401", %{conn: conn} do
      conn = get(conn, ~p"/api/realtime/token")
      assert json_response(conn, 401) == %{"error" => "not_authenticated"}
    end
  end

  describe "DELETE /api/auth/sign-out" do
    test "invalida a sessão: 204 e o /me seguinte volta 401", %{conn: conn} do
      user = create_user()
      _c = onboard(user)

      conn = conn |> authed(user) |> delete(~p"/api/auth/sign-out")
      assert conn.status == 204

      # Sessão limpa: uma nova requisição na mesma conn (cookies reciclados) não autentica.
      conn = get(conn, ~p"/api/auth/me")
      assert json_response(conn, 401) == %{"error" => "not_authenticated"}
    end
  end
end
