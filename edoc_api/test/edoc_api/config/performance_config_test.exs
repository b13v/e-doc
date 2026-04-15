defmodule EdocApi.Config.PerformanceConfigTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)

  test "dev repo pool is larger than total Oban queue concurrency" do
    dev_config = File.read!(Path.join(@root, "config/dev.exs"))

    assert repo_pool_size(dev_config) >= oban_queue_total(dev_config) + 5
  end

  test "production runtime default pool is larger than total Oban queue concurrency" do
    runtime_config = File.read!(Path.join(@root, "config/runtime.exs"))
    prod_config = File.read!(Path.join(@root, "config/prod.exs"))

    assert runtime_pool_size_default(runtime_config) >= oban_queue_total(prod_config) + 5
  end

  test "test repo pool remains modest because Oban runs inline" do
    test_config = File.read!(Path.join(@root, "config/test.exs"))

    assert repo_pool_size(test_config) == 10
    assert test_config =~ "testing: :inline"
  end

  defp repo_pool_size(config) do
    [_, value] = Regex.run(~r/pool_size:\s*(\d+)/, config)
    String.to_integer(value)
  end

  defp runtime_pool_size_default(config) do
    [_, value] = Regex.run(~r/POOL_SIZE"\)\s*\|\|\s*"(\d+)"/, config)
    String.to_integer(value)
  end

  defp oban_queue_total(config) do
    [_, queue_config] = Regex.run(~r/queues:\s*\[([^\]]+)\]/, config)

    ~r/\w+:\s*(\d+)/
    |> Regex.scan(queue_config, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.to_integer/1)
    |> Enum.sum()
  end
end
