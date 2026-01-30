defmodule EdocApiWeb.PageHTML do
  use EdocApiWeb, :html

  embed_templates("page_html/*")

  def get_flash(conn, key) do
    Phoenix.Controller.get_flash(conn, key)
  end
end
