defmodule Api.Repo do
  use AshPostgres.Repo, otp_app: :api

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  # Abre transação por ação (default do AshPostgres). Necessário para o RLS: a GUC de
  # tenant é `SET LOCAL` (transação-local), setada no `on_transaction_begin/1` abaixo.
  # Sem transação não haveria onde escopar a GUC com segurança (ADR-018).
  @impl true
  def prefer_transaction? do
    true
  end

  @tenant_guc "movimento.clinic_id"

  @doc """
  Injeta a GUC `movimento.clinic_id` no início de toda transação que tem um tenant no
  contexto (ADR-018). É o ponto de injeção automático: qualquer ação Ash sobre recurso
  por-tenant (`strategy :attribute`) abre transação, cai aqui e passa a enxergar só as
  linhas do `clinic_id` ativo. Transações sem tenant (recursos globais) não setam nada.
  """
  @impl true
  def on_transaction_begin(reason) do
    case tenant_from_reason(reason) do
      nil ->
        :ok

      tenant ->
        query!("SELECT set_config($1, $2, true)", [@tenant_guc, to_string(tenant)])
        :ok
    end
  end

  defp tenant_from_reason(%{data_layer_context: %{tenant: tenant}}) when not is_nil(tenant),
    do: tenant

  defp tenant_from_reason(%{metadata: %{query: %{tenant: tenant}}}) when not is_nil(tenant),
    do: tenant

  defp tenant_from_reason(_reason), do: nil

  @doc """
  Roda `fun` com o GUC `movimento.clinic_id` setado (transação-local) para as RLS
  policies (ADR-018). Toda operação em recurso por-tenant deve passar por aqui —
  no app, o plug de scope da sessão (ADR-014) é quem chama. `SET LOCAL` exige a
  transação; sem GUC as policies falham fechando (0 linhas).
  """
  def with_clinic(clinic_id, fun) when is_binary(clinic_id) do
    transaction(fn ->
      query!("SELECT set_config($1, $2, true)", [@tenant_guc, clinic_id])
      fun.()
    end)
  end

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    # citext: coluna case-insensitive do User.email (:ci_string).
    ["ash-functions", "citext"]
  end
end
