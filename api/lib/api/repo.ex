defmodule Api.Repo do
  use AshPostgres.Repo, otp_app: :api

  # Lista os schemas de tenant para rodar as tenant migrations em todos eles
  # (ADR-014, strategy :context). Um schema por clínica: `tenant_<uuid>`.
  def all_tenants do
    import Ecto.Query, only: [from: 2]
    all(from(c in "clinics", select: fragment("? || ?", "tenant_", type(c.id, :string))))
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  def prefer_transaction? do
    false
  end

  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    # citext: coluna case-insensitive do User.email (:ci_string).
    ["ash-functions", "citext"]
  end
end
