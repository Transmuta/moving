defmodule Api.Directory.ProfessionalCascadeTest do
  @moduledoc """
  `professionals.clinic_id` → `ON DELETE CASCADE` (auditoria doc 13, causa D): apagar a clínica
  apaga seus profissionais. Como não há ação `destroy` de `Clinic`, o teste apaga a linha da
  clínica direto no banco e confere que o profissional some junto (o cascade é da FK).
  """
  use Api.DataCase, async: false

  import Ecto.Query

  alias Api.Accounts
  alias Api.Directory

  test "apagar a clínica cascateia nos profissionais" do
    email = "cascade-#{System.unique_integer([:positive])}@example.com"
    user = Accounts.register_user!("Dono", email, authorize?: false)
    clinic = Accounts.onboard_clinic!("Clínica Cascade", %{}, actor: user)
    prof = Directory.create_professional!("Dra. Y", %{}, tenant: clinic.id, actor: user)

    prof_exists? = fn ->
      Repo.exists?(from(p in "professionals", where: p.id == ^Ecto.UUID.dump!(prof.id)))
    end

    assert prof_exists?.()

    {1, _} = Repo.delete_all(from(c in "clinics", where: c.id == ^Ecto.UUID.dump!(clinic.id)))

    refute prof_exists?.()
  end
end
