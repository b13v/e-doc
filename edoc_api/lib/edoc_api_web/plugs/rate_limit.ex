defmodule EdocApiWeb.Plugs.RateLimit do
  @moduledoc false

  import Plug.Conn

  alias EdocApiWeb.ErrorMapper

  @table :edoc_api_rate_limit
  @cleanup_every 100

  def init(opts), do: opts

  def call(conn, opts) do
    ensure_table!()

    limit = Keyword.get(opts, :limit, 5)
    window_seconds = normalize_window_seconds(Keyword.get(opts, :window_seconds, 60))
    subject = rate_limit_subject(conn, Keyword.get(opts, :subject, :ip))
    action = Keyword.get(opts, :action, default_action(conn))
    now = System.system_time(:second)
    window_start = window_start(now, window_seconds)
    reset_at = window_start + window_seconds
    key = {subject, action, window_start}

    maybe_cleanup(now)

    count = :ets.update_counter(@table, key, {2, 1}, {key, 0, reset_at})
    remaining = max(limit - count, 0)
    retry_after = max(reset_at - now, 1)

    conn =
      conn
      |> put_resp_header("ratelimit-limit", Integer.to_string(limit))
      |> put_resp_header("ratelimit-remaining", Integer.to_string(remaining))
      |> put_resp_header("ratelimit-reset", Integer.to_string(retry_after))

    if count > limit do
      conn
      |> put_resp_header("retry-after", Integer.to_string(retry_after))
      |> ErrorMapper.too_many_requests("rate_limited", %{retry_after: retry_after})
      |> halt()
    else
      conn
    end
  end

  def reset! do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp maybe_cleanup(now) do
    if rem(:erlang.unique_integer([:positive]), @cleanup_every) == 0 do
      :ets.select_delete(@table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}])
    end

    :ok
  end

  defp default_action(conn), do: "#{conn.method}:#{conn.request_path}"

  defp window_start(now, window_seconds), do: div(now, window_seconds) * window_seconds

  defp normalize_window_seconds(window_seconds)
       when is_integer(window_seconds) and window_seconds > 0,
       do: window_seconds

  defp normalize_window_seconds(_), do: 60

  defp rate_limit_subject(conn, :user_or_ip) do
    case conn.assigns[:current_user] do
      %{id: user_id} when is_binary(user_id) -> "user:" <> user_id
      _ -> "ip:" <> client_ip(conn)
    end
  end

  defp rate_limit_subject(conn, :ip), do: "ip:" <> client_ip(conn)
  defp rate_limit_subject(conn, _), do: "ip:" <> client_ip(conn)

  defp client_ip(conn) do
    forwarded_ip =
      if trusted_proxy?(conn.remote_ip) do
        conn
        |> get_req_header("x-forwarded-for")
        |> List.first()
        |> parse_forwarded_ip()
      else
        nil
      end

    case forwarded_ip do
      nil -> format_ip(conn.remote_ip)
      ip -> ip
    end
  end

  defp trusted_proxy?(remote_ip) when is_tuple(remote_ip) do
    Enum.member?(trusted_proxies(), remote_ip)
  end

  defp trusted_proxy?(_), do: false

  defp trusted_proxies do
    Application.get_env(:edoc_api, __MODULE__, [])
    |> Keyword.get(:trusted_proxies, [])
  end

  defp format_ip(remote_ip) when is_tuple(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp format_ip(_), do: "unknown"

  defp parse_forwarded_ip(nil), do: nil

  defp parse_forwarded_ip(value) when is_binary(value) do
    value
    |> String.split(",")
    |> List.first()
    |> case do
      nil ->
        nil

      ip ->
        ip
        |> String.trim()
        |> validate_ip()
    end
  end

  defp validate_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, _parsed} -> ip
      _ -> nil
    end
  end
end
