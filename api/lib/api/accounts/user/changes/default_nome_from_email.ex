defmodule Api.Accounts.User.Changes.DefaultNomeFromEmail do
  @moduledoc """
  Registro auth-first (magic link) só carrega o e-mail — mas `User.nome` é obrigatório.
  Quando o `nome` não vem, defaulta para a parte local do e-mail, deixando um nome
  legível para "completar depois". No login por Google o nome real vem do `user_info`,
  então este change só atua na ausência.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_attribute(changeset, :nome) do
        nil ->
          email = changeset |> Ash.Changeset.get_attribute(:email) |> to_string()
          nome = email |> String.split("@") |> List.first()
          Ash.Changeset.force_change_attribute(changeset, :nome, nome)

        _nome ->
          changeset
      end
    end)
  end
end
