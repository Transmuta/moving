defmodule Api.Repo.Migrations.ProfessionalsRls do
  @moduledoc """
  RLS como defesa-em-profundidade da tenancy por atributo (ADR-018). Mesmo que o
  filtro do Ash (`WHERE clinic_id = ...`) seja contornado (query crua, bug,
  authorize?: false sem tenant), o Postgres só devolve linhas do `clinic_id` setado
  na GUC `movimento.clinic_id`. Sem GUC → 0 linhas (fail-closed).

  Roda como `postgres` (owner) no deploy/migrate; o app conecta como um role
  NOSUPERUSER/NOBYPASSRLS que fica sujeito à policy.
  """
  use Ecto.Migration

  def up do
    execute "ALTER TABLE professionals ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE professionals FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY tenant_isolation ON professionals
      USING (clinic_id = current_setting('movimento.clinic_id', true)::uuid)
      WITH CHECK (clinic_id = current_setting('movimento.clinic_id', true)::uuid)
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS tenant_isolation ON professionals"
    execute "ALTER TABLE professionals NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE professionals DISABLE ROW LEVEL SECURITY"
  end
end
