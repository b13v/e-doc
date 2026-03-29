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

  def contract_row_actions(contract) do
    primary = %{
      label: gettext("View"),
      transport: :link,
      method: :get,
      href: "/contracts/#{contract.id}",
      class:
        "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-blue-600 transition hover:bg-blue-50 hover:text-blue-900"
    }

    secondary =
      cond do
        EdocApi.ContractStatus.is_draft?(contract) ->
          [
            %{
              label: gettext("Edit"),
              transport: :link,
              method: :get,
              href: "/contracts/#{contract.id}/edit",
              class:
                "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-green-600 transition hover:bg-green-50 hover:text-green-900"
            },
            %{
              label: gettext("Delete"),
              transport: :form,
              method: :post,
              action: "/contracts/#{contract.id}",
              _method: "delete",
              class:
                "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-red-600 transition hover:bg-red-50 hover:text-red-900",
              confirm_text: gettext("Delete this draft contract?")
            }
          ]

        EdocApi.ContractStatus.is_issued?(contract) ->
          [
            %{
              label: gettext("Signed"),
              transport: :form,
              method: :post,
              action: "/contracts/#{contract.id}/sign",
              class:
                "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-emerald-600 transition hover:bg-emerald-50 hover:text-emerald-900",
              confirm_text: gettext("Mark this contract as signed?")
            }
          ]

        true ->
          []
      end

    %{primary: primary, secondary: secondary}
  end
end
