defmodule EdocApiWeb.Plugs.RateLimitTest do
  use EdocApiWeb.ConnCase, async: false

  alias EdocApiWeb.Plugs.RateLimit

  setup do
    RateLimit.reset!()
    :ok
  end

  test "limits requests and sets rate limit headers", %{conn: conn} do
    opts = RateLimit.init(limit: 2, window_seconds: 60, action: "test_action", subject: :ip)

    conn = RateLimit.call(conn, opts)
    assert get_resp_header(conn, "ratelimit-limit") == ["2"]
    assert get_resp_header(conn, "ratelimit-remaining") == ["1"]

    conn = RateLimit.call(build_conn(), opts)
    assert get_resp_header(conn, "ratelimit-remaining") == ["0"]

    conn = RateLimit.call(build_conn(), opts)
    assert conn.status == 429
    assert conn.halted
    assert get_resp_header(conn, "retry-after") != []
  end

  test "ignores forwarded ip for untrusted remote ip" do
    opts = RateLimit.init(limit: 1, window_seconds: 60, action: "xff_action", subject: :ip)

    conn =
      build_conn()
      |> put_req_header("x-forwarded-for", "1.1.1.1, 10.0.0.1")
      |> RateLimit.call(opts)

    assert conn.status in [nil, 200]

    conn =
      build_conn()
      |> put_req_header("x-forwarded-for", "2.2.2.2")
      |> RateLimit.call(opts)

    assert conn.status == 429
  end

  test "uses forwarded ip only for trusted proxy remote ip" do
    Application.put_env(:edoc_api, RateLimit, trusted_proxies: [{127, 0, 0, 1}])
    on_exit(fn -> Application.delete_env(:edoc_api, RateLimit) end)

    opts = RateLimit.init(limit: 1, window_seconds: 60, action: "xff_action", subject: :ip)

    conn =
      build_conn()
      |> put_req_header("x-forwarded-for", "1.1.1.1")
      |> RateLimit.call(opts)

    assert conn.status in [nil, 200]

    conn =
      build_conn()
      |> put_req_header("x-forwarded-for", "1.1.1.1")
      |> RateLimit.call(opts)

    assert conn.status == 429

    conn =
      build_conn()
      |> put_req_header("x-forwarded-for", "2.2.2.2")
      |> RateLimit.call(opts)

    assert conn.status in [nil, 200]
  end

  test "separates user_or_ip counters by user id" do
    opts = RateLimit.init(limit: 1, window_seconds: 60, action: "mutation", subject: :user_or_ip)

    conn =
      build_conn()
      |> Plug.Conn.assign(:current_user, %{id: "user-1"})
      |> RateLimit.call(opts)

    assert conn.status in [nil, 200]

    conn =
      build_conn()
      |> Plug.Conn.assign(:current_user, %{id: "user-2"})
      |> RateLimit.call(opts)

    assert conn.status in [nil, 200]

    conn =
      build_conn()
      |> Plug.Conn.assign(:current_user, %{id: "user-1"})
      |> RateLimit.call(opts)

    assert conn.status == 429
  end
end
