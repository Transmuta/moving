-- Role de aplicação restrito para RLS (ADR-018). Idempotente; roda como `postgres`
-- (owner) no entrypoint dev, depois das migrations. O app (phx.server) conecta como
-- este role: NOSUPERUSER + NOBYPASSRLS => fica SUJEITO às policies de RLS.
-- Migrations continuam rodando como `postgres` (superusuário, bypassa RLS p/ DDL).

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'movimento_app') THEN
    CREATE ROLE movimento_app LOGIN PASSWORD 'movimento_app'
      NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO movimento_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO movimento_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO movimento_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO movimento_app;

-- Tabelas/sequences/funções futuras (criadas por postgres) já nascem acessíveis ao app.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO movimento_app;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO movimento_app;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO movimento_app;
