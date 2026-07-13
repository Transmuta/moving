defmodule Api.Directory.ProfessionalTenantIsolationTest do
  @moduledoc """
  Isolamento por-tenant do `Professional` (ADR-017), a regressão que faltava (auditoria doc 13,
  causa J). Prova a camada **primária**: o `strategy :attribute` injeta `WHERE clinic_id = tenant`
  em toda query, então uma clínica nunca enxerga o profissional de outra.

  A RLS (ADR-018, defesa-em-profundidade) **não** é exercida aqui: o sandbox de teste conecta
  como `postgres` (BYPASSRLS). Ela foi provada manualmente na auditoria conectando como
  `movimento_app`.
  """
  use Api.DataCase, async: false

  alias Api.Accounts
  alias Api.Directory

  defp owner_of_clinic(nome) do
    email = "iso-#{System.unique_integer([:positive])}@example.com"
    user = Accounts.register_user!("Dono #{nome}", email, authorize?: false)
    clinic = Accounts.onboard_clinic!(nome, %{}, actor: user)
    {user, clinic}
  end

  test "cada clínica só vê o próprio profissional (isolamento por atributo)" do
    {user_a, clinic_a} = owner_of_clinic("Clínica A")
    {user_b, clinic_b} = owner_of_clinic("Clínica B")

    prof_a = Directory.create_professional!("Dra. A", %{}, tenant: clinic_a.id, actor: user_a)
    prof_b = Directory.create_professional!("Dr. B", %{}, tenant: clinic_b.id, actor: user_b)

    lista_a = Directory.list_professionals!(tenant: clinic_a.id, actor: user_a)
    lista_b = Directory.list_professionals!(tenant: clinic_b.id, actor: user_b)

    assert Enum.map(lista_a, & &1.id) == [prof_a.id]
    assert Enum.map(lista_b, & &1.id) == [prof_b.id]
    refute prof_a.id in Enum.map(lista_b, & &1.id)
  end
end
