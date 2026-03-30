defmodule EdocApi.Buyers do
  @moduledoc """
  Context module for buyer (counterparty) operations.
  """
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Errors
  alias EdocApi.Core.Buyer
  alias EdocApi.Core.BuyerBankAccount
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
  Supports optional pagination via :limit and :offset.
  """
  def list_buyers_for_company(company_id, opts \\ []) when is_binary(company_id) do
    Buyer
    |> where(company_id: ^company_id)
    |> order_by([b], asc: b.name)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc """
  Creates a buyer for a company.
  """
  def create_buyer_for_company(company_id, attrs) when is_binary(company_id) do
    {buyer_attrs, bank_attrs} = split_attrs(attrs)

    case Repo.transaction(fn ->
           buyer_changeset = Buyer.changeset(%Buyer{}, buyer_attrs, company_id)

           buyer =
             case Repo.insert(buyer_changeset) do
               {:ok, buyer} -> buyer
               {:error, changeset} -> Repo.rollback({:changeset, changeset})
             end

           case maybe_upsert_default_bank_account(buyer.id, bank_attrs) do
             {:ok, _} -> buyer
             {:error, changeset} -> Repo.rollback({:changeset, changeset})
           end
         end) do
      {:ok, buyer} ->
        {:ok, Repo.preload(buyer, bank_accounts: :bank)}

      {:error, {:changeset, changeset}} ->
        Errors.from_changeset({:error, changeset})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a buyer.
  """
  def update_buyer(buyer_id, attrs, company_id) when is_binary(buyer_id) do
    case get_buyer_for_company(buyer_id, company_id) do
      nil ->
        Errors.not_found(:buyer)

      buyer ->
        {buyer_attrs, bank_attrs} = split_attrs(attrs)

        case Repo.transaction(fn ->
               buyer_changeset = Buyer.update_changeset(buyer, buyer_attrs)

               updated_buyer =
                 case Repo.update(buyer_changeset) do
                   {:ok, updated_buyer} -> updated_buyer
                   {:error, changeset} -> Repo.rollback({:changeset, changeset})
                 end

               case maybe_upsert_default_bank_account(updated_buyer.id, bank_attrs) do
                 {:ok, _} -> updated_buyer
                 {:error, changeset} -> Repo.rollback({:changeset, changeset})
               end
             end) do
          {:ok, updated_buyer} ->
            {:ok, Repo.preload(updated_buyer, bank_accounts: :bank)}

          {:error, {:changeset, changeset}} ->
            Errors.from_changeset({:error, changeset})

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def get_default_bank_account(%Buyer{} = buyer) do
    bank_accounts =
      case buyer.bank_accounts do
        %Ecto.Association.NotLoaded{} -> []
        accounts -> accounts
      end

    Enum.find(bank_accounts, & &1.is_default) || List.first(bank_accounts)
  end

  def get_default_bank_account(buyer_id) when is_binary(buyer_id) do
    BuyerBankAccount
    |> where([a], a.buyer_id == ^buyer_id and a.is_default == true)
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil ->
        BuyerBankAccount
        |> where([a], a.buyer_id == ^buyer_id)
        |> order_by([a], desc: a.inserted_at)
        |> limit(1)
        |> Repo.one()

      account ->
        account
    end
    |> case do
      nil -> nil
      account -> Repo.preload(account, :bank)
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

  defp apply_pagination(query, opts) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)

    query =
      if is_integer(limit) do
        from(q in query, limit: ^limit)
      else
        query
      end

    if is_integer(offset) and offset > 0 do
      from(q in query, offset: ^offset)
    else
      query
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

  defp split_attrs(attrs) do
    buyer_attrs = Map.drop(attrs || %{}, ["bank_id", "iban", "bic"])
    bank_attrs = Map.take(attrs || %{}, ["bank_id", "iban", "bic"])
    {buyer_attrs, bank_attrs}
  end

  defp maybe_upsert_default_bank_account(_buyer_id, %{"bank_id" => bank_id})
       when bank_id in [nil, ""],
       do: {:ok, nil}

  defp maybe_upsert_default_bank_account(buyer_id, %{"bank_id" => bank_id} = attrs) do
    normalized_attrs = %{
      "bank_id" => bank_id,
      "iban" => blank_to_nil(attrs["iban"]),
      "bic" => blank_to_nil(attrs["bic"]),
      "is_default" => true
    }

    existing_default =
      BuyerBankAccount
      |> where([a], a.buyer_id == ^buyer_id and a.is_default == true)
      |> order_by([a], desc: a.inserted_at)
      |> limit(1)
      |> Repo.one()

    changeset =
      case existing_default do
        nil -> BuyerBankAccount.changeset(%BuyerBankAccount{}, normalized_attrs, buyer_id)
        account -> BuyerBankAccount.changeset(account, normalized_attrs, buyer_id)
      end

    case existing_default do
      nil -> Repo.insert(changeset)
      _ -> Repo.update(changeset)
    end
  end

  defp maybe_upsert_default_bank_account(_buyer_id, _attrs), do: {:ok, nil}

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v
end
