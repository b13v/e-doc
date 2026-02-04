defmodule EdocApiWeb.PdfTemplates do
  use Phoenix.Component

  alias EdocApi.InvoiceStatus
  alias EdocApi.Repo

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
        :buyer,
        :bank_account,
        :contract_items,
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

  defp build_seller_data(contract) do
    company = contract.company || %{}

    %{
      name: Map.get(company, :name) || contract.company_id || "",
      # Default, could be stored in company
      legal_form: "ТОО",
      bin_iin: Map.get(company, :bin_iin) || "",
      address: Map.get(company, :address) || "",
      director_name: Map.get(company, :representative_name) || "",
      director_title: "директор",
      basis: "Устав",
      phone: Map.get(company, :phone) || "",
      email: Map.get(company, :email) || ""
    }
  end

  defp build_buyer_data(contract) do
    if contract.buyer do
      buyer_entity = contract.buyer

      %{
        name: buyer_entity.name || "",
        legal_form: buyer_entity.legal_form || contract.buyer_legal_form || "ТОО",
        bin_iin: buyer_entity.bin_iin || "",
        address: buyer_entity.address || "",
        director_name: buyer_entity.director_name || contract.buyer_director_name || "",
        director_title: "директор",
        basis: buyer_entity.basis || contract.buyer_basis || "Устав",
        phone: buyer_entity.phone || contract.buyer_phone || "",
        email: buyer_entity.email || contract.buyer_email || ""
      }
    else
      %{
        name: contract.buyer_name || "",
        legal_form: contract.buyer_legal_form || "ТОО",
        bin_iin: contract.buyer_bin_iin || "",
        address: contract.buyer_address || "",
        director_name: contract.buyer_director_name || "",
        director_title: contract.buyer_director_title || "директор",
        basis: contract.buyer_basis || "Устав",
        phone: contract.buyer_phone || "",
        email: contract.buyer_email || ""
      }
    end
  end

  defp build_bank_data(contract) do
    if contract.bank_account do
      acc = contract.bank_account
      bank = acc.bank || %{}
      kbe = acc.kbe_code || %{}
      knp = acc.knp_code || %{}

      %{
        bank_name: Map.get(bank, :name) || "",
        iban: Map.get(acc, :iban) || "",
        bic: Map.get(bank, :bic) || "",
        kbe: Map.get(kbe, :code) || "",
        knp: Map.get(knp, :code) || ""
      }
    else
      # No bank account - return empty values (template will show blanks)
      %{
        bank_name: "",
        iban: "",
        bic: "",
        kbe: "",
        knp: ""
      }
    end
  end

  defp build_items_data(contract) do
    Enum.map(contract.contract_items || [], fn item ->
      %{
        name: Map.get(item, :name) || "",
        qty: Map.get(item, :qty) || Decimal.new(0),
        unit_price: Map.get(item, :unit_price) || Decimal.new(0),
        amount: Map.get(item, :amount) || Decimal.new(0),
        code: Map.get(item, :code)
      }
    end)
  end

  defp build_totals(items, vat_rate) do
    subtotal =
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, item.amount || Decimal.new(0))
      end)

    vat_rate_dec = Decimal.new(vat_rate || 0)

    vat =
      Decimal.mult(subtotal, vat_rate_dec) |> Decimal.div(Decimal.new(100)) |> Decimal.round(2)

    total = Decimal.add(subtotal, vat)

    %{
      subtotal: subtotal,
      vat: vat,
      total: total
    }
  end

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
    [int, frac] =
      case String.split(str, ".") do
        [i, f] -> [i, f]
        [i] -> [i, nil]
      end

    int =
      int
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
      |> String.reverse()

    if frac do
      int <> "." <> frac
    else
      int
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

    if feminine? do
      base
      |> String.replace_prefix("один", "одна")
      |> String.replace_prefix("два", "две")
    else
      base
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

  defp contract(assigns) do
    ~H"""
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          body { font-family: Arial, sans-serif; font-size: 12px; color:#000; line-height:1.35; }
          h1 { font-size: 16px; text-align:center; margin: 8px 0; }
          h2 { font-size: 13px; margin: 12px 0 6px; }
          .center { text-align:center; }
          .right { text-align:right; }
          .muted { color:#333; }
          .hr { border-top: 2px solid #000; margin: 10px 0; }
          table { width:100%; border-collapse: collapse; margin-top: 8px; }
          th, td { border: 1px solid #000; padding: 6px; }
          th { background:#f2f2f2; }
          .no-border td { border:none; padding:2px 0; }
          .sign td { border:none; padding-top:18px; }
          .stamp { border:1px dashed #777; height:60px; width:170px; margin-top:8px; }
          .small { font-size:11px; }
        </style>
      </head>

      <body>
        <h1>CONTRACT № <%= @contract.number || "____" %></h1>
        <div class="center muted">
          City <%= @contract.city || "Astana" %>,
          <%= fmt_date(@contract.issue_date) || "__.__.20__" %>
        </div>

        <div class="hr"></div>

        <p>
          <strong><%= @buyer.name %></strong>, BIN <strong><%= @buyer.bin_iin %></strong>,
          address: <%= @buyer.address %>,
          represented by <strong><%= @buyer.director_title %> <%= @buyer.director_name %></strong>,
          acting under the <strong><%= @buyer.basis || "Charter" %></strong>,
          hereinafter referred to as the "Customer", and
        </p>

        <p>
          <strong><%= @seller.name %></strong>, BIN <strong><%= @seller.bin_iin %></strong>,
          address: <%= @seller.address %>,
          represented by <strong><%= @seller.director_title %> <%= @seller.director_name %></strong>,
          acting under the <strong><%= @seller.basis || "Charter" %></strong>,
          hereinafter referred to as the "Contractor", jointly referred to as the "Parties".
        </p>

        <h2>1. Subject</h2>
        <p>
          The Contractor undertakes to provide services specified in Appendix №1 (Specification),
          and the Customer undertakes to accept and pay for them.
        </p>

        <h2>2. Price and VAT</h2>
        <p>
          Total contract value: <strong><%= money(@totals.total) %> <%= @contract.currency %></strong>,
          <%= vat_text(@contract) %>.
        </p>

        <h2>3. Acceptance of Services</h2>
        <p>
          Services are accepted based on the Act of Services Rendered.
          If no objections are provided within 5 business days, services are deemed accepted.
        </p>

        <h2>4. Liability</h2>
        <p class="small">
          Late payment penalty: 0.1% per day, but not more than 10% of the outstanding amount.
        </p>

        <h2>5. Force Majeure</h2>
        <p class="small">
          Parties are released from liability in case of force majeure circumstances.
        </p>

        <h2>6. Disputes</h2>
        <p class="small">
          Disputes are resolved in courts of the Republic of Kazakhstan.
        </p>

        <h2>7. Term</h2>
        <p class="small">
          Contract is valid until full fulfillment of obligations.
        </p>

        <div class="hr"></div>

        <h2>Details and Signatures</h2>
        <table>
          <tr>
            <th>Contractor</th>
            <th>Customer</th>
          </tr>
          <tr>
            <td>
              <strong><%= @seller.name %></strong><br/>
              BIN: <%= @seller.bin_iin %><br/>
              Address: <%= @seller.address %><br/>
              Bank: <%= @bank.bank_name %><br/>
              IBAN: <%= @bank.iban %><br/>
              BIC: <%= @bank.bic %><br/>
              KBe: <%= @bank.kbe %><br/>
              KNP: <%= @bank.knp %>
            </td>
            <td>
              <strong><%= @buyer.name %></strong><br/>
              BIN: <%= @buyer.bin_iin %><br/>
              Address: <%= @buyer.address %>
            </td>
          </tr>
        </table>

        <table class="sign" style="width:100%;">
          <tr>
            <td width="50%">
              Contractor<br/><br/>
              ____________________ <%= @seller.director_name %><br/>
              <div class="stamp">Stamp</div>
            </td>
            <td width="50%">
              Customer<br/><br/>
              ____________________ <%= @buyer.director_name %><br/>
              <div class="stamp">Stamp</div>
            </td>
          </tr>
        </table>

        <div style="page-break-before:always;"></div>

        <h1>APPENDIX №1 — SPECIFICATION</h1>

        <table>
          <tr>
            <th>#</th>
            <th>Description</th>
            <th>Qty</th>
            <th>Price</th>
            <th>Amount</th>
          </tr>
          <%= for {item, idx} <- Enum.with_index(@items, 1) do %>
            <tr>
              <td><%= idx %></td>
              <td><%= item.name %></td>
              <td><%= item.qty %></td>
              <td class="right"><%= money(item.unit_price) %></td>
              <td class="right"><%= money(item.amount) %></td>
            </tr>
          <% end %>
          <tr>
            <td colspan="4" class="right"><strong>Total</strong></td>
            <td class="right"><strong><%= money(@totals.total) %></strong></td>
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
                body { font-family: Arial, sans-serif; font-size: 12px; color: #000; }
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
            </style>
          </head>
          <body>
          <% c = assoc_loaded(@invoice.company) || %{} %>
          <% acc = assoc_loaded(@invoice.bank_account) %>
          <% snap = assoc_loaded(@invoice.bank_snapshot) %>
          <% contract = assoc_loaded(@invoice.contract) %>
          <% issued = InvoiceStatus.is_issued?(@invoice) %>
          <% bank = acc && acc.bank || (c && c.bank) %>
          <% kbe = acc && acc.kbe_code || (c && c.kbe_code) %>
          <% knp = acc && acc.knp_code || (c && c.knp_code) %>

          <% bank_name = if issued, do: (snap && snap.bank_name) || "—", else: (bank && bank.name) || (c && c.bank_name) || "—" %>
          <% bank_bic  = if issued, do: (snap && snap.bic) || "—", else: (bank && bank.bic) || "—" %>
          <% kbe_code  = if issued, do: (snap && snap.kbe) || "—", else: (kbe && kbe.code) || "—" %>
          <% knp_code  = if issued, do: (snap && snap.knp) || "—", else: (knp && knp.code) || "—" %>
          <% iban = if issued, do: (snap && snap.iban) || "—", else: (acc && acc.iban) || (c && c.iban) || @invoice.seller_iban %>
          <% items = @invoice.items || [] %>
          <% items_count = length(items) %>
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
                   <%= c.name || @invoice.seller_name %><br/>
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
                    <%= @invoice.seller_name %>,
                    <%= @invoice.seller_address %>,
                    </td>
                </tr>
                <tr>
                <td><strong>Покупатель:</strong></td>
                <td>
                БИН/ИИН <%= @invoice.buyer_bin_iin %>,
                 <%= @invoice.buyer_name %>,
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
              <th class="center">Код</th>
              <th>Наименование</th>
              <th class="center">Кол-во</th>
              <th class="right">Цена</th>
              <th class="right">Сумма</th>
            </tr>
          </thead>
          <tbody>
            <%= for {item, idx} <- Enum.with_index(items, 1) do %>
              <tr>
                <td class="center"><%= idx %></td>
                <td class="center"><%= item.code || "—" %></td>
                <td><%= item.name %></td>
                <td class="center"><%= item.qty %></td>
                <td class="right"><%= money(item.unit_price) %></td>
                <td class="right"><%= money(item.amount) %></td>
              </tr>
            <% end %>

            <%= if items_count == 0 do %>
              <tr>
                <td class="center">—</td>
                <td class="center">—</td>
                <td>—</td>
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
