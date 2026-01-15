defmodule EdocApiWeb.DictController do
  use EdocApiWeb, :controller

  alias EdocApi.Payments

  def banks(conn, _params) do
    banks = Payments.list_banks()
    json(conn, %{banks: Enum.map(banks, &bank_json/1)})
  end

  def kbe(conn, _params) do
    codes = Payments.list_kbe_codes()
    json(conn, %{kbe_codes: Enum.map(codes, &code_json/1)})
  end

  def knp(conn, _params) do
    codes = Payments.list_knp_codes()
    json(conn, %{knp_codes: Enum.map(codes, &code_json/1)})
  end

  defp bank_json(b), do: %{id: b.id, name: b.name, bic: b.bic}
  defp code_json(c), do: %{id: c.id, code: c.code, description: c.description}
end
