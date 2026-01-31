defmodule EdocApiWeb.ContractsHTML do
  use EdocApiWeb, :html

  embed_templates("contracts_html/*")

  # Helper functions for contract template
  def fmt_date(nil), do: "—"

  def fmt_date(%Date{} = d) do
    d
    |> Date.to_erl()
    |> then(fn {y, m, day} -> "#{pad2(m)}.#{pad2(day)}.#{y}" end)
  end

  def money(nil), do: "—"

  def money(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> add_thousands_sep()
  end

  def money(v) when is_integer(v), do: v |> Decimal.new() |> money()

  def money(v) when is_float(v),
    do: v |> :erlang.float_to_binary(decimals: 2) |> Decimal.new() |> money()

  def money(v) when is_binary(v) do
    case Decimal.parse(v) do
      {d, ""} -> money(d)
      _ -> v
    end
  end

  defp add_thousands_sep(str) when is_binary(str) do
    [int, frac] =
      case String.split(str, ".") do
        [i, f] -> [i, f]
        [i] -> [i, nil]
      end

    int =
      int
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.join(" ")
      |> String.reverse()

    if frac, do: "#{int}.#{frac}", else: int
  end

  defp pad2(n) when is_integer(n) and n < 10, do: "0#{n}"
  defp pad2(n) when is_integer(n), do: Integer.to_string(n)

  def vat_text(%{vat_rate: vat_rate}) when is_integer(vat_rate) do
    if vat_rate == 0, do: "без НДС", else: "с НДС #{vat_rate}%"
  end

  def vat_text(%{vat_rate: vat_rate}) when is_binary(vat_rate) do
    case Integer.parse(vat_rate) do
      {0, _} -> "без НДС"
      {n, _} -> "с НДС #{n}%"
      _ -> "без НДС"
    end
  end

  def vat_text(_), do: "без НДС"
end
