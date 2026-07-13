defmodule Api.Accounts.Checks.HasClinicRoleTest do
  @moduledoc """
  RBAC por tenant (ADR-016). Prova que o check só concede acesso a quem é membro
  **ativo** da clínica relevante, com o papel exigido — e nega o resto (não-membro,
  papel errado, vínculo ainda pendente, actor anônimo, sem tenant).

  Dois níveis:
    * integração pela policy real do `invite` (único uso em produção hoje —
      `clinic_from: {:argument, :clinic_id}`): owner convida, estranho não;
    * unidade em `match?/3` cobrindo os modos `:tenant`/`:record` e o filtro de papéis,
      que existem mas ainda não estão ligados a uma ação (recursos futuros).
  """
  use Api.DataCase, async: false

  alias Api.Accounts
  alias Api.Accounts.Checks.HasClinicRole

  defp create_user do
    email = "user-#{System.unique_integer([:positive])}@example.com"
    :ok = Accounts.request_magic_link(email)
    assert_receive {:email, mail}, 1_000
    [_, token] = Regex.run(~r/token=([\w.\-]+)/, mail.text_body)
    {:ok, user} = Accounts.sign_in_with_magic_link(token)
    user
  end

  defp owner_with_clinic do
    owner = create_user()

    {:ok, clinic} =
      Accounts.onboard_clinic("Clínica #{System.unique_integer([:positive])}", %{}, actor: owner)

    {owner, clinic}
  end

  # Um contexto de policy no formato que o check lê: `%{subject: subject}`, onde o
  # subject expõe `.tenant` (modo :tenant) ou `.data` (modo :record) — exatamente os
  # campos que uma `Ash.Query`/`Ash.Changeset` carrega em produção.
  defp tenant_ctx(clinic_id), do: %{subject: %{tenant: clinic_id}}

  describe "policy real do :invite (clinic_from: {:argument, :clinic_id})" do
    test "owner ativo da clínica é AUTORIZADO a convidar (clinic_id vem do argumento)" do
      {owner, clinic} = owner_with_clinic()
      convidado = create_user()

      assert Accounts.can_invite_member?(owner, %{
               user_id: convidado.id,
               clinic_id: clinic.id,
               papel: :recepcao
             })
    end

    test "estranho (não-membro) NÃO é autorizado a convidar" do
      {_owner, clinic} = owner_with_clinic()
      estranho = create_user()
      convidado = create_user()

      refute Accounts.can_invite_member?(estranho, %{
               user_id: convidado.id,
               clinic_id: clinic.id,
               papel: :recepcao
             })
    end
  end

  describe "match?/3 — modo :tenant" do
    test "membro ativo casa (roles :any, o default)" do
      {owner, clinic} = owner_with_clinic()
      assert HasClinicRole.match?(owner, tenant_ctx(clinic.id), [])
    end

    test "casa quando o papel do membro está entre os exigidos" do
      {owner, clinic} = owner_with_clinic()
      assert HasClinicRole.match?(owner, tenant_ctx(clinic.id), roles: [:owner, :admin])
    end

    test "NÃO casa quando o papel exigido não é o do membro" do
      {owner, clinic} = owner_with_clinic()
      refute HasClinicRole.match?(owner, tenant_ctx(clinic.id), roles: [:recepcao])
    end

    test "NÃO casa para não-membro da clínica" do
      {_owner, clinic} = owner_with_clinic()
      estranho = create_user()
      refute HasClinicRole.match?(estranho, tenant_ctx(clinic.id), [])
    end

    test "vínculo apenas PENDENTE não concede acesso (só :ativo conta)" do
      {_owner, clinic} = owner_with_clinic()
      convidado = create_user()

      # authorize?: false porque o :invite hoje não resolve outro user por id sob a
      # policy do User (id == actor.id); aqui só precisamos do vínculo pendente existir.
      {:ok, _pendente} =
        Accounts.invite_member(
          %{papel: :recepcao, user_id: convidado.id, clinic_id: clinic.id},
          authorize?: false
        )

      refute HasClinicRole.match?(convidado, tenant_ctx(clinic.id), [])
    end

    test "actor anônimo (nil) nunca casa" do
      {_owner, clinic} = owner_with_clinic()
      refute HasClinicRole.match?(nil, tenant_ctx(clinic.id), [])
    end

    test "sem tenant ativo (clinic_id nil) nunca casa" do
      {owner, _clinic} = owner_with_clinic()
      refute HasClinicRole.match?(owner, tenant_ctx(nil), [])
    end
  end

  describe "match?/3 — modo :record (clinic_id do próprio registro)" do
    test "resolve o clinic_id de changeset.data e casa o membro ativo" do
      {owner, clinic} = owner_with_clinic()
      ctx = %{subject: %{data: %{clinic_id: clinic.id}}}
      assert HasClinicRole.match?(owner, ctx, clinic_from: :record)
    end

    test "registro sem clinic_id não casa" do
      {owner, _clinic} = owner_with_clinic()
      ctx = %{subject: %{data: %{}}}
      refute HasClinicRole.match?(owner, ctx, clinic_from: :record)
    end
  end
end
