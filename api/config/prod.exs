import Config

# TLS/HSTS ficam no proxy (Caddy), NÃO no `force_ssl` da API. Nesta topologia a API é
# **interna** (só o BFF SvelteKit e o Caddy falam com ela): o BFF chama `http://api:4000` sem
# `x-forwarded-proto`, e `force_ssl` redirecionaria essas chamadas server-to-server para https,
# quebrando o BFF. O Caddy termina TLS, redireciona http→https e emite HSTS para o browser
# (ver `compose.prod.yml` / `Caddyfile`).

# Do not print debug messages in production
config :logger, level: :info

# Liga o rate limiting dos endpoints de auth (auditoria doc 13, causa A). Só em produção:
# o `ApiWeb.Plugs.RateLimitAuth` é no-op quando esta flag é falsa (dev/test).
config :api, rate_limit_enabled: true

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
