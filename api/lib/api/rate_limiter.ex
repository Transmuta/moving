defmodule Api.RateLimiter do
  @moduledoc """
  Rate limiter da aplicação (Hammer 7, backend ETS, algoritmo **sliding window**).

  Janela deslizante (não fixa) para evitar o burst na virada de janela: conta os hits nos
  últimos `scale` milissegundos (a unidade do Hammer), não num balde alinhado ao relógio. Usado pelo
  `ApiWeb.Plugs.RateLimitAuth` nos endpoints de autenticação (auditoria doc 13, causa A).

  A enforcement é **ligada só em produção** (`config :api, rate_limit_enabled: true` no
  `prod.exs`); em dev/test a tabela ETS existe mas o plug não bloqueia — o processo aqui
  sobe em todos os ambientes de propósito, para o teste poder exercitá-lo.
  """
  use Hammer, backend: :ets, algorithm: :sliding_window
end
