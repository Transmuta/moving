defmodule Api.Accounts.Membership.Validations.NotLastOwner do
  @moduledoc """
  ADR-016 — invariante "≥1 owner por tenant". Impede rebaixar (update) ou remover
  (destroy) o último `owner` de uma clínica. Não-atômica de propósito: precisa contar
  os owners restantes do mesmo `clinic_id` (Membership é global, schema público).
  """
  use Ash.Resource.Validation
  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    data = changeset.data

    removing_owner? =
      case changeset.action_type do
        :destroy ->
          data.papel == :owner

        :update ->
          data.papel == :owner and Ash.Changeset.get_attribute(changeset, :papel) != :owner

        _ ->
          false
      end

    if removing_owner? and other_owners_count(data) == 0 do
      {:error,
       field: :papel, message: "não é possível remover ou rebaixar o único owner da clínica"}
    else
      :ok
    end
  end

  defp other_owners_count(%{clinic_id: clinic_id, id: mid}) do
    Api.Accounts.Membership
    |> Ash.Query.filter(clinic_id == ^clinic_id and papel == :owner and id != ^mid)
    |> Ash.read!(authorize?: false)
    |> length()
  end
end
