defmodule EdocApi.LegalForms do
  @moduledoc """
  Canonical legal forms supported by the application.
  """

  @too "Товарищество с ограниченной ответственностью"
  @ao "Акционерное общество"
  @ip "Индивидуальный предприниматель"

  @allowed [@too, @ao, @ip]

  @legacy_to_full %{
    "ТОО" => @too,
    "АО" => @ao,
    "ИП" => @ip
  }

  @spec allowed() :: [String.t()]
  def allowed, do: @allowed

  @spec default() :: String.t()
  def default, do: @too

  @spec normalize(term()) :: term()
  def normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> then(fn trimmed -> Map.get(@legacy_to_full, trimmed, trimmed) end)
  end

  def normalize(value), do: value

  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value), do: normalize(value) in @allowed
  def valid?(_), do: false

  @spec display(term()) :: String.t()
  def display(nil), do: default()
  def display(""), do: default()

  def display(value) when is_binary(value) do
    normalized = normalize(value)
    if valid?(normalized), do: normalized, else: default()
  end

  def display(_), do: default()
end
