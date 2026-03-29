defmodule EdocApiWeb.PdfTemplates do
  use Phoenix.Component

  alias EdocApi.InvoiceStatus
  alias EdocApi.LegalForms
  alias EdocApi.Repo
  alias EdocApi.Documents.Builders.ContractDataBuilder

  # Возвращает HTML строкой (готово для wkhtmltopdf)
  def invoice_html(invoice) do
    assigns = %{invoice: invoice}

    invoice(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  def contract_html(contract) do
    contract =
      Repo.preload(contract, [
        :company,
        :bank_account,
        :contract_items,
        buyer: [bank_accounts: :bank],
        bank_account: [:bank, :kbe_code, :knp_code]
      ])

    # Build seller data from contract's company
    seller = build_seller_data(contract)

    # Build buyer data from buyer or legacy buyer fields
    buyer = build_buyer_data(contract)

    # Build bank data from bank_account
    bank = build_bank_data(contract)

    # Build items list
    items = build_items_data(contract)

    # Build totals
    totals = build_totals(items, contract.vat_rate)

    assigns = %{
      contract: contract,
      seller: seller,
      buyer: buyer,
      bank: bank,
      items: items,
      totals: totals
    }

    contract(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  def act_html(act) do
    act =
      Repo.preload(act, [
        :company,
        :buyer,
        :contract,
        :items
      ])

    assigns = %{act: act}

    act(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp build_seller_data(contract),
    do: ContractDataBuilder.build_seller_data(contract)

  defp build_buyer_data(contract),
    do: ContractDataBuilder.build_buyer_data(contract)

  defp build_bank_data(contract),
    do: ContractDataBuilder.build_bank_data(contract)

  defp build_items_data(contract),
    do: ContractDataBuilder.build_items_data(contract)

  defp build_totals(items, vat_rate),
    do: ContractDataBuilder.build_totals(items, vat_rate)

  defp money(nil), do: "—"

  defp money(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> add_thousands_sep()
  end

  defp money(v) when is_integer(v),
    do: v |> Decimal.new() |> money()

  defp money(v) when is_float(v),
    do: v |> :erlang.float_to_binary(decimals: 2) |> Decimal.new() |> money()

  defp money(v) when is_binary(v) do
    case Decimal.parse(v) do
      {d, ""} -> money(d)
      _ -> v
    end
  end

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

  defp fmt_date(nil), do: "—"

  defp fmt_date(%Date{} = d) do
    d
    |> Date.to_erl()
    |> then(fn {y, m, day} ->
      "#{pad2(day)}.#{pad2(m)}.#{y}"
    end)
  end

  defp pad2(n) when is_integer(n) and n < 10, do: "0#{n}"
  defp pad2(n) when is_integer(n), do: Integer.to_string(n)

  defp vat_text(%{vat_rate: vat_rate}) when is_integer(vat_rate) do
    if vat_rate == 0, do: "без НДС", else: "с НДС #{vat_rate}%"
  end

  defp vat_text(%{vat_rate: vat_rate}) when is_binary(vat_rate) do
    case Integer.parse(vat_rate) do
      {0, _} -> "без НДС"
      {n, _} -> "с НДС #{n}%"
      :error -> "без НДС"
    end
  end

  defp vat_text(_), do: "без НДС"

  defp vat_line(invoice) do
    rate = invoice.vat_rate || 0

    if rate == 0 do
      "0,00"
    else
      # "В том числе НДС #{rate}%  #{money(invoice.vat)}"
      "#{money(invoice.vat)}"
    end
  end

  defp amount_words_kzt(nil), do: "—"

  defp amount_words_kzt(%Decimal{} = d) do
    d = Decimal.round(d, 2)

    # "12345.67"
    s = Decimal.to_string(d, :normal)

    {tenge, tiyn} =
      case String.split(s, ".") do
        [i, f] -> {String.to_integer(i), String.pad_trailing(String.slice(f, 0, 2), 2, "0")}
        [i] -> {String.to_integer(i), "00"}
      end

    words = num_to_words_ru(tenge)
    "#{String.capitalize(words)} тенге #{tiyn} тиын"
  end

  @ones %{
    0 => "ноль",
    1 => "один",
    2 => "два",
    3 => "три",
    4 => "четыре",
    5 => "пять",
    6 => "шесть",
    7 => "семь",
    8 => "восемь",
    9 => "девять"
  }
  @teens %{
    10 => "десять",
    11 => "одиннадцать",
    12 => "двенадцать",
    13 => "тринадцать",
    14 => "четырнадцать",
    15 => "пятнадцать",
    16 => "шестнадцать",
    17 => "семнадцать",
    18 => "восемнадцать",
    19 => "девятнадцать"
  }
  @tens %{
    2 => "двадцать",
    3 => "тридцать",
    4 => "сорок",
    5 => "пятьдесят",
    6 => "шестьдесят",
    7 => "семьдесят",
    8 => "восемьдесят",
    9 => "девяносто"
  }
  @hundreds %{
    1 => "сто",
    2 => "двести",
    3 => "триста",
    4 => "четыреста",
    5 => "пятьсот",
    6 => "шестьсот",
    7 => "семьсот",
    8 => "восемьсот",
    9 => "девятьсот"
  }

  defp num_to_words_ru(n) when is_integer(n) and n >= 0 do
    cond do
      n < 10 -> @ones[n]
      n < 20 -> @teens[n]
      n < 100 -> words_2(n)
      n < 1000 -> words_3(n)
      n < 1_000_000 -> words_group(n, 1000, {"тысяча", "тысячи", "тысяч"}, feminine: true)
      n < 1_000_000_000 -> words_group(n, 1_000_000, {"миллион", "миллиона", "миллионов"})
      true -> words_group(n, 1_000_000_000, {"миллиард", "миллиарда", "миллиардов"})
    end
  end

  defp words_2(n) do
    t = div(n, 10)
    o = rem(n, 10)

    base = @tens[t]
    if o == 0, do: base, else: base <> " " <> @ones[o]
  end

  defp words_3(n) do
    h = div(n, 100)
    rest = rem(n, 100)

    head = @hundreds[h]

    tail =
      cond do
        rest == 0 -> ""
        rest < 10 -> " " <> @ones[rest]
        rest < 20 -> " " <> @teens[rest]
        true -> " " <> words_2(rest)
      end

    head <> tail
  end

  defp words_group(n, unit, forms, opts \\ []) do
    g = div(n, unit)
    rest = rem(n, unit)

    g_words = group_words(g, opts)
    form = choose_form(g, forms)

    rest_words =
      cond do
        rest == 0 -> ""
        rest < 1000 -> " " <> num_to_words_ru(rest)
        true -> " " <> num_to_words_ru(rest)
      end

    String.trim(g_words <> " " <> form <> rest_words)
  end

  defp group_words(g, opts) do
    feminine? = Keyword.get(opts, :feminine, false)

    # тысячи: 1/2 -> одна/две
    base =
      cond do
        g < 1000 -> num_to_words_ru(g)
        true -> num_to_words_ru(g)
      end

    if feminine?, do: feminineize_last_unit(base, g), else: base
  end

  defp feminineize_last_unit(base, g) do
    tens = rem(g, 100)
    ones = rem(g, 10)

    cond do
      tens in 11..19 ->
        base

      ones == 1 ->
        replace_suffix(base, "один", "одна")

      ones == 2 ->
        replace_suffix(base, "два", "две")

      true ->
        base
    end
  end

  defp replace_suffix(str, suffix, replacement) do
    if String.ends_with?(str, suffix) do
      prefix_len = byte_size(str) - byte_size(suffix)
      binary_part(str, 0, prefix_len) <> replacement
    else
      str
    end
  end

  defp choose_form(n, {one, few, many}) do
    n = rem(n, 100)
    last = rem(n, 10)

    cond do
      n in 11..19 -> many
      last == 1 -> one
      last in 2..4 -> few
      true -> many
    end
  end

  defp assoc_loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp assoc_loaded(value), do: value

  defp act(assigns) do
    ~H"""
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          body { margin: 0; }
          .act-doc { font-family: Arial, sans-serif; font-size: 12px; color: #000; line-height: 1.35; }
          .act-doc table { width: 100%; border-collapse: collapse; margin-top: 8px; }
          .act-doc th, .act-doc td { border: 1px solid #000; padding: 6px; vertical-align: top; }
          .act-doc .center { text-align: center; }
          .act-doc .right { text-align: right; }
          .act-doc .no-border td { border: none; }
          .act-doc .small { font-size: 11px; }
          .act-doc .hr { border-top: 1px solid #000; margin: 10px 0; }
          .act-doc .party-wrap {
            display: table;
            width: 100%;
            table-layout: fixed;
            margin-top: 6px;
          }
          .act-doc .party-wrap-left {
            display: table-cell;
            vertical-align: top;
            padding-right: 12px;
          }
          .act-doc .party-wrap-right {
            display: table-cell;
            width: 240px;
            vertical-align: top;
          }
          .act-doc .party-table {
            width: 100%;
            table-layout: fixed;
            border-collapse: separate;
            border-spacing: 0 6px;
            margin-top: 0;
          }
          .act-doc .party-col-label { width: 15%; }
          .act-doc .party-col-details { width: 85%; }
          .act-doc .party-table tr td { vertical-align: bottom; }
          .act-doc .party-table td.party-details { padding-top: 4px; padding-bottom: 0; }
          .act-doc .party-table .party-details-line {
            border-bottom: 1px solid #000;
            padding-bottom: 2px;
            margin-right: 100px;
            font-weight: 700;
          }
          .act-doc .party-bin-stack {
            width: 220px;
            margin-left: auto;
            text-align: center;
          }
          .act-doc .party-bin-header {
            font-weight: 700;
            margin-bottom: 6px;
          }
          .act-doc .party-bin-box {
            display: block;
            box-sizing: border-box;
            border: 2px solid #000;
            font-weight: 700;
            height: 44px;
            line-height: 44px;
            padding: 0 10px;
            margin-bottom: 4px;
            text-align: center;
            overflow: hidden;
          }
          .act-doc .contract-wrap-table { width: 80%; table-layout: fixed; margin-top: 4px; }
          .act-doc .contract-wrap-table td { border: none !important; vertical-align: top; padding: 0; }
          .act-doc .contract-wrap-left { width: 76%; padding-right: 12px !important; }
          .act-doc .contract-wrap-right { width: 24%; }
          .act-doc .contract-meta-table { width: 100%; table-layout: fixed; margin-top: 0; }
          .act-doc .contract-meta-table td { border: none !important; padding: 4px 6px; }
          .act-doc .contract-meta-label { width: 25%; }
          .act-doc .contract-meta-value { width: 75%; }
          .act-doc .contract-meta-line {
            border-bottom: 1px solid #000;
            padding-bottom: 2px;
            margin-right: 24px;
          }
          .act-doc .doc-meta-box { width: 100%; border-collapse: collapse; }
          .act-doc .doc-meta-box th,
          .act-doc .doc-meta-box td {
            border: 1px solid #000 !important;
            text-align: center;
            padding: 6px;
          }
          .act-doc .doc-meta-box th { font-weight: 400; }
          .act-doc .doc-meta-box td { font-weight: 700; }
          .act-doc .doc-meta-box th { line-height: 1.1; }
          .act-doc .act-items-table th { font-weight: 400; }
          .act-doc .act-title {
            width: 76%;
            margin-top: -22px;
            margin-left: 0;
            margin-bottom: 16px;
            text-align: center;
            font-size: 15px;
            font-weight: 700;
          }
        </style>
      </head>
      <body>
        <% act = @act %>
        <div class="act-doc">
          <% items = act.items || [] %>
          <% vat_rate = Decimal.new(act.vat_rate || 0) %>
          <% total_qty = Enum.reduce(items, Decimal.new(0), fn i, acc -> Decimal.add(acc, i.qty || Decimal.new(0)) end) %>
          <% total_net = Enum.reduce(items, Decimal.new(0), fn i, acc -> Decimal.add(acc, i.amount || Decimal.new(0)) end) %>
          <% total_vat = Enum.reduce(items, Decimal.new(0), fn i, acc -> Decimal.add(acc, Decimal.mult(i.amount || Decimal.new(0), vat_rate) |> Decimal.div(Decimal.new(100)) |> Decimal.round(2)) end) %>
          <% total_amount = Decimal.add(total_net, total_vat) %>
          <% seller_legal_form =
            case Map.get(act.company || %{}, :legal_form) do
              value when is_binary(value) and value != "" -> EdocApi.LegalForms.display(value)
              _ -> nil
            end %>
          <% buyer_legal_form =
            case Map.get(act.buyer || %{}, :legal_form) do
              value when is_binary(value) and value != "" -> EdocApi.LegalForms.display(value)
              _ -> nil
            end %>

          <div class="small right">Приложение 50</div>
          <div class="small right">к приказу Министра финансов Республики Казахстан</div>
          <div class="small right">от 20 декабря 2012 года № 562</div>
          <div class="small right" style="margin-top: 8px;">Форма Р-1</div>
          <div class="party-wrap">
            <div class="party-wrap-left">
              <table class="no-border party-table">
                <colgroup>
                  <col class="party-col-label" />
                  <col class="party-col-details" />
                </colgroup>
                <tr>
                  <td><strong>Заказчик</strong></td>
                  <td class="party-details">
                    <div class="party-details-line">
                      <%= if seller_legal_form, do: seller_legal_form <> " " %><%= act.seller_name %>, <%= act.seller_address %>
                    </div>
                  </td>
                </tr>
                <tr>
                  <td><strong>Исполнитель</strong></td>
                  <td class="party-details">
                    <div class="party-details-line">
                      <%= if buyer_legal_form, do: buyer_legal_form <> " " %><%= act.buyer_name %>, <%= act.buyer_address %>
                    </div>
                  </td>
                </tr>
              </table>
            </div>
            <div class="party-wrap-right">
              <div class="party-bin-stack">
                <div class="party-bin-header">ИИН/БИН</div>
                <span class="party-bin-box"><%= act.seller_bin_iin %></span>
                <span class="party-bin-box"><%= act.buyer_bin_iin %></span>
              </div>
            </div>
          </div>

          <table class="no-border contract-wrap-table">
            <tr>
              <td class="contract-wrap-left">
                <table class="no-border contract-meta-table">
                  <colgroup>
                    <col class="contract-meta-label" />
                    <col class="contract-meta-value" />
                  </colgroup>
                  <tr>
                    <td>Договор (контракт)</td>
                    <td>
                      <div class="contract-meta-line">
                        <%= if act.contract do %>
                          Договор № <%= act.contract.number %> от <%= fmt_date(act.contract.issue_date) %>
                        <% else %>
                          —
                        <% end %>
                      </div>
                    </td>
                  </tr>
                </table>
              </td>
              <td class="contract-wrap-right">
                <table class="doc-meta-box">
                  <tr>
                    <th>Номер<br/>документа</th>
                    <th>Дата<br/>составления</th>
                  </tr>
                  <tr>
                    <td><%= act.number %></td>
                    <td><%= fmt_date(act.issue_date) %></td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>

          <h2 class="act-title">АКТ ВЫПОЛНЕННЫХ РАБОТ (ОКАЗАННЫХ УСЛУГ)</h2>

          <table class="act-items-table" style="width: 100%; border-collapse: collapse; table-layout: fixed; font-family: Arial, sans-serif; font-size: 11px; margin-top: 0;">
            <colgroup>
              <col style="width: 4%;" />
              <col style="width: 32%;" />
              <col style="width: 8%;" />
              <col style="width: 18%;" />
              <col style="width: 8%;" />
              <col style="width: 8%;" />
              <col style="width: 8%;" />
              <col style="width: 7%;" />
              <col style="width: 7%;" />
            </colgroup>
            <thead>
              <tr>
                <th rowspan="2" style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle; line-height: 1.2;">Номер<br/>по<br/>порядку</th>
                <th rowspan="2" style="border: 1px solid #000; padding: 5px 4px; text-align: center; vertical-align: middle; line-height: 1.35; font-size: 12px;">
                  Наименование работ(услуг)(в разрезе их<br/>
                  подвидов в соответствии с технической<br/>
                  спецификацией,заданием,графиком<br/>
                  выполнения работ(услуг) при их наличии)
                </th>
                <th rowspan="2" style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle; line-height: 1.2;">
                  Дата<br/>выполнения<br/>работ<br/>(оказания<br/>услуг)
                </th>
                <th rowspan="2" style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle; line-height: 1.2;">
                  Сведения об отчете о научных исследованиях, маркетинговых, консультационных и прочих услугах (дата, номер, количество страниц) (при их наличии)
                </th>
                <th rowspan="2" style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle; line-height: 1.2;">
                  Единица измерения
                </th>
                <th colspan="4" style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle; line-height: 1.2;">
                  Выполнено работ (оказано услуг)
                </th>
              </tr>
              <tr>
                <th style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;">количество</th>
                <th style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;">цена за<br/>единицу</th>
                <th style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;">стоимость</th>
                <th style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;">в том числе НДС, в KZT</th>
              </tr>
              <tr>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">1</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">2</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">3</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">4</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">5</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">6</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">7</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">8</th>
                <th style="border: 1px solid #000; padding: 2px; text-align: center;">9</th>
              </tr>
            </thead>
            <tbody>
              <%= for {item, idx} <- Enum.with_index(items, 1) do %>
                <% item_unit_price = item.unit_price || Decimal.new(0) %>
                <% item_amount_net = item.amount || Decimal.new(0) %>
                <% item_unit_vat = Decimal.mult(item_unit_price, vat_rate) |> Decimal.div(Decimal.new(100)) |> Decimal.round(2) %>
                <% item_vat = Decimal.mult(item_amount_net, vat_rate) |> Decimal.div(Decimal.new(100)) |> Decimal.round(2) %>
                <% item_unit_price_with_vat = Decimal.add(item_unit_price, item_unit_vat) %>
                <% item_amount_with_vat = Decimal.add(item_amount_net, item_vat) %>
                <tr>
                  <td style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;"><%= idx %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: left; vertical-align: top;"><%= item.name || "" %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;"><%= fmt_date(item.actual_date) %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: left; vertical-align: top;"><%= item.report_info || "" %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;"><%= item.code || "" %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: center; vertical-align: middle;"><%= Decimal.to_string(item.qty || Decimal.new(0), :normal) %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: right; vertical-align: middle;"><%= EdocApiWeb.ContractHTML.money(item_unit_price_with_vat) %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: right; vertical-align: middle;"><%= EdocApiWeb.ContractHTML.money(item_amount_with_vat) %></td>
                  <td style="border: 1px solid #000; padding: 4px; text-align: right; vertical-align: middle;"><%= EdocApiWeb.ContractHTML.money(item_vat) %></td>
                </tr>
              <% end %>
              <tr>
                <td style="border: 1px solid #000; border-left: none; border-right: none; border-bottom: none; padding: 4px;"></td>
                <td style="border: 1px solid #000; border-left: none; border-right: none; border-bottom: none; padding: 4px;"></td>
                <td style="border: 1px solid #000; border-left: none; border-right: none; border-bottom: none; padding: 4px;"></td>
                <td style="border: 1px solid #000; border-left: none; border-right: none; border-bottom: none; padding: 4px;"></td>
                <td style="border: 1px solid #000; border-right: none; padding: 4px; text-align: center;">Итого</td>
                <td style="border: 1px solid #000; padding: 4px; text-align: center;"><%= Decimal.to_string(total_qty, :normal) %></td>
                <td style="border: 1px solid #000; padding: 4px; text-align: center;">x</td>
                <td style="border: 1px solid #000; padding: 4px; text-align: right;"><%= EdocApiWeb.ContractHTML.money(total_amount) %></td>
                <td style="border: 1px solid #000; padding: 4px; text-align: right;"><%= EdocApiWeb.ContractHTML.money(total_vat) %></td>
              </tr>
            </tbody>
          </table>

          <% executor_title = assigns[:executor_title] || "Директор" %>
          <% appendix_pages = assigns[:appendix_pages] || "_____________" %>
          <% acceptance_date = assigns[:acceptance_date] || fmt_date(act.actual_date) %>
          <table style="width: 100%; border-collapse: collapse; table-layout: fixed; margin-top: 12px; font-family: Arial, sans-serif; font-size: 11px; line-height: 1.15;">
            <colgroup>
              <%= for _ <- 1..28 do %>
                <col style="width: 3.5714%;" />
              <% end %>
            </colgroup>
            <tr>
              <td colspan="7" style="border: none; padding: 2px 3px; text-align: left; white-space: nowrap;">Сведения об использовании запасов, полученных от заказчика</td>
              <td colspan="7" style="border: none; border-bottom: 1px solid #000;"></td>
              <td colspan="14" style="border: none; border-bottom: 1px solid #000;"></td>
            </tr>
            <tr>
              <td colspan="11" style="border: none; height: 16px;"></td>
              <td colspan="8" style="border: none; padding: 2px 3px; text-align: center; font-style: italic;">
                наименование, количество, стоимость
              </td>
              <td colspan="9" style="border: none;"></td>
            </tr>
            <tr>
              <td colspan="28" style="border: none; height: 10px;"></td>
            </tr>
            <tr>
              <td colspan="20" style="border: none; padding: 2px 3px 0 3px; text-align: left;">
                Приложение: Перечень документации, в том числе отчет(ы) о маркетинговых, научных исследованиях, консультационных и прочих услугах (обязательны при его
              </td>
              <td colspan="8" style="border: none;"></td>
            </tr>
            <tr>
              <td colspan="2" style="border: none;"></td>
              <td colspan="5" style="border: none; padding: 0 3px; text-align: right; vertical-align: bottom;">
                <div style="display: flex; align-items: flex-end; width: 100%; height: 100%; justify-content: flex-end;">
                  <span>(их) наличии) на <%= appendix_pages %> </span>
                  <span style="line-height: 1; margin: 0 4px -1px 7px;">страниц</span>
                  <span style="flex: 1; border-bottom: 1px solid #000; height: 0; margin-bottom: -1px;"></span>
                </div>
              </td>
              <td colspan="21" style="border: none; border-bottom: 1px solid #000;"></td>
            </tr>
            <tr>
              <td colspan="28" style="border: none; height: 14px;"></td>
            </tr>
            <tr>
              <td colspan="3" style="border: none; padding: 2px 3px; text-align: left;">Сдал (Исполнитель)</td>
              <td colspan="2" style="border: none; border-bottom: 1px solid #000; padding: 2px 3px; text-align: center;"><%= executor_title %></td>
              <td colspan="3" style="border: none; border-bottom: 1px solid #000; padding: 2px 3px; text-align: left;">/</td>
              <td colspan="4" style="border: none; border-bottom: 1px solid #000; padding: 2px 3px; text-align: left;">/</td>
              <td colspan="2" style="border: none;"></td>
              <td colspan="3" style="border: none; padding: 2px 3px; text-align: left;">Принял (Заказчик)</td>
              <td colspan="3" style="border: none; border-bottom: 1px solid #000;"></td>
              <td colspan="3" style="border: none; border-bottom: 1px solid #000; padding: 2px 3px; text-align: left;">/</td>
              <td colspan="4" style="border: none; border-bottom: 1px solid #000; padding: 2px 3px; text-align: left;">/</td>
            </tr>
            <tr>
              <td colspan="3" style="border: none;"></td>
              <td colspan="2" style="border: none; padding: 1px 3px; text-align: center; font-style: italic;">должность</td>
              <td colspan="3" style="border: none; padding: 1px 3px; text-align: center; font-style: italic;">подпись</td>
              <td colspan="4" style="border: none; padding: 1px 3px; text-align: center; font-style: italic;">расшифровка подписи</td>
              <td colspan="2" style="border: none;"></td>
              <td colspan="5" style="border: none; padding: 1px 3px 1px 2px; text-align: right; font-style: italic;">должность</td>
              <td colspan="4" style="border: none; padding: 1px 3px; text-align: center; font-style: italic;">подпись</td>
              <td colspan="4" style="border: none; padding: 1px 3px; text-align: center; font-style: italic;">расшифровка подписи</td>
            </tr>
            <tr>
              <td colspan="28" style="border: none; height: 8px;"></td>
            </tr>
            <tr>
              <td colspan="4" style="border: none; padding: 2px 3px 2px 15px; text-align: left; font-weight: 700;">М.П.</td>
              <td colspan="10" style="border: none;"></td>
              <td colspan="8" style="border: none; padding: 2px 3px; text-align: left;">
                <div style="display: flex; align-items: flex-end;">
                  <span style="margin-right: 6px;">Дата подписания (принятия) работ (услуг)</span>
                  <span style="flex: 1; border-bottom: 1px solid #000; text-align: center; line-height: 1;">
                    <span style="display: inline-block; padding: 0 6px; background: #fff; white-space: nowrap;"><%= acceptance_date %></span>
                  </span>
                </div>
              </td>
              <td colspan="6" style="border: none;"></td>
            </tr>
            <tr>
              <td colspan="28" style="border: none; height: 8px;"></td>
            </tr>
            <tr>
              <td colspan="14" style="border: none;"></td>
              <td colspan="8" style="border: none; padding: 2px 3px 2px 15px; text-align: left; font-weight: 700;">М.П.</td>
              <td colspan="6" style="border: none;"></td>
            </tr>
          </table>
        </div>
      </body>
    </html>
    """
  end

  defp contract(assigns) do
    ~H"""
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          body { font-family: Arial, sans-serif; font-size: 12px; color:#000; line-height: 1.35; position: relative; }
          h1 { font-size: 16px; text-align:center; margin: 8px 0; }
          h2 { font-size: 13px; margin: 12px 0 6px; }
          .center { text-align:center; }
          .right { text-align:right; }
          .muted { color:#333; }
          .hr { border-top: 2px solid #000; margin: 10px 0; }
          table { width:100%; border-collapse: collapse; margin-top: 8px; }
          th, td { border: 1px solid #000; padding: 6px; vertical-align: top; }
          th { background: #f2f2f2; }
          .no-border td { border: none; padding: 2px 0; }
          .sign td { border: none; padding-top: 18px; }
          .stamp { border: 1px dashed #777; height: 60px; width: 170px; margin-top: 8px; }
          .small { font-size: 11px; }
          .signed-watermark {
            position: absolute;
            top: 50%;
            left: 0;
            right: 0;
            margin-top: -28px;
            text-align: center;
            -webkit-transform: rotate(-24deg);
            transform: rotate(-24deg);
            font-size: 56px;
            font-weight: 700;
            color: rgba(5, 150, 105, 0.18);
            letter-spacing: 2px;
            text-transform: uppercase;
            white-space: nowrap;
            z-index: 999;
          }
        </style>
      </head>

      <body>
        <% c = @contract %>
        <% seller = @seller %>
        <% buyer = @buyer %>
        <% bank = @bank %>
        <% items = @items %>
        <% totals = @totals %>
        <%= if c.status == "signed" do %>
          <div class="signed-watermark">Подписан - Қол қойылған</div>
        <% end %>

        <h1>ДОГОВОР № <%= c.number || "____" %></h1>
        <div class="center muted">
          г. <%= c.city || "Астана" %>, <%= fmt_date(c.issue_date) %> г.
        </div>

        <div class="hr"></div>

        <!-- 0. Преамбула -->
        <p>
          <strong><%= EdocApi.LegalForms.display(buyer.legal_form) %> «<%= buyer.name || "____________" %>»</strong>,
          БИН <strong><%= buyer.bin_iin || "____________" %></strong>,
          адрес: <%= buyer.address || "____________" %>,
          в лице <strong><%= buyer.director_title || "Директора" %> <%= buyer.director_name || "____________" %></strong>,
          действующего на основании <strong><%= buyer.basis || "Устава" %></strong>,
          именуемое далее «Заказчик», с одной стороны, и

          <strong><%= EdocApi.LegalForms.display(seller.legal_form) %> «<%= seller.name || "____________" %>»</strong>,
          БИН <strong><%= seller.bin_iin || "____________" %></strong>,
          адрес: <%= seller.address || "____________" %>,
          в лице <strong><%= seller.director_title %> <%= seller.director_name || "____________" %></strong>,
          действующего на основании <strong><%= seller.basis %></strong>,
          именуемое далее «Исполнитель», с другой стороны, совместно именуемые «Стороны»,
          заключили настоящий Договор о нижеследующем.
        </p>

        <!-- 1. Предмет -->
        <h2>1. Предмет Договора</h2>
        <p>
          1.1. Исполнитель обязуется оказать Заказчику услуги/выполнить работы/поставить товары,
          а Заказчик обязуется принять и оплатить их на условиях настоящего Договора.
        </p>
        <p>
          1.2. Перечень, количество и стоимость указываются в <strong>Приложении №1</strong> (Спецификация),
          являющемся неотъемлемой частью Договора.
        </p>

        <!-- 2. Стоимость и НДС -->
        <h2>2. Стоимость, НДС и порядок оплаты</h2>
        <p>
          2.1. Стоимость по Договору: <strong><%= money(totals.total) %> <%= c.currency || "KZT" %></strong>,
          <strong><%= vat_text(c) %></strong>.
        </p>
        <p>
          2.2. Оплата: безналичным переводом на расчетный счет Исполнителя
          в течение <strong>5</strong> (пяти) банковских дней с даты выставления счета,
          если иное не согласовано Сторонами письменно.
        </p>
        <p>
          2.3. Датой оплаты считается дата поступления денежных средств на счет Исполнителя.
        </p>

        <!-- 3. Порядок оказания и приемки -->
        <h2>3. Порядок оказания услуг и приемки</h2>
        <p>
          3.1. Срок оказания услуг: <strong>в сроки, согласованные Сторонами</strong>.
        </p>
        <p>
          3.2. По факту оказания услуг Стороны подписывают <strong>Акт оказанных услуг</strong>
          (может быть в электронном виде по согласованию).
        </p>
        <p>
          3.3. Если Заказчик не предоставил мотивированные замечания в течение
          <strong>5</strong> рабочих дней с даты получения Акта,
          услуги считаются принятыми в полном объеме.
        </p>

        <!-- 4. Ответственность -->
        <h2>4. Ответственность Сторон</h2>
        <p>
          4.1. За просрочку оплаты Заказчик уплачивает пеню <strong>0,1%</strong> от суммы задолженности за каждый день просрочки,
          но не более <strong>10%</strong> от суммы задолженности.
        </p>
        <p>
          4.2. Стороны несут ответственность согласно законодательству Республики Казахстан.
        </p>

        <!-- 5. Форс-мажор -->
        <h2>5. Форс-мажор</h2>
        <p>
          5.1. Стороны освобождаются от ответственности при наступлении обстоятельств непреодолимой силы,
          при условии уведомления другой стороны в разумный срок.
        </p>

        <!-- 6. Споры -->
        <h2>6. Порядок разрешения споров</h2>
        <p>
          6.1. Споры решаются путем переговоров; при недостижении согласия — в суде Республики Казахстан
          по месту нахождения ответчика (если не согласовано иное).
        </p>

        <!-- 7. Срок действия -->
        <h2>7. Срок действия</h2>
        <p>
          7.1. Договор вступает в силу с даты подписания и действует до
          <strong>полного исполнения обязательств</strong>.
        </p>

        <div class="hr"></div>

        <!-- Реквизиты -->
        <h2>Реквизиты Сторон</h2>
        <table style="width:100%; table-layout: fixed;">
          <thead>
            <tr>
              <th style="width:50%;">Исполнитель</th>
              <th style="width:50%;">Заказчик</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>
                <div><strong><%= EdocApi.LegalForms.display(seller.legal_form) %> «<%= seller.name || "____________" %>»</strong></div>
                <div>БИН: <%= seller.bin_iin || "____________" %></div>
                <div>Адрес: <%= seller.address || "____________" %></div>
                <div>Республика Казахстан, г. <%= Map.get(seller, :city) || "____________" %></div>
                <div>Банк: <%= if bank.bank_name in [nil, ""], do: "____________", else: bank.bank_name %></div>
                <div>БИК: <%= if bank.bic in [nil, ""], do: "____________", else: bank.bic %></div>
                <div>ИИК: <%= if bank.iban in [nil, ""], do: "____________", else: bank.iban %></div>
                <%= if seller.phone && seller.phone != "" do %>
                  <div>Тел.: <%= seller.phone %></div>
                <% end %>
                <%= if seller.email && seller.email != "" do %>
                  <div>Email: <%= seller.email %></div>
                <% end %>
              </td>

              <td>
                <div><strong><%= EdocApi.LegalForms.display(buyer.legal_form) %> «<%= buyer.name || "____________" %>»</strong></div>
                <div>БИН: <%= buyer.bin_iin || "____________" %></div>
                <div>Адрес: <%= buyer.address || "____________" %></div>
                <div>Республика Казахстан, г. <%= Map.get(buyer, :city) || "____________" %></div>
                <div>Банк: <%= if buyer.bank_name in [nil, ""], do: "____________", else: buyer.bank_name %></div>
                <div>БИК: <%= if buyer.bic in [nil, ""], do: "____________", else: buyer.bic %></div>
                <div>ИИК: <%= if buyer.iban in [nil, ""], do: "____________", else: buyer.iban %></div>
                <%= if buyer.phone && buyer.phone != "" do %>
                  <div>Тел.: <%= buyer.phone %></div>
                <% end %>
                <%= if buyer.email && buyer.email != "" do %>
                  <div>Email: <%= buyer.email %></div>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>

        <!-- Подписи -->
        <table class="sign" style="width:100%;">
          <tr>
            <td style="width:50%;">
              <strong>Исполнитель</strong><br/>
              <%= seller.director_title %><br/><br/>
              ____________________________ <%= seller.director_name || "____________" %><br/>
              <div class="stamp small muted">М.П.</div>
            </td>
            <td style="width:50%;">
              <strong>Заказчик</strong><br/>
              <%= buyer.director_title || "Директор" %><br/><br/>
              ____________________________ <%= buyer.director_name || "____________" %><br/>
              <div class="stamp small muted">М.П.</div>
            </td>
          </tr>
        </table>

        <!-- Приложение №1 -->
        <div style="page-break-before: always;"></div>

        <h1>ПРИЛОЖЕНИЕ №1 (СПЕЦИФИКАЦИЯ)</h1>
        <div class="center muted small">
          к Договору № <%= c.number || "____" %> от <%= fmt_date(c.issue_date) %> г.
        </div>

        <table>
          <thead>
            <tr>
              <th class="center" style="width:40px;">№</th>
              <th>Наименование</th>
              <th class="center" style="width:90px;">Ед. изм.</th>
              <th class="center" style="width:80px;">Кол-во</th>
              <th class="right" style="width:120px;">Цена</th>
              <th class="right" style="width:140px;">Сумма</th>
            </tr>
          </thead>
          <tbody>
            <%= for {item, idx} <- Enum.with_index(items, 1) do %>
              <tr>
                <td class="center"><%= idx %></td>
                <td><%= item.name %></td>
                <td class="center"><%= item.code || "—" %></td>
                <td class="center"><%= item.qty %></td>
                <td class="right"><%= money(item.unit_price) %></td>
                <td class="right"><%= money(item.amount) %></td>
              </tr>
            <% end %>

            <%= if length(items) == 0 do %>
              <tr>
                <td class="center">—</td>
                <td>—</td>
                <td class="center">—</td>
                <td class="center">—</td>
                <td class="right">—</td>
                <td class="right">—</td>
              </tr>
            <% end %>

            <tr>
              <td colspan="5" class="right"><strong>Итого без НДС</strong></td>
              <td class="right"><strong><%= money(totals.subtotal) %></strong></td>
            </tr>
            <tr>
              <td colspan="5" class="right"><strong>НДС <%= c.vat_rate || 0 %>%</strong></td>
              <td class="right"><%= money(totals.vat) %></td>
            </tr>
            <tr>
              <td colspan="5" class="right"><strong>Итого</strong></td>
              <td class="right"><strong><%= money(totals.total) %></strong></td>
            </tr>
          </tbody>
        </table>

        <table class="sign" style="width:100%; margin-top: 14px;">
          <tr>
            <td style="width:50%;">
              <strong>Заказчик</strong><br/><br/>
              ____________________________ <%= buyer.director_name || "____________" %><br/>
              <div class="stamp small muted">М.П.</div>
            </td>
            <td style="width:50%;">
              <strong>Исполнитель</strong><br/><br/>
              ____________________________ <%= seller.director_name || "____________" %><br/>
              <div class="stamp small muted">М.П.</div>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  # HEEx шаблон
  defp invoice(assigns) do
    ~H"""
    <!doctype html>
        <html>
        <head>
            <meta charset="utf-8" />
            <style>
                body { font-family: Arial, sans-serif; font-size: 12px; color: #000; position: relative; }
                .note { font-size: 10px; margin-bottom: 10px; }
                h1 { font-size: 16px; margin: 10px 0; }
                .box { border: 1px solid #000; padding: 8px; margin-bottom: 10px; }
                table { width: 100%; border-collapse: collapse; margin-top: 8px; }
                th, td { border: 1px solid #000; padding: 6px; }
                .transparent-row td {
                  border: none !important;
                  background: transparent !important;
                }
                th { background: #f2f2f2; }
                .right { text-align: right; }
                .center { text-align: center; }
                .small { font-size: 11px; }
                .no-border td { border: none; }
                .sign-row { margin-top: 30px; display: flex; gap: 40px; align-items: flex-end; }
                .sign { width: 60%; }
                .line { border-bottom: 1px solid #000; height: 18px; }
                .caption { font-size: 11px; margin-top: 4px; }
                .stamp {
                  width: 140px; height: 140px;
                  border: 2px dashed #444; border-radius: 50%;
                  display: flex; align-items: center; justify-content: center;
                  font-size: 11px; text-align: center;
                }
                .hr-strong {
                  border: none;
                  border-top: 2px solid #000;
                  margin: 10px 0;
                }
                .paid-watermark {
                  position: absolute;
                  top: 50%;
                  left: 0;
                  right: 0;
                  margin-top: -28px;
                  text-align: center;
                  -webkit-transform: rotate(-24deg);
                  transform: rotate(-24deg);
                  font-size: 56px;
                  font-weight: 700;
                  color: rgba(185, 28, 28, 0.20);
                  letter-spacing: 2px;
                  text-transform: uppercase;
                  white-space: nowrap;
                  z-index: 999;
                }
            </style>
          </head>
          <body>
          <% c = assoc_loaded(@invoice.company) || %{} %>
          <% acc = assoc_loaded(@invoice.bank_account) %>
          <% snap = assoc_loaded(@invoice.bank_snapshot) %>
          <% contract = assoc_loaded(@invoice.contract) %>
          <% issued = InvoiceStatus.is_issued?(@invoice) %>
          <% bank = acc && acc.bank || (c && c.bank) %>
          <% kbe = assoc_loaded(@invoice.kbe_code) || (acc && acc.kbe_code) || (c && c.kbe_code) %>
          <% knp = assoc_loaded(@invoice.knp_code) || (acc && acc.knp_code) || (c && c.knp_code) %>

          <% bank_name = if issued, do: (snap && snap.bank_name) || "—", else: (bank && bank.name) || (c && c.bank_name) || "—" %>
          <% bank_bic  = if issued, do: (snap && snap.bic) || "—", else: (bank && bank.bic) || "—" %>
          <% kbe_code  = if issued, do: (snap && snap.kbe) || "—", else: (kbe && kbe.code) || "—" %>
          <% knp_code  = if issued, do: (snap && snap.knp) || "—", else: (knp && knp.code) || "—" %>
          <% iban = if issued, do: (snap && snap.iban) || "—", else: (acc && acc.iban) || (c && c.iban) || @invoice.seller_iban %>
          <% seller_legal_form =
            case Map.get(c, :legal_form) do
              value when is_binary(value) and value != "" -> LegalForms.display(value)
              _ -> nil
            end %>
          <% buyer_legal_form =
            cond do
              contract && Map.get(contract, :buyer) && is_binary(Map.get(contract.buyer, :legal_form)) &&
                  Map.get(contract.buyer, :legal_form) != "" ->
                LegalForms.display(contract.buyer.legal_form)

              contract && is_binary(Map.get(contract, :buyer_legal_form)) &&
                  Map.get(contract, :buyer_legal_form) != "" ->
                LegalForms.display(contract.buyer_legal_form)

              true ->
                nil
            end %>
          <% buyer_city =
            cond do
              contract && Map.get(contract, :buyer) && is_binary(Map.get(contract.buyer, :city)) &&
                  String.trim(Map.get(contract.buyer, :city)) != "" ->
                String.trim(contract.buyer.city)

              true ->
                nil
            end %>
          <% items = @invoice.items || [] %>
          <% items_count = length(items) %>
          <%= if InvoiceStatus.is_paid?(@invoice) do %>
            <div class="paid-watermark">Төлеген - Оплачено</div>
          <% end %>
          <!-- ВНИМАНИЕ -->
            <div class="note">
            Внимание! Оплата данного счета означает согласие с условиями поставки товара.
            <strong>Уведомление об оплате обязательно.</strong> Поставка товара осуществляется при наличии доверенности и документов, удостоверяющих личность.
            </div>

            <!-- ПЛАТЕЖНОЕ ПОРУЧЕНИЕ -->
            <!-- БЕНЕФИЦИАР (как в банковском счёте) -->
             <table style="width:100%; border-collapse: collapse; margin-bottom: 12px;" class="small">
               <tr>
                 <td style="border:1px solid #000; padding:6px;" colspan="1">
                   <strong>Бенефициар:</strong><br/>
                   <%= if seller_legal_form, do: seller_legal_form <> " " %><%= c.name || @invoice.seller_name %><br/>
                   БИН: <%= c.bin_iin || @invoice.seller_bin_iin %>
                 </td>

                 <td style="border:1px solid #000; padding:6px;">
                   <strong>ИИК</strong><br/>
                   <%= iban %>
                 </td>

                 <td style="border:1px solid #000; padding:6px; width:60px;">
                   <strong>КБе</strong><br/>
                   <%= kbe_code %>
                 </td>
               </tr>

               <tr>
                 <td style="border:1px solid #000; padding:6px;">
                   <strong>Банк бенефициара:</strong><br/>
                   <%= bank_name %>
                 </td>

                 <td style="border:1px solid #000; padding:6px;">
                   <strong>БИК</strong><br/>
                   <%= bank_bic %>
                 </td>

                 <td style="border:1px solid #000; padding:6px;">
                   <strong>КНП</strong><br/>
                   <%= knp_code %>
                 </td>
               </tr>
             </table>

            <!-- ЗАГОЛОВОК -->
            <h1>Счет на оплату № <%= @invoice.number %> от <%= fmt_date(@invoice.issue_date) %></h1>
            <hr class="hr-strong" />
            <!-- ПОСТАВЩИК / ПОКУПАТЕЛЬ -->
            <table class="no-border">
                <tr>
                    <td><strong>Поставщик:</strong></td>
                    <td>
                    БИН/ИИН <%= @invoice.seller_bin_iin %>,
                    <%= if seller_legal_form, do: seller_legal_form <> " " %><%= @invoice.seller_name %>,
                    Республика Казахстан,
                    <%= @invoice.seller_address %>,
                    </td>
                </tr>
                <tr>
                <td><strong>Покупатель:</strong></td>
                <td>
                БИН/ИИН <%= @invoice.buyer_bin_iin %>,
                 <%= if buyer_legal_form, do: buyer_legal_form <> " " %><%= @invoice.buyer_name %><%= if buyer_city, do: ", Республика Казахстан, г. " <> buyer_city %>,
                 <%= @invoice.buyer_address %>
                </td>
                </tr>
                <tr>
                <td><strong>Основание:</strong></td>
                <td>
                <%= if contract do %>
                  Договор № <%= contract.number %> от <%= fmt_date(contract.issue_date) %>
                <% else %>
                  Без договора
                <% end %>
                </td>
                </tr>
                <tr>
                <td><strong>Дата окончания:</strong></td>
                <td><%= if @invoice.due_date, do: fmt_date(@invoice.due_date), else: "Без окончания" %></td>
                </tr>
            </table>

        <!-- ТАБЛИЦА -->
        <table>
          <thead>
            <tr>
              <th class="center">№</th>
              <th>Наименование</th>
              <th class="center">Кол-во</th>
              <th class="center">Ед.</th>
              <th class="right">Цена</th>
              <th class="right">Сумма</th>
            </tr>
          </thead>
          <tbody>
            <%= for {item, idx} <- Enum.with_index(items, 1) do %>
              <tr>
                <td class="center"><%= idx %></td>
                <td><%= item.name %></td>
                <td class="center"><%= item.qty %></td>
                <td class="center"><%= item.code || "—" %></td>
                <td class="right"><%= money(item.unit_price) %></td>
                <td class="right"><%= money(item.amount) %></td>
              </tr>
            <% end %>

            <%= if items_count == 0 do %>
              <tr>
                <td class="center">—</td>
                <td>—</td>
                <td class="center">—</td>
                <td class="center">—</td>
                <td class="right">—</td>
                <td class="right">—</td>
              </tr>
            <% end %>
            <!-- ИТОГО -->
              <tr class="transparent-row">
                <td colspan="4"></td>
                <td class="right"><strong>Итого:</strong></td>
                <td class="right"><strong><%= money(@invoice.total) %></strong></td>
              </tr>

              <!-- НДС -->
              <tr class="transparent-row">
                <td colspan="4"></td>
                <td class="right"><strong>В том числе НДС:</strong></td>
                <td class="right"><%= vat_line(@invoice) %></td>
              </tr>
          </tbody>
         </table>

        <p class="small">
          Всего наименований: <%= items_count %>, на сумму <%= money(@invoice.total) %> <%= @invoice.currency %>
        </p>
         <p>
          <strong>Всего к оплате:</strong>
          <strong><%= amount_words_kzt(@invoice.total) %></strong>
         </p>
         <hr class="hr-strong" />
        <!-- ПОДПИСЬ -->
        <br/><br/>
        <%!-- <p>Исполнитель _______________________</p> --%>
        <div class="sign-row">
          <div class="sign">
            <div>Руководитель: <strong><%= c.representative_name || "____________" %></strong></div>
            <div class="line"></div>
            <div class="caption">подпись</div>
          </div>
          <div class="stamp">
            М.П.<br/>Печать
          </div>
        </div>
        </body>
        </html>
    """
  end
end
