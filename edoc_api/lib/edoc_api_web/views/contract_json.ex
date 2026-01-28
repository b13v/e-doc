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
      date: contract.date,
      title: contract.title,
      status: contract.status,
      issued_at: contract.issued_at,
      body_html: contract.body_html
    }
  end
end
