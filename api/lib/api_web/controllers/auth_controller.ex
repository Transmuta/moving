defmodule ApiWeb.AuthController do
  @moduledoc """
  Endpoints de autenticação e sessão (ADR-015, contrato 09 §8). Sem senha: magic link
  e Google (o hand-off OAuth em si é feito pelo `ApiWeb.AuthStrategyController`, via
  Assent). Aqui ficam o pedido de magic link, o callback que assina a sessão, o
  `/me`, a troca de tenant e o sign-out.
  """
  use ApiWeb, :controller

  alias Api.Accounts
  alias Api.Accounts.Membership
  alias Api.Scope
  alias AshAuthentication.Plug.Helpers

  # POST /api/auth/magic-link {email} — dispara o e-mail. Resposta NEUTRA (não revela se
  # o e-mail existe), ADR-015 / 09 §8.
  def request_magic_link(conn, params) do
    email = params["email"] || get_in(params, ["user", "email"])

    if is_binary(email) and email != "" do
      # Best-effort: erros (e-mail inválido etc.) não vazam existência de conta.
      _ = Accounts.request_magic_link(email)
    end

    json(conn, %{ok: true})
  end

  # GET /api/auth/magic-link/callback?token=… — valida o token, cria/vincula o User e
  # assina a sessão. Redireciona ao app web.
  def magic_link_callback(conn, %{"token" => token}) do
    case Accounts.sign_in_with_magic_link(token) do
      {:ok, user} ->
        conn
        |> Helpers.store_in_session(user)
        |> redirect(external: Api.web_app_url())

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> redirect(external: Api.web_app_url() <> "/login?erro=magic_link")
    end
  end

  def magic_link_callback(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing_token"})
  end

  # GET /api/auth/google — entrada limpa que leva ao fluxo OAuth (Assent) montado sob
  # /api/auth/strategy pelo AuthStrategyController.
  def google(conn, _params) do
    redirect(conn, to: "/api/auth/strategy/user/google")
  end

  # GET /api/auth/me — identidade global + memberships + tenant ativo (ADR-014, 09 §8).
  def me(conn, _params) do
    case conn.assigns[:scope] do
      %Scope{user: user} = scope ->
        memberships = Accounts.list_active_memberships!(user.id, authorize?: false)

        json(conn, %{
          user: %{id: user.id, nome: user.nome, email: to_string(user.email)},
          active_clinic_id: scope.clinic_id,
          papel: scope.papel,
          professional_id: scope.professional_id,
          memberships: Enum.map(memberships, &membership_json/1)
        })

      _ ->
        unauthenticated(conn)
    end
  end

  # POST /api/auth/switch-tenant {clinic_id} — valida o vínculo ativo e grava o tenant
  # ativo na sessão. Devolve o novo /me.
  def switch_tenant(conn, %{"clinic_id" => clinic_id}) do
    case conn.assigns[:scope] do
      %Scope{user: user} ->
        case Accounts.get_active_membership(user.id, clinic_id, authorize?: false) do
          {:ok, %Membership{}} ->
            conn
            |> put_session(:active_clinic_id, clinic_id)
            |> assign(:scope, nil)
            |> reload_scope(user, clinic_id)
            |> me(%{})

          _ ->
            conn |> put_status(:forbidden) |> json(%{error: "no_active_membership"})
        end

      _ ->
        unauthenticated(conn)
    end
  end

  def switch_tenant(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing_clinic_id"})
  end

  # DELETE /api/auth/sign-out — invalida a sessão. Revoga o token no servidor (não só
  # limpa o cookie): mesmo um cookie capturado deixa de valer (o `jti` vira revogado).
  def sign_out(conn, _params) do
    conn
    |> Helpers.revoke_session_tokens(:api)
    |> clear_session()
    |> send_resp(:no_content, "")
  end

  # GET /api/realtime/token — token efêmero (Phoenix.Token) para o WebSocket dos Channels
  # (ADR-014, 09 §8). Escopo do token: `user_id` + `clinic_id` ativo, para o `join`
  # validar o tópico. Vida curta; trocar de tenant reemite (o BFF chama de novo). É o
  # único token que vai ao browser — o resto é cookie de sessão.
  @realtime_salt "realtime socket"
  @realtime_max_age 900

  def realtime_token(conn, _params) do
    case conn.assigns[:scope] do
      %Scope{user: user, clinic_id: clinic_id} when is_binary(clinic_id) ->
        token =
          Phoenix.Token.sign(
            ApiWeb.Endpoint,
            @realtime_salt,
            %{user_id: user.id, clinic_id: clinic_id},
            max_age: @realtime_max_age
          )

        expires_at =
          DateTime.utc_now()
          |> DateTime.add(@realtime_max_age, :second)
          |> DateTime.to_iso8601()

        json(conn, %{token: token, expires_at: expires_at})

      %Scope{} ->
        conn |> put_status(:conflict) |> json(%{error: "no_active_clinic"})

      _ ->
        unauthenticated(conn)
    end
  end

  # Reconstrói o scope em memória após a troca de tenant, para o /me refletir na hora.
  defp reload_scope(conn, user, clinic_id) do
    case Accounts.get_active_membership(user.id, clinic_id, authorize?: false) do
      {:ok, %Membership{} = membership} ->
        assign(conn, :scope, Scope.with_membership(user, membership))

      _ ->
        assign(conn, :scope, Scope.new(user))
    end
  end

  defp membership_json(%Membership{} = m) do
    %{
      clinic_id: m.clinic_id,
      clinic_nome: m.clinic && m.clinic.nome,
      papel: m.papel,
      professional_id: m.professional_id
    }
  end

  defp unauthenticated(conn) do
    conn |> put_status(:unauthorized) |> json(%{error: "not_authenticated"})
  end
end
