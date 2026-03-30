defmodule EdocApiWeb.BuyerJSON do
  alias EdocApi.LegalForms

  def index(assigns) do
    buyers = Map.get(assigns, :buyers, [])
    meta = Map.get(assigns, :meta)

    %{data: Enum.map(buyers, &buyer/1)}
    |> maybe_put_meta(meta)
  end

  def show(%{buyer: buyer}) do
    buyer(buyer)
  end

  defp buyer(buyer) do
    %{
      id: buyer.id,
      name: buyer.name,
      legal_form: LegalForms.display(buyer.legal_form),
      bin_iin: buyer.bin_iin,
      address: buyer.address,
      city: buyer.city,
      phone: buyer.phone,
      email: buyer.email,
      bank: default_bank_map(buyer),
      director_name: buyer.director_name,
      director_title: buyer.director_title,
      basis: buyer.basis,
      inserted_at: buyer.inserted_at,
      updated_at: buyer.updated_at
    }
  end

  defp maybe_put_meta(payload, nil), do: payload
  defp maybe_put_meta(payload, meta), do: Map.put(payload, :meta, meta)

  defp default_bank_map(buyer) do
    bank_accounts =
      case Map.get(buyer, :bank_accounts) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        accounts -> accounts
      end

    case Enum.find(bank_accounts, & &1.is_default) || List.first(bank_accounts) do
      nil ->
        nil

      account ->
        %{
          bank_id: account.bank_id,
          bank_name: if(account.bank, do: account.bank.name, else: nil),
          iban: account.iban,
          bic: account.bic || if(account.bank, do: account.bank.bic, else: nil)
        }
    end
  end
end
