defmodule Api.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sender do magic link (ADR-015). Delega ao `Api.Accounts.Emails`, que constrói e
  entrega o e-mail via `Api.Mailer` (Swoosh). Recebe um `%User{}` (já existe) ou uma
  string de e-mail (primeiro acesso — o `User` ainda não existe).
  """
  use AshAuthentication.Sender

  @impl true
  def send(user_or_email, token, _opts) do
    Api.Accounts.Emails.send_magic_link_email(user_or_email, token)
  end
end
