defmodule EdocApiWeb.ContractJSON do
  alias EdocApi.LegalForms

  def index(assigns) do
    contracts = Map.get(assigns, :contracts, [])
    meta = Map.get(assigns, :meta)

    %{data: Enum.map(contracts, &contract/1)}
    |> maybe_put_meta(meta)
  end

  def show(%{contract: contract}) do
    %{data: contract(contract)}
  end

  defp contract(contract) do
    %{
      id: contract.id,
      number: contract.number,
      issue_date: contract.issue_date,
      city: contract.city,
      currency: contract.currency,
      vat_rate: contract.vat_rate,
      title: contract.title,
      status: contract.status,
      issued_at: contract.issued_at,
      signed_at: contract.signed_at,
      body_html: contract.body_html,
      buyer_id: contract.buyer_id,
      buyer_name: contract.buyer_name,
      buyer_legal_form: LegalForms.display(contract.buyer_legal_form),
      buyer_bin_iin: contract.buyer_bin_iin,
      buyer_address: contract.buyer_address,
      buyer_director_name: contract.buyer_director_name,
      buyer_director_title: contract.buyer_director_title,
      buyer_basis: contract.buyer_basis,
      buyer_phone: contract.buyer_phone,
      buyer_email: contract.buyer_email,
      bank_account_id: contract.bank_account_id
    }
  end

  defp maybe_put_meta(payload, nil), do: payload
  defp maybe_put_meta(payload, meta), do: Map.put(payload, :meta, meta)
end
