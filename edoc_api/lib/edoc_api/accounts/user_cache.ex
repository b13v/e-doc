defmodule EdocApi.Accounts.UserCache do
  @moduledoc """
  Short-lived ETS cache for API authentication user lookups.

  The cache stores successful user lookups only. Misses are not cached so newly
  created users are visible immediately, and app-side mutations invalidate the
  affected user explicitly.
  """
  use GenServer

  alias EdocApi.Accounts.User
  alias EdocApi.Repo

  @table :accounts_user_cache
  @default_ttl_ms :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ensure_table!()
    ttl_ms = Keyword.get(opts, :ttl_ms, ttl_ms())
    {:ok, %{ttl_ms: ttl_ms}}
  end

  @spec get(binary()) :: User.t() | nil
  def get(user_id) when is_binary(user_id) do
    now = System.monotonic_time(:millisecond)

    with [{^user_id, %User{} = user, expires_at}] <- lookup(user_id),
         true <- expires_at > now do
      user
    else
      _ -> load_and_cache(user_id, now)
    end
  end

  def get(_), do: nil

  @spec invalidate(binary()) :: :ok
  def invalidate(user_id) when is_binary(user_id) do
    delete(user_id)
    :ok
  end

  def invalidate(_), do: :ok

  @spec clear() :: :ok
  def clear do
    try do
      :ets.delete_all_objects(@table)
      :ok
    rescue
      ArgumentError -> :ok
    end
  end

  @impl true
  def handle_call(:ttl_ms, _from, %{ttl_ms: ttl_ms} = state) do
    {:reply, ttl_ms, state}
  end

  defp lookup(user_id) do
    :ets.lookup(@table, user_id)
  catch
    :error, :badarg -> []
  end

  defp load_and_cache(user_id, now) do
    delete(user_id)

    case Repo.get(User, user_id) do
      %User{} = user ->
        put(user_id, user, now + active_ttl_ms())
        user

      nil ->
        nil
    end
  end

  defp put(user_id, %User{} = user, expires_at) do
    :ets.insert(@table, {user_id, user, expires_at})
  catch
    :error, :badarg -> :ok
  end

  defp delete(user_id) do
    :ets.delete(@table, user_id)
  catch
    :error, :badarg -> :ok
  end

  defp active_ttl_ms do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :ttl_ms)
    else
      ttl_ms()
    end
  end

  defp ensure_table! do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
  rescue
    ArgumentError -> :ok
  end

  defp ttl_ms do
    Application.get_env(:edoc_api, __MODULE__, [])
    |> Keyword.get(:ttl_ms, @default_ttl_ms)
  end
end
