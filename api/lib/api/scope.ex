defmodule Api.Scope do
  @moduledoc """
  O escopo da requisição (ADR-014): quem é o usuário e qual o tenant ativo. Derivado
  do `Membership` ativo na sessão pelo `ApiWeb.Plugs.LoadScope`. É a **única** fonte do
  `tenant` (clinic_id) e do `actor` das ações Ash — nunca vindo do corpo/URL (09 §8).

  Implementa `Ash.Scope.ToOpts`, então basta passar `scope: scope` às chamadas de ação
  que o Ash extrai `actor` (o `User`) e `tenant` (o `clinic_id`). `papel` e
  `professional_id` são informativos (espelho de UI e `/auth/me`); a autoridade real é a
  policy do servidor, que consulta o `Membership`.
  """
  @enforce_keys [:user]
  defstruct [:user, :clinic_id, :papel, :professional_id, :membership]

  @type t :: %__MODULE__{
          user: Api.Accounts.User.t() | nil,
          clinic_id: Ecto.UUID.t() | nil,
          papel: atom() | nil,
          professional_id: Ecto.UUID.t() | nil,
          membership: Api.Accounts.Membership.t() | nil
        }

  @doc "Escopo só com o usuário autenticado, sem tenant ativo (antes de escolher a clínica)."
  def new(user), do: %__MODULE__{user: user}

  @doc """
  Escopo com tenant ativo, derivado de um `Membership` (que traz papel e professional_id).
  """
  def with_membership(user, %Api.Accounts.Membership{} = membership) do
    %__MODULE__{
      user: user,
      clinic_id: membership.clinic_id,
      papel: membership.papel,
      professional_id: membership.professional_id,
      membership: membership
    }
  end

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{user: user}), do: {:ok, user}

    def get_tenant(%{clinic_id: nil}), do: :error
    def get_tenant(%{clinic_id: clinic_id}), do: {:ok, clinic_id}

    def get_context(_scope), do: :error
    def get_tracer(_scope), do: :error
    def get_authorize?(_scope), do: :error
  end
end
