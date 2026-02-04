defmodule EdocApi.Buyers do
  @moduledoc """
  Context module for buyer (counterparty) operations.
  """
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Errors
  alias EdocApi.Core.Buyer
  alias EdocApi.Core.Company
  alias EdocApi.Validators.BinIin

  @doc """
  Gets a buyer by ID.
  """
  def get_buyer(id) when is_binary(id) do
    Repo.get(Buyer, id)
  end

  @doc """
  Gets a buyer by ID, preloading company.
  """
  def get_buyer_with_company(id) when is_binary(id) do
    Buyer
    |> Repo.get(id)
    |> case do
      nil -> nil
      buyer -> Repo.preload(buyer, :company)
    end
  end

  @doc """
  Gets a buyer by ID for a specific company.
  """
  def get_buyer_for_company(buyer_id, company_id)
      when is_binary(buyer_id) and is_binary(company_id) do
    Buyer
    |> where(id: ^buyer_id, company_id: ^company_id)
    |> Repo.one()
  end

  @doc """
  Lists all buyers for a company.
  """
  def list_buyers_for_company(company_id) when is_binary(company_id) do
    Buyer
    |> where(company_id: ^company_id)
    |> order_by([b], asc: b.name)
    |> Repo.all()
  end

  @doc """
  Creates a buyer for a company.
  """
  def create_buyer_for_company(company_id, attrs) when is_binary(company_id) do
    %Buyer{}
    |> Buyer.changeset(attrs, company_id)
    |> Repo.insert()
    |> Errors.from_changeset()
  end

  @doc """
  Updates a buyer.
  """
  def update_buyer(buyer_id, attrs, company_id) when is_binary(buyer_id) do
    case get_buyer_for_company(buyer_id, company_id) do
      nil ->
        Errors.not_found(:buyer)

      buyer ->
        buyer
        |> Buyer.update_changeset(attrs)
        |> Repo.update()
        |> Errors.from_changeset()
    end
  end

  @doc """
  Deletes a buyer (hard delete).
  """
  def delete_buyer(buyer_id, company_id) when is_binary(buyer_id) do
    case get_buyer_for_company(buyer_id, company_id) do
      nil ->
        Errors.not_found(:buyer)

      buyer ->
        case Repo.delete(buyer) do
          {:ok, _} -> {:ok, :deleted}
          {:error, changeset} -> Errors.from_changeset({:error, changeset})
        end
    end
  end

  @doc """
  Checks if a buyer can be deleted (not in use by contracts/invoices).
  """
  def can_delete?(buyer_id) when is_binary(buyer_id) do
    # Check if buyer is used in any contract
    contract_count =
      from(c in "contracts",
        where: c.buyer_company_id == ^buyer_id,
        select: count(c.id)
      )
      |> Repo.one()

    # Check if buyer is used in any invoice
    invoice_count =
      from(i in "invoices",
        where: i.buyer_company_id == ^buyer_id,
        select: count(i.id)
      )
      |> Repo.one()

    if contract_count > 0 or invoice_count > 0 do
      {:error, :in_use, %{contract_count: contract_count, invoice_count: invoice_count}}
    else
      {:ok, :can_delete}
    end
  end

  @doc """
  Searches buyers by name or BIN/IIN.
  """
  def search_buyers(company_id, query) when is_binary(company_id) and is_binary(query) do
    query = "%#{query}%"

    Buyer
    |> where(company_id: ^company_id)
    |> where([b], ilike(b.name, ^query) or ilike(b.bin_iin, ^query))
    |> order_by([b], asc: b.name)
    |> Repo.all()
  end

  @doc """
  Gets a buyer by BIN/IIN for a company.
  """
  def get_buyer_by_bin_iin(bin_iin, company_id)
      when is_binary(bin_iin) and is_binary(company_id) do
    normalized_bin = BinIin.normalize(bin_iin)

    Buyer
    |> where(company_id: ^company_id, bin_iin: ^normalized_bin)
    |> Repo.one()
  end

  @doc """
  Returns the count of buyers for a company.
  """
  def count_buyers_for_company(company_id) when is_binary(company_id) do
    Buyer
    |> where(company_id: ^company_id)
    |> Repo.aggregate(:count, :id)
  end
end
