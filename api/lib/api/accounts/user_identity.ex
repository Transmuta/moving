defmodule Api.Accounts.UserIdentity do
  @moduledoc """
  Vínculo entre um `User` global e a identidade num provedor OAuth (Google, ADR-015).
  Guarda o par `strategy` + `uid` (o `iss`/`sub` do provedor) — a única chave estável
  para reconhecer a pessoa, mais segura que casar por e-mail. Gerada/gerida pelo
  `AshAuthentication.UserIdentity`.
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  user_identity do
    user_resource Api.Accounts.User
  end

  postgres do
    table "user_identities"
    repo Api.Repo

    # FK sem índice + sem on_delete (auditoria doc 13, causas C/D): indexa `user_id` (lookup
    # por usuário e checagem de cascata) e faz a identidade morrer junto com o `User` — antes
    # o RESTRICT bloqueava apagar um usuário que tivesse login Google.
    references do
      reference :user, on_delete: :delete
    end

    custom_indexes do
      index [:user_id]
    end
  end
end
