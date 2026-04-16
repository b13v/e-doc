defmodule EdocApiWeb.Plugs.AuthenticateTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Accounts.UserCache
  alias EdocApi.Auth.Token
  alias EdocApiWeb.Plugs.Authenticate

  setup do
    ensure_cache_started!()
    UserCache.clear()
    :ok
  end

  test "caches authenticated users across repeated bearer token requests" do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    {:ok, token, _claims} = Token.generate_access_token(user.id)

    user_selects =
      capture_user_select_count(fn ->
        first_conn = authenticate_conn(token)
        second_conn = authenticate_conn(token)

        assert first_conn.assigns.current_user.id == user.id
        assert second_conn.assigns.current_user.id == user.id
      end)

    assert user_selects == 1
  end

  test "invalidate/1 forces the next authenticated request to reload the user" do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    {:ok, token, _claims} = Token.generate_access_token(user.id)

    assert authenticate_conn(token).assigns.current_user.id == user.id

    UserCache.invalidate(user.id)

    user_selects =
      capture_user_select_count(fn ->
        assert authenticate_conn(token).assigns.current_user.id == user.id
      end)

    assert user_selects == 1
  end

  test "email verification invalidates cached unverified user" do
    user = create_user!()
    {:ok, token, _claims} = Token.generate_access_token(user.id)

    denied_conn = authenticate_conn(token)
    assert denied_conn.halted
    assert denied_conn.status == 401

    Accounts.mark_email_verified!(user.id)

    allowed_conn = authenticate_conn(token)
    refute allowed_conn.halted
    assert allowed_conn.assigns.current_user.id == user.id
  end

  defp authenticate_conn(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Authenticate.call([])
  end

  defp capture_user_select_count(fun) when is_function(fun, 0) do
    test_pid = self()
    handler_id = {__MODULE__, :repo_query, System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      [:edoc_api, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if String.starts_with?(query, ~s(SELECT u0.)) and query =~ ~s(FROM "users") do
          send(test_pid, :user_select)
        end
      end,
      nil
    )

    try do
      fun.()
      drain_user_select_count(0)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_user_select_count(count) do
    receive do
      :user_select -> drain_user_select_count(count + 1)
    after
      0 -> count
    end
  end

  defp ensure_cache_started! do
    case Process.whereis(UserCache) do
      nil -> start_supervised!({UserCache, ttl_ms: :timer.minutes(5)})
      _pid -> :ok
    end
  end
end
