defmodule EdocApiWeb.BuyerJSON do
  def index(%{buyers: buyers}) do
    %{data: Enum.map(buyers, &buyer/1)}
  end

  def show(%{buyer: buyer}) do
    buyer(buyer)
  end

  defp buyer(buyer) do
    %{
      id: buyer.id,
      name: buyer.name,
      legal_form: buyer.legal_form,
      bin_iin: buyer.bin_iin,
      address: buyer.address,
      city: buyer.city,
      phone: buyer.phone,
      email: buyer.email,
      director_name: buyer.director_name,
      director_title: buyer.director_title,
      basis: buyer.basis,
      inserted_at: buyer.inserted_at,
      updated_at: buyer.updated_at
    }
  end
end
