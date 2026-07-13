defmodule Api.Directory do
  @moduledoc """
  Domínio do quadro da clínica — recursos **por-tenant** por atributo (`strategy :attribute`
  sobre `clinic_id`, ADR-017). Por ora só `Professional`; `AppointmentType`/`PriceVersion`
  entram nas fatias seguintes.
  """
  use Ash.Domain, otp_app: :api

  resources do
    resource Api.Directory.Professional do
      define :create_professional, action: :create, args: [:nome]
      define :list_professionals, action: :read
      define :get_professional, action: :read, get_by: [:id]
    end
  end
end
