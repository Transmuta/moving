defmodule Api.Accounts.Checks.HasClinicRole do
  @moduledoc """
  Check de RBAC por tenant (ADR-016): o actor tem um `Membership` **ativo** na clínica
  relevante, opcionalmente com um dos papéis exigidos. Consulta o `Membership`
  (`authorize?: false`, sem recursão de policy) — usada em mutações, onde uma FilterCheck
  declarativa não cabe.

  Opções:
    * `:roles` — lista de papéis aceitos, ou `:any` (qualquer membro ativo). Default `:any`.
    * `:clinic_from` — de onde tirar o `clinic_id`:
        * `:tenant` (default) — o tenant ativo (recursos por-atributo, ex. Professional);
        * `:record` — `changeset.data.clinic_id` (update/destroy de recurso global);
        * `{:argument, name}` — um argumento da ação (ex. o `:clinic_id` do convite).
  """
  use Ash.Policy.SimpleCheck
  require Ash.Query

  alias Api.Accounts.Membership

  @impl true
  def describe(opts) do
    "actor é membro ativo (#{inspect(Keyword.get(opts, :roles, :any))}) da clínica " <>
      "(#{inspect(Keyword.get(opts, :clinic_from, :tenant))})"
  end

  @impl true
  def match?(actor, context, opts) do
    with %{id: actor_id} when not is_nil(actor_id) <- actor,
         cid when is_binary(cid) <- clinic_id(context, opts) do
      Membership
      |> Ash.Query.filter(user_id == ^actor_id and clinic_id == ^cid and status == :ativo)
      |> filter_roles(Keyword.get(opts, :roles, :any))
      |> Ash.Query.limit(1)
      |> Ash.read!(authorize?: false)
      |> Enum.any?()
    else
      _ -> false
    end
  end

  defp filter_roles(query, :any), do: query
  defp filter_roles(query, roles) when is_list(roles), do: Ash.Query.filter(query, papel in ^roles)

  defp clinic_id(%{subject: subject}, opts) do
    case Keyword.get(opts, :clinic_from, :tenant) do
      :tenant -> normalize(Map.get(subject, :tenant))
      :record -> subject |> Map.get(:data) |> record_clinic_id()
      {:argument, name} -> normalize(Ash.Changeset.get_argument(subject, name))
    end
  end

  defp clinic_id(_context, _opts), do: nil

  defp record_clinic_id(%{clinic_id: clinic_id}), do: normalize(clinic_id)
  defp record_clinic_id(_), do: nil

  defp normalize(nil), do: nil
  defp normalize(value), do: to_string(value)
end
