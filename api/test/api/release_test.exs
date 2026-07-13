defmodule Api.ReleaseTest do
  @moduledoc """
  Guard do provisionamento do role restrito (prod, RLS ADR-018). `CREATE ROLE` não aceita bind
  params, então o nome do role é interpolado — e precisa ser validado como identificador SQL
  para não virar injeção. Aqui provamos que um nome malicioso é recusado **antes** de tocar o
  banco.
  """
  use ExUnit.Case, async: false

  test "setup_app_role/0 recusa DATABASE_APP_USER que não é identificador SQL" do
    System.put_env("DATABASE_APP_USER", "app\"; DROP TABLE users; --")
    System.put_env("DATABASE_APP_PASSWORD", "irrelevante")

    on_exit(fn ->
      System.delete_env("DATABASE_APP_USER")
      System.delete_env("DATABASE_APP_PASSWORD")
    end)

    assert_raise ArgumentError, ~r/identificador SQL/, fn -> Api.Release.setup_app_role() end
  end
end
