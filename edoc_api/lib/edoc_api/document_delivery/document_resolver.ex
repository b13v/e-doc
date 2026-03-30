defmodule EdocApi.DocumentDelivery.DocumentResolver do
  import Ecto.Query, warn: false

  alias EdocApi.Acts
  alias EdocApi.Core
  alias EdocApi.Core.Act
  alias EdocApi.Core.Contract
  alias EdocApi.Core.Invoice
  alias EdocApi.Invoicing
  alias EdocApi.Repo

  def get_for_user(user_id, document_type, document_id) when is_binary(user_id) do
    with {:ok, normalized_type} <- normalize_document_type(document_type),
         {:ok, document} <- do_get_for_user(user_id, normalized_type, document_id) do
      {:ok, {normalized_type, document}}
    end
  end

  def get_public(document_type, document_id) do
    with {:ok, normalized_type} <- normalize_document_type(document_type),
         {:ok, document} <- do_get_public(normalized_type, document_id) do
      {:ok, {normalized_type, document}}
    end
  end

  def normalize_document_type(document_type) when document_type in [:invoice, :act, :contract],
    do: {:ok, document_type}

  def normalize_document_type(document_type) when is_binary(document_type) do
    case String.downcase(String.trim(document_type)) do
      "invoice" -> {:ok, :invoice}
      "act" -> {:ok, :act}
      "contract" -> {:ok, :contract}
      _ -> {:error, :unsupported_document_type}
    end
  end

  def normalize_document_type(_), do: {:error, :unsupported_document_type}

  defp do_get_for_user(user_id, :invoice, document_id) do
    case Invoicing.get_invoice_for_user(user_id, document_id) do
      nil -> {:error, :document_not_found}
      invoice -> {:ok, invoice}
    end
  end

  defp do_get_for_user(user_id, :contract, document_id) do
    case Core.get_contract_for_user(user_id, document_id) do
      {:ok, contract} -> {:ok, contract}
      _ -> {:error, :document_not_found}
    end
  end

  defp do_get_for_user(user_id, :act, document_id) do
    case Acts.get_act_for_user(user_id, document_id) do
      nil -> {:error, :document_not_found}
      act -> {:ok, act}
    end
  end

  defp do_get_public(:invoice, document_id) do
    Invoice
    |> where([i], i.id == ^document_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :document_not_found}

      invoice ->
        {:ok,
         Repo.preload(invoice, [
           :items,
           :bank_snapshot,
           :company,
           :kbe_code,
           :knp_code,
           bank_account: [:bank, :kbe_code, :knp_code],
           contract: [:buyer]
         ])}
    end
  end

  defp do_get_public(:contract, document_id) do
    Contract
    |> where([c], c.id == ^document_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :document_not_found}

      contract ->
        {:ok,
         Repo.preload(contract, [
           :company,
           :bank_account,
           :contract_items,
           buyer: [bank_accounts: :bank],
           bank_account: [:bank, :kbe_code, :knp_code]
         ])}
    end
  end

  defp do_get_public(:act, document_id) do
    Act
    |> where([a], a.id == ^document_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :document_not_found}
      act -> {:ok, Repo.preload(act, [:items, :company, :buyer, :contract])}
    end
  end
end
