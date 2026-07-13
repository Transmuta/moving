defmodule ApiWeb.Plugs.LoadScopeTest do
  @moduledoc """
  Montagem do `Api.Scope` na requisição (ADR-014). Prova as três resoluções de tenant
  e a propagação de actor/tenant para o `Ash.PlugHelpers` — a fonte única do `clinic_id`
  das ações, que **nunca** vem do corpo/URL (09 §8).
  """
  use Api.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Api.Accounts
  alias ApiWeb.Plugs.LoadScope

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

  # conn com sessão e (opcionalmente) o usuário já posto pelo load_from_session.
  defp build(current_user, session \\ %{}) do
    conn(:get, "/api/auth/me")
    |> init_test_session(session)
    |> assign(:current_user, current_user)
  end

  test "sem usuário autenticado: scope nil, sem actor/tenant no PlugHelpers" do
    conn = LoadScope.call(build(nil), [])

    assert conn.assigns.scope == nil
    assert Ash.PlugHelpers.get_actor(conn) == nil
    assert Ash.PlugHelpers.get_tenant(conn) == nil
  end

  test "com 1 vínculo e sem clínica na sessão: cai no membership default (o primeiro)" do
    user = create_user()
    clinic = onboard(user)

    conn = LoadScope.call(build(user), [])
    scope = conn.assigns.scope

    assert scope.clinic_id == clinic.id
    assert scope.papel == :owner
    # actor e tenant propagados para as rotas AshJsonApi.
    assert Ash.PlugHelpers.get_actor(conn).id == user.id
    assert Ash.PlugHelpers.get_tenant(conn) == clinic.id
  end

  test "active_clinic_id na sessão escolhe aquela clínica (não o default)" do
    user = create_user()
    _a = onboard(user, "Clínica A")
    b = onboard(user, "Clínica B")

    conn = LoadScope.call(build(user, %{active_clinic_id: b.id}), [])

    assert conn.assigns.scope.clinic_id == b.id
    assert Ash.PlugHelpers.get_tenant(conn) == b.id
  end

  test "sessão aponta clínica sem vínculo ativo do usuário: cai no default" do
    user = create_user()
    a = onboard(user, "Clínica A")

    # Clínica de outra pessoa — o usuário não tem membership nela.
    outro = create_user()
    alheia = onboard(outro, "Clínica Alheia")

    conn = LoadScope.call(build(user, %{active_clinic_id: alheia.id}), [])

    assert conn.assigns.scope.clinic_id == a.id
  end

  test "usuário sem nenhum vínculo ativo: scope só com identidade, tenant não é setado" do
    user = create_user()

    conn = LoadScope.call(build(user), [])
    scope = conn.assigns.scope

    assert scope.user.id == user.id
    assert scope.clinic_id == nil
    # sem clínica ativa → maybe_set_tenant não põe tenant.
    assert Ash.PlugHelpers.get_tenant(conn) == nil
  end
end
