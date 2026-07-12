defmodule Api.Accounts do
  @moduledoc """
  Domínio de identidade e acesso (modelo Vercel, ADR-014/015/016). Recursos **globais**
  (schema público): `User` (identidade), `Clinic` (tenant registry) e `Membership`
  (vínculo com papel por-tenant).
  """
  use Ash.Domain, otp_app: :api

  resources do
    resource Api.Accounts.User do
      define :register_user, action: :register, args: [:nome, :email]
      define :get_user, action: :read, get_by: [:id]
    end

    resource Api.Accounts.Clinic do
      define :onboard_clinic, action: :onboard, args: [:nome]
      define :get_clinic, action: :read, get_by: [:id]
    end

    resource Api.Accounts.Membership do
      define :invite_member, action: :invite
      define :update_membership, action: :update
      define :accept_invite, action: :accept_invite
      define :revoke_access, action: :revoke_access
      define :list_memberships, action: :read
    end
  end
end
