defmodule ApiWeb.Plugs.VerifyTokenSubjectTest do
  @moduledoc """
  Prova do binding jti↔sub (defesa contra forja "meu jti + sub de outro" sob secret vazada).
  """
  use Api.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Api.Accounts
  alias ApiWeb.Plugs.VerifyTokenSubject

  # Loga um usuário novo via magic link e devolve {user, token_de_sessão}.
  defp sign_in do
    email = "user-#{System.unique_integer([:positive])}@example.com"
    :ok = Accounts.request_magic_link(email)
    assert_receive {:email, mail}, 1_000
    [_, token] = Regex.run(~r/token=([\w.\-]+)/, mail.text_body)
    {:ok, user} = Accounts.sign_in_with_magic_link(token)
    {user, user.__metadata__.token}
  end

  defp conn_with(token, current_user) do
    conn(:get, "/api/auth/me")
    |> init_test_session(%{})
    |> put_session("user_token", token)
    |> assign(:current_user, current_user)
  end

  test "sessão legítima passa (jti↔sub batem)" do
    {user, token} = sign_in()

    conn = VerifyTokenSubject.call(conn_with(token, user), [])

    refute conn.halted
  end

  test "rejeita jti do A com sub do B (forja sob secret vazada)" do
    {_a, token_a} = sign_in()
    {b, _token_b} = sign_in()

    # Forja: mantém as claims do A (inclui jti_A, que ESTÁ na tabela) mas troca o sub p/ o B,
    # e re-assina com a secret (o que o atacante faria). A assinatura é válida; o buraco que
    # o plug fecha é justamente o jti_A não pertencer ao sub do B.
    {:ok, claims_a} = AshAuthentication.Jwt.peek(token_a)
    forged_claims = Map.put(claims_a, "sub", AshAuthentication.user_to_subject(b))

    signer =
      Joken.Signer.create("HS256", Application.fetch_env!(:api, :token_signing_secret))

    {:ok, forged_token} = Joken.Signer.sign(forged_claims, signer)

    # No pipeline real, o load_from_session teria posto current_user = B (do sub forjado).
    conn = VerifyTokenSubject.call(conn_with(forged_token, b), [])

    assert conn.halted
    assert conn.status == 401
  end
end
