defmodule EdocApi.Accounts.UserCacheTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts.UserCache

  setup do
    ensure_cache_started!()
    UserCache.clear()
    :ok
  end

  test "serves cached user until invalidated" do
    user = create_user!()

    user_selects =
      capture_user_select_count(fn ->
        assert UserCache.get(user.id).email == user.email
        assert UserCache.get(user.id).email == user.email
      end)

    assert user_selects == 1

    UserCache.invalidate(user.id)

    user_selects =
      capture_user_select_count(fn ->
        assert UserCache.get(user.id).email == user.email
      end)

    assert user_selects == 1
  end

  test "does not cache missing users" do
    missing_id = Ecto.UUID.generate()

    assert UserCache.get(missing_id) == nil
    assert UserCache.get(missing_id) == nil
  end

  defp ensure_cache_started! do
    case Process.whereis(UserCache) do
      nil -> start_supervised!({UserCache, ttl_ms: :timer.minutes(5)})
      _pid -> :ok
    end
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
end
