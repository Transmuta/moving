defmodule Api.Mailer do
  @moduledoc """
  Mailer da aplicação (Swoosh). Em dev usa o adapter `Local` (caixa em memória,
  previewável); em teste, o adapter `Test`; em prod, o adapter configurado por env
  no `runtime.exs`. O único remetente de e-mail hoje é o magic link (ADR-015).
  """
  use Swoosh.Mailer, otp_app: :api
end
