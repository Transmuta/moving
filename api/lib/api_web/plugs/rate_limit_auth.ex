defmodule ApiWeb.Plugs.RateLimitAuth do
  @moduledoc """
  Rate limiting dos endpoints de autenticação (auditoria doc 13, causa A). Janela deslizante
  via `Api.RateLimiter`. **Só bloqueia em produção** (`config :api, rate_limit_enabled`); em
  dev/test é no-op, para não atrapalhar os fluxos locais.

  Chaves por rota (deny se **qualquer uma** estourar):

    * `/api/auth/magic-link` — por **e-mail** (limita bombardear a caixa de um alvo) **e** por
      **IP** (limita um atacante disparando links para mil e-mails diferentes). Os dois juntos
      fecham o vetor de spam-relay que a sonda pegou.
    * demais (`/auth/google`, `/auth/switch-tenant`) — por **actor** quando autenticado, senão
      por IP.

  > Nota de produção: atrás de proxy, `conn.remote_ip` é o IP do proxy. Ponha um plug de
  > `x-forwarded-for` (ex.: `remote_ip`) antes deste para o key por IP valer por cliente. O key
  > por e-mail/actor já é robusto ao proxy.
  """
  @behaviour Plug
  import Plug.Conn

  alias Api.RateLimiter

  # Janelas e limites. ATENÇÃO: o Hammer quer `scale` em **milissegundos** (`hit(key, scale_ms,
  # limite)`), não em segundos — passar 60 daria uma janela de 60ms (bug que só a app viva pegou;
  # o teste in-process passava por caber nos 60ms). `:timer.minutes/1` = minutos em ms.
  #   e-mail: 5 pedidos / 1 min (bombardear um alvo)
  #   IP:     10 pedidos / 2 min (um IP disparando para vários e-mails)
  @email_scale :timer.minutes(1)
  @email_limit 5
  @ip_scale :timer.minutes(2)
  @ip_limit 10

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?() do
      enforce(conn, keys_for(conn))
    else
      conn
    end
  end

  defp enforce(conn, []), do: conn

  defp enforce(conn, [{key, scale, limit} | rest]) do
    case RateLimiter.hit(key, scale, limit) do
      {:allow, _count} -> enforce(conn, rest)
      {:deny, _retry_after_ms} -> deny(conn)
    end
  end

  # Monta a lista de chaves {key, scale_ms, limite} conforme a rota.
  defp keys_for(%Plug.Conn{request_path: "/api/auth/magic-link"} = conn) do
    ip = client_ip(conn)

    case magic_link_email(conn) do
      nil ->
        [{"ml:ip:" <> ip, @ip_scale, @ip_limit}]

      email ->
        [
          {"ml:email:" <> email, @email_scale, @email_limit},
          {"ml:ip:" <> ip, @ip_scale, @ip_limit}
        ]
    end
  end

  defp keys_for(conn) do
    id =
      case conn.assigns[:scope] do
        %Api.Scope{user: %{id: user_id}} when is_binary(user_id) -> "actor:" <> user_id
        _ -> "ip:" <> client_ip(conn)
      end

    [{"auth:" <> conn.request_path <> ":" <> id, @ip_scale, @ip_limit}]
  end

  defp magic_link_email(conn) do
    (conn.body_params["email"] || get_in(conn.body_params, ["user", "email"]))
    |> normalize_email()
  end

  defp normalize_email(email) when is_binary(email) do
    case email |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_email(_), do: nil

  # IP real do cliente para o key por IP. A conexão TCP na API é sempre de um proxy (o BFF, na
  # rede interna; ou a edge do Fly, no tráfego público), nunca do browser — então `remote_ip`
  # sozinho é o do proxy. Ordem de confiança:
  #   1. `fly-client-ip` — setado pela edge do Fly no tráfego PÚBLICO, autoritativo (a edge
  #      sobrescreve qualquer valor do cliente), à prova de spoof.
  #   2. `x-forwarded-for` — setado pelo BFF no tráfego INTERNO (6PN, inalcançável de fora),
  #      então confiável nesse hop.
  #   3. `remote_ip` — fallback (dev/local sem proxy).
  defp client_ip(conn) do
    forwarded(conn, "fly-client-ip") || forwarded(conn, "x-forwarded-for") || peer_ip(conn)
  end

  defp forwarded(conn, header) do
    case get_req_header(conn, header) do
      [value | _] -> value |> String.split(",") |> List.first() |> String.trim() |> nil_if_empty()
      [] -> nil
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value

  defp peer_ip(%Plug.Conn{remote_ip: ip}), do: ip |> :inet.ntoa() |> to_string()

  defp deny(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, ~s({"error":"rate_limited"}))
    |> halt()
  end

  defp enabled?, do: Application.get_env(:api, :rate_limit_enabled, false)
end
