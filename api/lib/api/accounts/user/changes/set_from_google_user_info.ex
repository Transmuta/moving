defmodule Api.Accounts.User.Changes.SetFromGoogleUserInfo do
  @moduledoc """
  Mapeia o `user_info` verificado do Google (ADR-015) para os atributos do `User`:
  e-mail (identidade de login) e nome. Usado no `register_with_google` (upsert por
  e-mail), que serve tanto de registro quanto de login.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info) || %{}

    email = user_info["email"]
    nome = user_info["name"] || default_nome(email)

    changeset
    |> Ash.Changeset.change_attribute(:email, email)
    |> Ash.Changeset.change_attribute(:nome, nome)
  end

  defp default_nome(nil), do: "Usuário"
  defp default_nome(email), do: email |> to_string() |> String.split("@") |> List.first()
end
