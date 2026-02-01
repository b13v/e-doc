defmodule EdocApi.RepoHelpers do
  @moduledoc """
  Helpers for working with Ecto.Repo operations.

  Provides utilities for consistent transaction handling and error management
  with standardized error formats.
  """

  alias EdocApi.Repo
  alias EdocApi.Errors

  @doc """
  Runs a function in a transaction with automatic error unwrapping.

  If the function returns {:error, term}, it will automatically rollback.
  The returned value will be unwrapped from the transaction wrapper.
  Uses Errors.normalize/1 to standardize error formats.

  ## Examples

      transaction(fn ->
        with {:ok, user} <- create_user(attrs),
             {:ok, profile} <- create_profile(user.id, profile_attrs) do
          {:ok, {user, profile}}
        end
      end)

  This eliminates the need for manual Repo.rollback and unwrapping.
  """
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
        {:error, reason, details} -> Repo.rollback({reason, details})
        other -> other
      end
    end)
    |> Errors.normalize()
  end

  @doc """
  Aborts a transaction with the given reason.

  This is a convenience wrapper around Repo.rollback that returns
  the reason directly instead of wrapping it.
  Supports both simple atoms and standardized error tuples.

  ## Examples

      transaction(fn ->
        case validate_something() do
          :ok -> {:ok, result}
          :error -> abort(:validation_failed)
        end
      end)

      # With standardized error format
      abort({:not_found, %{resource: :invoice}})
      abort({:business_rule, %{rule: :already_issued}})
  """
  def abort(reason) do
    Repo.rollback(reason)
  end

  @doc """
  Inserts a changeset and returns {:ok, record} or aborts the transaction.

  Use this inside transaction/1 for cleaner error handling.
  Aborts with standardized validation error format.

  ## Examples

      transaction(fn ->
        with {:ok, invoice} <- insert_or_abort(invoice_changeset),
             {:ok, item} <- insert_or_abort(item_changeset) do
          {:ok, {invoice, item}}
        end
      end)
  """
  def insert_or_abort(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> abort({:validation, %{changeset: changeset}})
    end
  end

  @doc """
  Updates a changeset and returns {:ok, record} or aborts the transaction.

  Use this inside transaction/1 for cleaner error handling.
  Aborts with standardized validation error format.
  """
  def update_or_abort(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> abort({:validation, %{changeset: changeset}})
    end
  end

  @doc """
  Checks a condition and aborts the transaction with the given reason if false.

  Supports both simple atoms and standardized error tuples.

  ## Examples

      transaction(fn ->
        check_or_abort(items != [], :items_required)
        check_or_abort(user.active?, :user_inactive)
        check_or_abort(contract.present?, {:not_found, %{resource: :contract}})
        {:ok, result}
      end)
  """
  def check_or_abort(condition, reason) do
    unless condition do
      abort(reason)
    end
  end

  @doc """
  Fetches a record by ID and aborts if not found.

  Standardizes the pattern of fetching records within transactions.
  Eliminates the need for manual `unless` checks after Repo.get.

  ## Examples

      transaction(fn ->
        # Old pattern:
        # invoice = Repo.get(Invoice, id)
        # unless invoice do
        #   RepoHelpers.abort({:not_found, %{resource: :invoice}})
        # end

        # New pattern:
        invoice = fetch_or_abort(Invoice, id, :invoice)
        {:ok, invoice}
      end)
  """
  def fetch_or_abort(queryable, id, resource_name) when is_atom(resource_name) do
    case Repo.get(queryable, id) do
      nil -> abort({:not_found, %{resource: resource_name}})
      record -> record
    end
  end

  @doc """
  Fetches a record by query and aborts if not found.

  ## Examples

      transaction(fn ->
        invoice = fetch_or_abort(
          from(i in Invoice, where: i.user_id == ^user_id and i.id == ^invoice_id),
          :invoice
        )
        {:ok, invoice}
      end)
  """
  def fetch_or_abort(query, resource_name) do
    case Repo.one(query) do
      nil -> abort({:not_found, %{resource: resource_name}})
      record -> record
    end
  end
end
