defmodule Api.Release do
  @moduledoc """
  Tarefas de release para produção (sem Mix). Rodam a partir do release compilado — no Fly via
  `release_command = "/app/bin/api eval Api.Release.setup()"` (fly.toml). Conectam como o role
  **owner** (`DATABASE_ADMIN_URL`): fazem DDL e criam o role restrito. O app de longa duração
  conecta como o role **restrito** (`DATABASE_URL` = `movimento_app`, NOBYPASSRLS) e fica
  sujeito à RLS (ADR-018).

  - `setup/0`   — roda migrations e provisiona o role restrito (a ordem importa: tabelas antes
                  dos grants).
  - `migrate/0` — só as migrations.
  - `setup_app_role/0` — cria/garante `DATABASE_APP_USER` (NOBYPASSRLS) + grants (ADR-018).
  """
  @app :api

  def setup do
    migrate()
    setup_app_role()
  end

  def migrate do
    load_app()

    with_admin_config(fn ->
      for repo <- repos() do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end
    end)
  end

  @doc """
  Provisiona o role restrito do app (RLS, ADR-018). Idempotente. Roda como owner (o `migrate`
  service usa a `DATABASE_URL` de admin). Espelha `priv/sql/setup_app_role.sql` do dev, mas
  parametriza usuário/senha por env.
  """
  def setup_app_role do
    load_app()
    user = System.fetch_env!("DATABASE_APP_USER")
    pass = System.fetch_env!("DATABASE_APP_PASSWORD")
    validate_identifier!(user)

    with_admin_config(fn ->
      {:ok, _, _} =
        Ecto.Migrator.with_repo(Api.Repo, fn repo ->
          Enum.each(role_statements(user, pass), &Ecto.Adapters.SQL.query!(repo, &1))
          :ok
        end)
    end)

    :ok
  end

  # `user` é validado como identificador SQL; a senha é escapada (aspas dobradas). CREATE ROLE
  # não aceita bind params, então interpolamos com cuidado.
  defp role_statements(user, pass) do
    quoted_pass = "'" <> String.replace(pass, "'", "''") <> "'"

    [
      """
      DO $$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{user}') THEN
          CREATE ROLE #{user} LOGIN PASSWORD #{quoted_pass}
            NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
        END IF;
      END $$;
      """,
      "GRANT USAGE ON SCHEMA public TO #{user}",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{user}",
      "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{user}",
      "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO #{user}",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{user}",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{user}",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO #{user}"
    ]
  end

  defp validate_identifier!(user) do
    unless Regex.match?(~r/\A[a-z_][a-z0-9_]*\z/i, user) do
      raise ArgumentError,
            "DATABASE_APP_USER deve ser um identificador SQL simples, recebido: #{inspect(user)}"
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Roda `fun` com o Repo apontado para a conexão de OWNER (`DATABASE_ADMIN_URL`) — migrations/DDL
  # e criação do role restrito. No Fly o `release_command` e o app compartilham secrets, então
  # separamos por variável: admin aqui, `DATABASE_URL` (restrito) no runtime do app. Sobrescreve a
  # config **antes** do `with_repo` (o `url:` opt do with_repo não sobrepõe a url do runtime.exs).
  # Sem `DATABASE_ADMIN_URL`, usa a config atual (setups onde a `DATABASE_URL` já é de owner).
  defp with_admin_config(fun) do
    case System.get_env("DATABASE_ADMIN_URL") do
      nil ->
        fun.()

      admin ->
        original = Application.get_env(@app, Api.Repo, [])
        Application.put_env(@app, Api.Repo, Keyword.put(original, :url, admin))

        try do
          fun.()
        after
          Application.put_env(@app, Api.Repo, original)
        end
    end
  end

  defp load_app, do: Application.load(@app)
end
