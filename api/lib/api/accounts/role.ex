defmodule Api.Accounts.Role do
  @moduledoc """
  Papel de um membro por tenant (RBAC). ADR-016: 4 perfis fixos, do mais forte ao
  mais fraco. `owner` é a dona (>=1 por tenant, invariante em `Membership`).
  `recepcao` corresponde ao `membro` do protótipo.
  """
  use Ash.Type.Enum, values: [:owner, :admin, :profissional, :recepcao]
end
