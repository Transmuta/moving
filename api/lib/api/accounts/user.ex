defmodule Api.Accounts.User do
  @moduledoc """
  A identidade global de login (ADR-014). Uma pessoa = um `User`, no schema público,
  ligada a N clínicas por N `Membership`s. Separado de `Professional` (que é por-tenant).

  Autenticação **sem senha** (ADR-015): Google OAuth + Magic Link. O `AshAuthentication`
  cuida dos tokens (recurso `Api.Accounts.Token`) e das estratégias; a resolução do tenant
  ativo e do papel vive na sessão/escopo (ver `ApiWeb.Plugs.LoadScope`), não aqui.
  """
  use Ash.Resource,
    otp_app: :api,
    domain: Api.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Api.Accounts.Token
      signing_secret Api.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        # Callback GET direto assina a sessão (contrato 09 §8): o link do e-mail leva
        # ao `/auth/magic-link/callback?token=…`, sem página intermediária de interação.
        require_interaction? false

        sender Api.Accounts.User.Senders.SendMagicLinkEmail
      end

      # Google OAuth (ADR-015). URLs de authorize/token/userinfo são preset pelo Google;
      # client_id/secret/redirect_uri vêm de `Api.Secrets` (env). Registro = login (upsert
      # por e-mail verificado) via `register_with_google`.
      google do
        client_id Api.Secrets
        redirect_uri Api.Secrets
        client_secret Api.Secrets
        # Casa a pessoa pelo par (iss, sub) do Google, não pelo e-mail (mais estável/seguro).
        identity_resource Api.Accounts.UserIdentity
      end

      remember_me :remember_me
    end
  end

  policies do
    # O próprio AshAuthentication precisa operar o recurso (upsert por token, lookup
    # por subject) sem passar por policy de negócio.
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Entrypoints públicos de autenticação (ADR-015): a segurança está no token/OAuth
    # validado dentro da ação, não numa policy. Chamados direto pelo code interface
    # (controller), eles não recebem a flag de "interaction", então liberamos aqui.
    policy action([:request_magic_link, :sign_in_with_magic_link, :register_with_google]) do
      authorize_if always()
    end

    # Um usuário só enxerga a si mesmo. A visão multi-tenant (memberships) é filtrada
    # pelas policies de `Membership` (ponto 4).
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
    end
  end

  # Global: o User é a identidade única e vive no schema público (sem `multitenancy`).
  postgres do
    table "users"
    repo Api.Repo
  end

  actions do
    defaults [:read]

    # Placeholder até a fatia de auth: cria/identifica o usuário pelo e-mail. Com
    # AshAuthentication, magic link/Google assumem o create real (upsert por e-mail).
    create :register do
      accept [:nome, :email]
      upsert? true
      upsert_identity :unique_email
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange
      # Registro auth-first não traz nome; defaulta pela parte local do e-mail.
      change Api.Accounts.User.Changes.DefaultNomeFromEmail

      change {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
              strategy_name: :remember_me}

      metadata :token, :string do
        allow_nil? false
      end
    end

    create :register_with_google do
      description "Registra ou identifica um usuário via Google OAuth (upsert por e-mail)."
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email, :nome]

      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false

      change Api.Accounts.User.Changes.SetFromGoogleUserInfo
      # Faz o upsert da UserIdentity (strategy + uid) e a liga ao usuário.
      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change AshAuthentication.GenerateTokenChange
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :nome, :string, allow_nil?: false, public?: true
    # case-insensitive; identidade de login.
    attribute :email, :ci_string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    has_many :memberships, Api.Accounts.Membership
  end

  identities do
    identity :unique_email, [:email]
  end
end
