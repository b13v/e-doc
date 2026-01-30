defmodule EdocApiWeb.SessionHTML do
  use EdocApiWeb, :html

  embed_templates("session_html/*")

  def get_flash(conn, key) do
    Phoenix.Controller.get_flash(conn, key)
  end
end
