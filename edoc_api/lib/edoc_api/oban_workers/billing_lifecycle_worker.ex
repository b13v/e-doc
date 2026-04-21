defmodule EdocApi.ObanWorkers.BillingLifecycleWorker do
  @moduledoc """
  Runs scheduled billing lifecycle maintenance.

  Supported actions:
  - `generate_renewal_invoices`
  - `process_overdue_billing`
  - `process_grace_expirations`
  - `send_billing_reminders`
  """

  use Oban.Worker, queue: :billing, max_attempts: 3

  alias EdocApi.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "generate_renewal_invoices"} = args}) do
    args
    |> lifecycle_opts()
    |> Billing.generate_renewal_invoices()

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "process_overdue_billing"} = args}) do
    args
    |> lifecycle_opts()
    |> Billing.process_overdue_billing()

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "process_grace_expirations"} = args}) do
    args
    |> lifecycle_opts()
    |> Billing.process_grace_expirations()

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "send_billing_reminders"} = args}) do
    args
    |> lifecycle_opts()
    |> Billing.send_billing_reminders()

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => action}}),
    do: {:cancel, "Unknown billing action: #{action}"}

  def perform(%Oban.Job{}), do: {:cancel, "Missing billing action"}

  defp lifecycle_opts(args) do
    case parse_now(args["now"]) do
      nil -> []
      now -> [now: now]
    end
  end

  defp parse_now(nil), do: nil

  defp parse_now(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end
end
