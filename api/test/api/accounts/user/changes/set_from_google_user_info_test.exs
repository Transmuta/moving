defmodule Api.Accounts.User.Changes.SetFromGoogleUserInfoTest do
  @moduledoc """
  Mapeamento do `user_info` verificado do Google (ADR-015) → atributos do `User`.
  Prova as três resoluções de nome: nome do Google, fallback pela parte local do e-mail,
  e o default "Usuário" quando não há nem nome nem e-mail.
  """
  use Api.DataCase, async: true

  alias Api.Accounts.User
  alias Api.Accounts.User.Changes.SetFromGoogleUserInfo

  defp apply_change(user_info) do
    User
    |> Ash.Changeset.new()
    |> Ash.Changeset.set_argument(:user_info, user_info)
    |> SetFromGoogleUserInfo.change([], %{})
  end

  test "usa e-mail e nome vindos do Google" do
    cs = apply_change(%{"email" => "ana@example.com", "name" => "Ana Souza"})

    assert to_string(Ash.Changeset.get_attribute(cs, :email)) == "ana@example.com"
    assert Ash.Changeset.get_attribute(cs, :nome) == "Ana Souza"
  end

  test "sem nome no payload: defaulta pela parte local do e-mail" do
    cs = apply_change(%{"email" => "bruno@example.com"})

    assert Ash.Changeset.get_attribute(cs, :nome) == "bruno"
  end

  test "sem nome e sem e-mail: nome default 'Usuário'" do
    cs = apply_change(%{})

    assert Ash.Changeset.get_attribute(cs, :nome) == "Usuário"
    assert Ash.Changeset.get_attribute(cs, :email) == nil
  end
end
