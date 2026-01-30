defmodule EdocApiWeb.CompanyHTML do
  use EdocApiWeb, :html

  embed_templates("company_html/*")

  def get_flash(conn, key) do
    Phoenix.Controller.get_flash(conn, key)
  end
end
