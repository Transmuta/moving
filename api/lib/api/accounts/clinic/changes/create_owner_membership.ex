defmodule Api.Accounts.Clinic.Changes.CreateOwnerMembership do
  @moduledoc """
  ADR-016: ao criar uma clínica (`onboard`), o usuário atual vira o `owner` dela — na
  mesma transação. Garante a invariante "≥1 owner por tenant" desde o nascimento do
  tenant e dá acesso a quem criou. Sem actor (chamada de sistema), não cria nada.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, clinic ->
      case context.actor do
        %{id: user_id} when not is_nil(user_id) ->
          {:ok, membership} =
            Api.Accounts.invite_member(
              %{papel: :owner, user_id: user_id, clinic_id: clinic.id},
              authorize?: false
            )

          {:ok, _active} = Api.Accounts.accept_invite(membership, authorize?: false)
          {:ok, clinic}

        _ ->
          {:ok, clinic}
      end
    end)
  end
end
