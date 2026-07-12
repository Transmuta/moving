defmodule Api.Accounts.MemberStatus do
  @moduledoc """
  Situação do vínculo de um membro. `pendente` = convidado, ainda não aceitou;
  `ativo` = aceitou (via magic link/Google, ADR-015).
  """
  use Ash.Type.Enum, values: [:ativo, :pendente]
end
