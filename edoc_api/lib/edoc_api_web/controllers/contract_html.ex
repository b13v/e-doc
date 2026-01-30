defmodule EdocApiWeb.ContractHTML do
  use EdocApiWeb, :html

  embed_templates("contract_html/*")

  def get_flash(conn, key) do
    Phoenix.Controller.get_flash(conn, key)
  end
end
