defmodule EdocApiWeb.Plugs.ValidateUuid do
  @moduledoc false

  import Plug.Conn

  alias EdocApiWeb.ErrorMapper

  @default_keys [
    "id",
    "invoice_id",
    "contract_id",
    "buyer_id",
    "bank_account_id",
    "company_id",
    "user_id"
  ]

  def init(opts), do: opts

  def call(conn, opts) do
    keys = Keyword.get(opts, :keys, @default_keys)

    case invalid_uuid_param(conn.params, keys) do
      nil ->
        conn

      _invalid_key ->
        conn
        |> ErrorMapper.bad_request("invalid_uuid")
        |> halt()
    end
  end

  defp invalid_uuid_param(params, keys) when is_map(params) do
    Enum.find(keys, fn key ->
      case Map.fetch(params, key) do
        {:ok, value} when is_binary(value) and value != "" -> Ecto.UUID.cast(value) == :error
        _ -> false
      end
    end)
  end
end
