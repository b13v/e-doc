defmodule EdocApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("[EdocApi] Starting application...")
    Logger.info("[EdocApi] Environment: #{Mix.env()}")
    Logger.info("[EdocApi] Elixir version: #{System.version()}")
    Logger.info("[EdocApi] OTP version: #{System.otp_release()}")

    children = [
      EdocApiWeb.Telemetry,
      EdocApi.Repo,
      {DNSCluster, query: Application.get_env(:edoc_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EdocApi.PubSub},
      {Finch, name: EdocApi.Finch},
      EdocApiWeb.Endpoint
    ]

    Logger.info("[EdocApi] Starting #{length(children)} supervised children...")

    opts = [strategy: :one_for_one, name: EdocApi.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, pid} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        log_startup_success(elapsed)
        {:ok, pid}

      {:error, reason} ->
        Logger.error("[EdocApi] Failed to start application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp log_startup_success(elapsed_ms) do
    Logger.info("[EdocApi] Application started successfully in #{elapsed_ms}ms")
    Logger.info("[EdocApi] Repo: #{inspect(EdocApi.Repo)}")
    Logger.info("[EdocApi] PubSub: #{inspect(EdocApi.PubSub)}")

    endpoint_config = Application.get_env(:edoc_api, EdocApiWeb.Endpoint)
    http_config = Keyword.get(endpoint_config || [], :http, [])
    port = Keyword.get(http_config, :port, 4000)
    Logger.info("[EdocApi] HTTP endpoint listening on port #{port}")

    Logger.info("[EdocApi] All systems operational")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdocApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
