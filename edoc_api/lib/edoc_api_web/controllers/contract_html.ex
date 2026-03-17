defmodule EdocApiWeb.ContractHTML do
  use EdocApiWeb, :html

  embed_templates("contract_html/*")

  def fmt_date(%Date{} = date) do
    Calendar.strftime(date, "%d.%m.%Y")
  end

  def fmt_date(nil), do: nil

  def money(%Decimal{} = amount) do
    amount
    |> Decimal.to_string(:normal)
    |> add_thousands_sep()
  end

  def money(nil), do: "0.00"

  defp add_thousands_sep(str) when is_binary(str) do
    {sign, rest} =
      if String.starts_with?(str, "-") do
        {"-", String.trim_leading(str, "-")}
      else
        {"", str}
      end

    [int, frac] =
      case String.split(rest, ".", parts: 2) do
        [i, f] -> [i, f]
        [i] -> [i, nil]
      end

    grouped_int =
      int
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
      |> String.reverse()

    if frac do
      sign <> grouped_int <> "." <> frac
    else
      sign <> grouped_int
    end
  end

  def vat_text(contract) do
    vat_rate = contract.vat_rate || 0

    if vat_rate > 0 do
      "в т.ч. НДС #{vat_rate}%"
    else
      "без НДС"
    end
  end
end
