defmodule EdocApiWeb.InvoicesHTML do
  use EdocApiWeb, :html

  embed_templates("invoices_html/*")

  def get_flash(conn, key) do
    Phoenix.Controller.get_flash(conn, key)
  end
end
