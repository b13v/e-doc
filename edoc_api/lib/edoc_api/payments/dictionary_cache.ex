defmodule EdocApi.Payments.DictionaryCache do
  @moduledoc """
  In-memory cache for dictionary data used by forms and selectors.
  """
  use GenServer

  import Ecto.Query, warn: false

  alias EdocApi.Core.{Bank, KbeCode, KnpCode}
  alias EdocApi.Repo

  @table :payments_dictionary_cache
  @dictionary_keys [:banks, :kbe_codes, :knp_codes]
  @default_refresh_ms :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ensure_table!()
    put_all_entries()

    refresh_ms = Keyword.get(opts, :refresh_ms, refresh_ms())
    schedule_refresh(refresh_ms)

    {:ok, %{refresh_ms: refresh_ms}}
  end

  @spec get(:banks | :kbe_codes | :knp_codes) :: [struct()]
  def get(key) when key in @dictionary_keys do
    case :ets.lookup(@table, key) do
      [{^key, values}] ->
        values

      [] ->
        values = load(key)
        put_entry(key, values)
        values
    end
  catch
    :error, :badarg ->
      load(key)
  end

  @spec refresh() :: :ok
  def refresh do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :refresh, :timer.seconds(10))
    else
      :ok
    end
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    put_all_entries()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:refresh, %{refresh_ms: refresh_ms} = state) do
    put_all_entries()
    schedule_refresh(refresh_ms)
    {:noreply, state}
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

  defp put_all_entries do
    Enum.each(@dictionary_keys, fn key ->
      put_entry(key, load(key))
    end)
  end

  defp put_entry(key, values) do
    true = :ets.insert(@table, {key, values})
    :ok
  catch
    :error, :badarg -> :ok
  end

  defp load(:banks) do
    Bank |> order_by([b], asc: b.name) |> Repo.all()
  end

  defp load(:kbe_codes) do
    KbeCode |> order_by([k], asc: k.code) |> Repo.all()
  end

  defp load(:knp_codes) do
    KnpCode |> order_by([k], asc: k.code) |> Repo.all()
  end

  defp schedule_refresh(:infinity), do: :ok

  defp schedule_refresh(ms) when is_integer(ms) and ms > 0,
    do: Process.send_after(self(), :refresh, ms)

  defp schedule_refresh(_), do: :ok

  defp refresh_ms do
    Application.get_env(:edoc_api, __MODULE__, [])
    |> Keyword.get(:refresh_ms, @default_refresh_ms)
  end
end
