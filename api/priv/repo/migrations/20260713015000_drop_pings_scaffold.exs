defmodule Api.Repo.Migrations.DropPingsScaffold do
  @moduledoc """
  Remove a tabela de scaffold `pings` (auditoria doc 13, causa B). O recurso `Api.Meta.Ping`
  e sua rota AshJsonApi já foram removidos no código; esta migration completa a remoção do
  endpoint que servia leitura e escrita **anônimas** em `/api/json/pings`.

  `down` recria a tabela **vazia** (estrutura do snapshot) — os pings de scaffold não são
  recuperáveis, mas o schema é reversível.
  """
  use Ecto.Migration

  def up do
    drop(table(:pings))
  end

  def down do
    create table(:pings, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("uuid_generate_v7()"), primary_key: true)
      add(:message, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end
  end
end
