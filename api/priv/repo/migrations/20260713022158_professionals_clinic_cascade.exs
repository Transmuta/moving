defmodule Api.Repo.Migrations.ProfessionalsClinicCascade do
  @moduledoc """
  `professionals.clinic_id` → `ON DELETE CASCADE` (auditoria doc 13, causa D): apagar a clínica
  apaga seus profissionais.

  Feito por **drop + add constraint** (SQL cru), não por `modify` da coluna: `clinic_id` é usado
  na policy RLS `tenant_isolation` (ADR-018) e o Postgres recusa `ALTER COLUMN TYPE` numa coluna
  referenciada em policy (`0A000 feature_not_supported`). Trocar só a constraint não toca a
  coluna, então a policy continua válida.
  """
  use Ecto.Migration

  def up do
    drop(constraint(:professionals, "professionals_clinic_id_fkey"))

    execute("""
    ALTER TABLE professionals
      ADD CONSTRAINT professionals_clinic_id_fkey
      FOREIGN KEY (clinic_id) REFERENCES clinics(id) ON DELETE CASCADE
    """)
  end

  def down do
    drop(constraint(:professionals, "professionals_clinic_id_fkey"))

    execute("""
    ALTER TABLE professionals
      ADD CONSTRAINT professionals_clinic_id_fkey
      FOREIGN KEY (clinic_id) REFERENCES clinics(id)
    """)
  end
end
