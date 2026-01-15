defmodule EdocApiWeb.Serializers.InvoiceSerializer do
  def to_map(inv) do
    %{
      id: inv.id,
      number: inv.number,
      service_name: inv.service_name,
      issue_date: inv.issue_date,
      due_date: inv.due_date,
      currency: inv.currency,
      vat_rate: inv.vat_rate,
      subtotal: inv.subtotal,
      vat: inv.vat,
      total: inv.total,
      seller_name: inv.seller_name,
      seller_bin_iin: inv.seller_bin_iin,
      seller_address: inv.seller_address,
      seller_iban: inv.seller_iban,
      buyer_name: inv.buyer_name,
      buyer_bin_iin: inv.buyer_bin_iin,
      buyer_address: inv.buyer_address,
      status: inv.status,
      company_id: inv.company_id,
      user_id: inv.user_id,
      bank_account_id: inv.bank_account_id,
      items: Enum.map(inv.items || [], &item_to_map/1),
      inserted_at: inv.inserted_at,
      updated_at: inv.updated_at
    }
  end

  def item_to_map(item) do
    %{
      id: item.id,
      code: item.code,
      name: item.name,
      qty: item.qty,
      unit_price: item.unit_price,
      amount: item.amount
    }
  end
end
