defmodule EdocApi.RepoHelpers do
  @moduledoc """
  Helpers for working with Ecto.Repo operations.

  Provides utilities for consistent transaction handling and error management.
  """

  alias EdocApi.Repo

  @doc """
  Runs a function in a transaction with automatic error unwrapping.

  If the function returns {:error, term}, it will automatically rollback.
  The returned value will be unwrapped from the transaction wrapper.

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
        other -> other
      end
    end)
  end

  @doc """
  Aborts a transaction with the given reason.

  This is a convenience wrapper around Repo.rollback that returns
  the reason directly instead of wrapping it.

  ## Examples

      transaction(fn ->
        case validate_something() do
          :ok -> {:ok, result}
          :error -> abort(:validation_failed)
        end
      end)
  """
  def abort(reason) do
    Repo.rollback(reason)
  end

  @doc """
  Inserts a changeset and returns {:ok, record} or aborts the transaction.

  Use this inside transaction/1 for cleaner error handling.

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
      {:error, changeset} -> abort(changeset)
    end
  end

  @doc """
  Updates a changeset and returns {:ok, record} or aborts the transaction.

  Use this inside transaction/1 for cleaner error handling.
  """
  def update_or_abort(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> abort(changeset)
    end
  end

  @doc """
  Checks a condition and aborts the transaction with the given reason if false.

  ## Examples

      transaction(fn ->
        check_or_abort(items != [], :items_required)
        check_or_abort(user.active?, :user_inactive)
        {:ok, result}
      end)
  """
  def check_or_abort(condition, reason) do
    unless condition do
      abort(reason)
    end
  end
end
