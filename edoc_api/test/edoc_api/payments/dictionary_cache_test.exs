defmodule EdocApi.Payments.DictionaryCacheTest do
  use EdocApi.DataCase, async: false

  alias EdocApi.Core.{Bank, KbeCode, KnpCode}
  alias EdocApi.Payments.DictionaryCache
  alias EdocApi.Repo

  setup do
    Repo.delete_all(Bank)
    Repo.delete_all(KbeCode)
    Repo.delete_all(KnpCode)
    ensure_cache_started!()
    clear_cache_table!()
    :ok
  end

  test "loads dictionaries and keeps sort order" do
    Repo.insert!(%Bank{name: "Zeta Bank", bic: unique_bic("ZETA")})
    Repo.insert!(%Bank{name: "Alpha Bank", bic: unique_bic("ALPH")})
    Repo.insert!(%KbeCode{code: "19", description: "KBE 19"})
    Repo.insert!(%KbeCode{code: "17", description: "KBE 17"})
    Repo.insert!(%KnpCode{code: "901", description: "KNP 901"})
    Repo.insert!(%KnpCode{code: "111", description: "KNP 111"})
    assert :ok = DictionaryCache.refresh()

    assert Enum.map(DictionaryCache.get(:banks), & &1.name) == ["Alpha Bank", "Zeta Bank"]
    assert Enum.map(DictionaryCache.get(:kbe_codes), & &1.code) == ["17", "19"]
    assert Enum.map(DictionaryCache.get(:knp_codes), & &1.code) == ["111", "901"]
  end

  test "serves cached values without re-reading DB between calls" do
    Repo.insert!(%Bank{name: "Cached Bank", bic: unique_bic("CACH")})
    assert :ok = DictionaryCache.refresh()

    assert [%Bank{name: "Cached Bank"}] = DictionaryCache.get(:banks)

    Repo.delete_all(Bank)

    assert [%Bank{name: "Cached Bank"}] = DictionaryCache.get(:banks)
  end

  test "refresh/0 updates stale snapshot with new values" do
    Repo.insert!(%Bank{name: "First Bank", bic: unique_bic("FIRS")})
    assert :ok = DictionaryCache.refresh()
    assert Enum.map(DictionaryCache.get(:banks), & &1.name) == ["First Bank"]

    Repo.insert!(%Bank{name: "Second Bank", bic: unique_bic("SECO")})
    assert Enum.map(DictionaryCache.get(:banks), & &1.name) == ["First Bank"]

    assert :ok = DictionaryCache.refresh()

    assert Enum.map(DictionaryCache.get(:banks), & &1.name) == ["First Bank", "Second Bank"]
  end

  defp unique_bic(prefix) do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.slice(-6, 6)
      |> String.pad_leading(6, "0")

    "#{prefix}#{suffix}"
  end

  defp ensure_cache_started! do
    case Process.whereis(DictionaryCache) do
      nil -> start_supervised!({DictionaryCache, refresh_ms: :infinity})
      _pid -> :ok
    end
  end

  defp clear_cache_table! do
    try do
      :ets.delete_all_objects(:payments_dictionary_cache)
    rescue
      ArgumentError -> :ok
    end
  end
end
