defmodule EdocApiWeb.WorkspaceOverviewUiTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  test "invoice index marks invoices nav active in the workspace shell", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    _draft = insert_invoice!(user, company, %{status: "draft", number: nil})
    _issued = insert_invoice!(user, company, %{status: "issued", number: "INV-2"})

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/invoices")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
    assert body =~ ~s(action="/logout")
    refute body =~ ~r/<a[^>]*href="\/buyers"[^>]*aria-current="page"/
  end

  test "buyer edit keeps buyers nav active in the workspace shell", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Acme Buyer",
        "bin_iin" => "060215385673"
      })

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/buyers/#{buyer.id}/edit")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/buyers"[^>]*aria-current="page"/
    refute body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
  end

  @tag :skip
  test "workspace_row_actions renders inline and overflow affordances", _context do
    html =
      %{
        primary: %{label: "View", transport: :link, method: :get, href: "/invoices/1"},
        secondary: [
          %{
            label: "Delete",
            transport: :htmx_delete,
            method: :delete,
            hx_delete: "/invoices/1",
            row_dom_id: "invoice-1",
            confirm_text: "Delete this invoice?"
          }
        ],
        mobile_mode: :overflow,
        row_id: "invoice-1"
      }
      |> EdocApiWeb.CoreComponents.workspace_row_actions()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ ~r/<a[^>]*href="\/invoices\/1"[^>]*>\s*View\s*<\/a>/s
    assert html =~ ~r/<(button|summary)[^>]*>\s*Actions\s*<\/(button|summary)>/s
    assert html =~ ~r/hx-delete="\/invoices\/1"/
    assert html =~ ~r/id="invoice-1"/
  end

  test "flash_error renders the shared error surface", _context do
    html =
      %{flash: %{"error" => "Validation failed"}}
      |> EdocApiWeb.CoreComponents.flash_error()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "Validation failed"
    assert html =~ "bg-red-50"
  end

  defp browser_conn(conn, user, locale) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id, locale: locale})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end
end
