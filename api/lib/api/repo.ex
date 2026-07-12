defmodule Api.Repo do
  use AshPostgres.Repo, otp_app: :api

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  def prefer_transaction? do
    false
  end

  @tenant_guc "movimento.clinic_id"

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

  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    # citext: coluna case-insensitive do User.email (:ci_string).
    ["ash-functions", "citext"]
  end
end
