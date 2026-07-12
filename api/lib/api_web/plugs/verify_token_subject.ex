defmodule ApiWeb.Plugs.VerifyTokenSubject do
  @moduledoc """
  Defesa contra confusão `jti`↔`sub` sob comprometimento da `token_signing_secret`.

  O `require_token_presence` só confere que o `jti` **existe** na tabela `tokens` — não
  que o `subject` guardado bate com o `sub` do JWT. Um atacante de posse da secret poderia
  forjar `{ jti = um válido qualquer (o dele), sub = de outra pessoa }` e se passar pela
  vítima. Este plug fecha esse buraco: exige que o `subject` do registro daquele `jti` seja
  **exatamente** o `sub` apresentado. Mismatch (só acontece em ataque) → 401 + alerta.

  Roda depois do `load_from_session` e antes do `LoadScope` (rejeita antes de montar o escopo).
  """
  @behaviour Plug
  import Plug.Conn
  require Ash.Query
  require Logger

  @session_key "user_token"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_user: %{} = _user}} = conn, _opts) do
    with token when is_binary(token) <- get_session(conn, @session_key),
         {:ok, %{"jti" => jti, "sub" => sub}} <- AshAuthentication.Jwt.peek(token),
         %Api.Accounts.Token{subject: ^sub} <- token_record(jti) do
      conn
    else
      _ -> reject(conn)
    end
  end

  # Sem usuário autenticado: nada a verificar.
  def call(conn, _opts), do: conn

  defp token_record(jti) do
    Api.Accounts.Token
    |> Ash.Query.filter(jti == ^jti and purpose == "user")
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp reject(conn) do
    Logger.warning(
      "Sessão rejeitada: jti↔sub não confere (possível forja de token com secret vazada)."
    )

    conn
    |> clear_session()
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
