defmodule ApiWeb.Router do
  use ApiWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Sessão + escopo (ADR-014): carrega o usuário da sessão e monta o `Api.Scope`
  # (actor + tenant ativo). Toda rota que fala com o domínio passa por aqui.
  pipeline :authenticated do
    plug :fetch_session
    plug :load_from_session
    # Binding jti↔sub: barra forja "meu jti + sub de outro" sob secret vazada. Roda antes
    # do LoadScope para rejeitar a sessão antes de montar o escopo.
    plug ApiWeb.Plugs.VerifyTokenSubject
    plug ApiWeb.Plugs.LoadScope
  end

  # Fluxo OAuth (Assent): precisa da sessão para o parâmetro de state.
  pipeline :oauth do
    plug :fetch_session
  end

  # Rate limiting dos endpoints de auth (auditoria doc 13, causa A). No-op fora de produção.
  pipeline :rate_limited do
    plug ApiWeb.Plugs.RateLimitAuth
  end

  # AshJsonApi (recursos do domínio) — sob :authenticated, então cada request já chega
  # com actor e `clinic_id` (tenant) resolvidos do escopo, nunca do corpo/URL (09 §8).
  scope "/api/json" do
    pipe_through [:api, :authenticated]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", ApiWeb.AshJsonApiRouter
  end

  # Endpoints de auth com rate limit (auditoria doc 13, causa A): os que geram e-mail/token
  # ou trocam de tenant. No-op fora de produção.
  scope "/api", ApiWeb do
    pipe_through [:api, :authenticated, :rate_limited]

    # Autenticação sem senha (ADR-015, contrato 09 §8).
    post "/auth/magic-link", AuthController, :request_magic_link
    get "/auth/google", AuthController, :google
    post "/auth/switch-tenant", AuthController, :switch_tenant
  end

  scope "/api", ApiWeb do
    pipe_through [:api, :authenticated]

    get "/health", HealthController, :show

    get "/auth/magic-link/callback", AuthController, :magic_link_callback
    get "/auth/me", AuthController, :me
    delete "/auth/sign-out", AuthController, :sign_out

    # Token efêmero de WebSocket (ADR-014, 09 §8).
    get "/realtime/token", AuthController, :realtime_token
  end

  # Máquina OAuth do AshAuthentication (Assent): request + callback do Google. Chama
  # `ApiWeb.AuthStrategyController.success/4` / `failure/3`.
  scope "/" do
    pipe_through :oauth
    auth_routes(ApiWeb.AuthStrategyController, Api.Accounts.User, path: "/api/auth/strategy")
  end

  # Preview da caixa de e-mail em dev: veja os magic links em /dev/mailbox.
  if Application.compile_env(:api, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session]
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
