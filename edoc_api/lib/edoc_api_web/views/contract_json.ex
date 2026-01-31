defmodule EdocApiWeb.ContractJSON do
  def index(%{contracts: contracts}) do
    %{data: Enum.map(contracts, &contract/1)}
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
      buyer_company_id: contract.buyer_company_id,
      buyer_name: contract.buyer_name,
      buyer_legal_form: contract.buyer_legal_form,
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
end
