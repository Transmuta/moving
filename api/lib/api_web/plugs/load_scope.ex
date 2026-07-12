defmodule ApiWeb.Plugs.LoadScope do
  @moduledoc """
  Monta o `Api.Scope` da requisição (ADR-014) a partir do usuário autenticado
  (`conn.assigns.current_user`, posto pelo `load_from_session`) e do tenant ativo na
  sessão. Roda **depois** do `load_from_session`.

  Resolve o membership ativo assim:
    1. se a sessão tem `active_clinic_id` e existe um `Membership` **ativo** do usuário
       naquela clínica, é ele;
    2. senão, cai no primeiro membership ativo do usuário (default, estilo Vercel);
    3. sem nenhum membership ativo, o scope fica sem tenant (só identidade).

  Além de `assign(:scope, ...)`, propaga `actor` e `tenant` para o `Ash.PlugHelpers`,
  de modo que as rotas AshJsonApi já recebam o actor e o `clinic_id` do escopo — o
  tenant **nunca** vem do corpo/URL (09 §8).
  """
  @behaviour Plug
  import Plug.Conn

  alias Api.Accounts
  alias Api.Accounts.Membership
  alias Api.Scope

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        assign(conn, :scope, nil)

      user ->
        scope = user |> resolve_membership(conn) |> to_scope(user)

        conn
        |> assign(:scope, scope)
        |> Ash.PlugHelpers.set_actor(user)
        |> maybe_set_tenant(scope.clinic_id)
    end
  end

  defp to_scope(nil, user), do: Scope.new(user)
  defp to_scope(%Membership{} = membership, user), do: Scope.with_membership(user, membership)

  defp resolve_membership(user, conn) do
    case get_session(conn, :active_clinic_id) do
      nil ->
        default_membership(user)

      clinic_id ->
        case Accounts.get_active_membership(user.id, clinic_id, authorize?: false) do
          {:ok, %Membership{} = membership} -> membership
          # Sessão aponta uma clínica sem vínculo ativo (revogado): cai no default.
          _ -> default_membership(user)
        end
    end
  end

  defp default_membership(user) do
    user.id
    |> Accounts.list_active_memberships!(authorize?: false)
    |> List.first()
  end

  defp maybe_set_tenant(conn, nil), do: conn
  defp maybe_set_tenant(conn, clinic_id), do: Ash.PlugHelpers.set_tenant(conn, clinic_id)
end
