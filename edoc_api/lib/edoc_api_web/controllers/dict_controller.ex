defmodule EdocApiWeb.DictController do
  use EdocApiWeb, :controller

  alias EdocApi.Payments
  alias EdocApiWeb.Serializers.DictSerializer

  def banks(conn, _params) do
    banks = Payments.list_banks()
    json(conn, %{banks: Enum.map(banks, &DictSerializer.bank_to_map/1)})
  end

  def kbe(conn, _params) do
    codes = Payments.list_kbe_codes()
    json(conn, %{kbe_codes: Enum.map(codes, &DictSerializer.code_to_map/1)})
  end

  def knp(conn, _params) do
    codes = Payments.list_knp_codes()
    json(conn, %{knp_codes: Enum.map(codes, &DictSerializer.code_to_map/1)})
  end
end
