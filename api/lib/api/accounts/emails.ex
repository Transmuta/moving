defmodule Api.Accounts.Emails do
  @moduledoc """
  E-mails do domínio de contas. Hoje só o magic link (ADR-015): o único fator de
  autenticação por posse do e-mail. O link aponta para o **web** (BFF), não para a API
  (ADR-005): o SvelteKit em `/auth/callback` valida o token via API e assina a sessão no
  domínio do web. `web_app_url` vem do config (dev: http://localhost:5173).
  """
  import Swoosh.Email

  @doc """
  Monta e envia o e-mail de magic link. Recebe um `%User{}` (já existe) ou uma string
  de e-mail (ainda não existe — o primeiro acesso cria o `User`).
  """
  def send_magic_link_email(user_or_email, token) do
    address =
      case user_or_email do
        %{email: email} -> to_string(email)
        email -> to_string(email)
      end

    link = Api.web_app_url() <> "/auth/callback?" <> URI.encode_query(token: token)

    new()
    |> to(address)
    |> from({"Movimento", "nao-responda@movimento.local"})
    |> subject("Seu link de acesso ao Movimento")
    |> text_body("""
    Olá!

    Use o link abaixo para entrar no Movimento (expira em breve):

    #{link}

    Se você não solicitou este acesso, ignore este e-mail.
    """)
    |> Api.Mailer.deliver()
  end
end
