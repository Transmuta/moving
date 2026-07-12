defmodule Api.Accounts.AuthFlowTest do
  @moduledoc """
  Fluxo de autenticação sem senha (ADR-015) + resolução de escopo (ADR-014): pedir
  magic link → e-mail → sign-in cria/vincula o `User` → onboard vira owner → o escopo
  resolve o tenant ativo e o papel.
  """
  use Api.DataCase, async: false

  alias Api.Accounts
  alias Api.Scope

  defp email, do: "user-#{System.unique_integer([:positive])}@example.com"

  defp request_and_capture_token(addr) do
    :ok = Accounts.request_magic_link(addr)
    assert_receive {:email, email}, 1_000
    [_, token] = Regex.run(~r/token=([\w.\-]+)/, email.text_body)
    token
  end

  test "magic link envia e-mail para o endereço pedido" do
    addr = email()
    assert :ok = Accounts.request_magic_link(addr)

    assert_receive {:email, email}, 1_000
    assert email.subject =~ "link de acesso"
    assert [{_, ^addr}] = email.to
    # O link aponta para o callback do WEB (BFF, ADR-005), não para a API.
    assert email.text_body =~ "/auth/callback?token="
  end

  test "sign-in por magic link cria o User com nome defaultado do e-mail" do
    addr = email()
    token = request_and_capture_token(addr)

    {:ok, user} = Accounts.sign_in_with_magic_link(token)

    assert to_string(user.email) == addr
    # DefaultNomeFromEmail: nome = parte local do e-mail.
    assert user.nome == addr |> String.split("@") |> List.first()
    assert user.__metadata__.token
  end

  test "onboard cria a clínica E o Membership owner ativo (ADR-016)" do
    addr = email()
    token = request_and_capture_token(addr)
    {:ok, user} = Accounts.sign_in_with_magic_link(token)

    {:ok, clinic} = Accounts.onboard_clinic("Clínica Teste", %{}, actor: user)

    memberships = Accounts.list_active_memberships!(user.id, authorize?: false)
    assert [membership] = memberships
    assert membership.papel == :owner
    assert membership.status == :ativo
    assert membership.clinic_id == clinic.id
  end

  test "o escopo deriva tenant/papel do Membership ativo (Ash.Scope.ToOpts)" do
    addr = email()
    token = request_and_capture_token(addr)
    {:ok, user} = Accounts.sign_in_with_magic_link(token)
    {:ok, clinic} = Accounts.onboard_clinic("Clínica Escopo", %{}, actor: user)

    [membership] = Accounts.list_active_memberships!(user.id, authorize?: false)
    scope = Scope.with_membership(user, membership)

    assert scope.clinic_id == clinic.id
    assert scope.papel == :owner
    # ToOpts: actor = user, tenant = clinic_id.
    assert {:ok, ^user} = Ash.Scope.ToOpts.get_actor(scope)
    assert {:ok, clinic_id} = Ash.Scope.ToOpts.get_tenant(scope)
    assert clinic_id == clinic.id
  end

  test "onboard exige actor autenticado (policy actor_present)" do
    assert {:error, %Ash.Error.Forbidden{}} = Accounts.onboard_clinic("Sem Dono", %{})
  end
end
