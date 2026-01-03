defmodule EdocApiWeb.PdfTemplates do
  use Phoenix.Component

  # Возвращает HTML строкой (готово для wkhtmltopdf)
  def invoice_html(invoice) do
    assigns = %{invoice: invoice}

    invoice(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
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
                th { background: #f2f2f2; }
                .right { text-align: right; }
                .center { text-align: center; }
                .small { font-size: 11px; }
                .no-border td { border: none; }
            </style>
          </head>
          <body>

          <!-- ВНИМАНИЕ -->
            <div class="note">
            Внимание! Оплата данного счета означает согласие с условиями поставки товара.
            <strong>Уведомление об оплате обязательно.</strong> Поставка товара осуществляется при наличии доверенности и документов, удостоверяющих личность.
            </div>

            <!-- ПЛАТЕЖНОЕ ПОРУЧЕНИЕ -->
            <div class="box small">
                <strong>Бенефициар:</strong><br/>
                <%= @invoice.seller_name %><br/>
                БИН: <%= @invoice.seller_bin_iin %><br/>
                IBAN: <%= @invoice.seller_iban %>
            </div>

            <!-- ЗАГОЛОВОК -->
            <h1>Счет на оплату № <%= @invoice.number %> от <%= @invoice.issue_date %></h1>

            <!-- ПОСТАВЩИК / ПОКУПАТЕЛЬ -->
            <table class="no-border">
                <tr>
                    <td><strong>Поставщик:</strong></td>
                    <td>
                    <%= @invoice.seller_name %>,
                    БИН <%= @invoice.seller_bin_iin %>,
                    <%= @invoice.seller_address %>,
                    </td>
                </tr>
                <tr>
                <td><strong>Покупатель:</strong></td>
                <td>
                   <%= @invoice.buyer_name %>,
                   БИН <%= @invoice.buyer_bin_iin %>,
                   <%= @invoice.buyer_address %>
                </td>
                </tr>
                <tr>
                <td><strong>Договор:</strong></td>
                <td>Счет на оплату № <%= @invoice.number %> от <%= @invoice.issue_date %></td>
                </tr>
                <tr>
                <td><strong>Дата окончания:</strong></td>
                <td><%= @invoice.due_date || "Без окончания" %></td>
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
            <tr>
              <td class="center">1</td>
              <td class="center">—</td>
              <td><%= @invoice.service_name %></td>
              <td class="center">1</td>
              <td class="right"><%= @invoice.total %></td>
              <td class="right"><%= @invoice.total %></td>
            </tr>
          </tbody>
        </table>

        <!-- ИТОГИ -->
        <p class="small">
          Всего наименований: 1, на сумму <%= @invoice.total %> <%= @invoice.currency %>
        </p>

        <p>
          <strong>Всего к оплате:</strong>
          <%= @invoice.total %> <%= @invoice.currency %>
        </p>

        <!-- ПОДПИСЬ -->
        <br/><br/>
        <p>Исполнитель _______________________</p>

        </body>
        </html>
    """
  end
end
