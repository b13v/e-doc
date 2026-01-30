defmodule EdocApiWeb.InvoiceHTML do
  use EdocApiWeb, :html

  embed_templates("invoice_html/*")

  def get_flash(conn, key) do
    Phoenix.Controller.get_flash(conn, key)
  end
end
