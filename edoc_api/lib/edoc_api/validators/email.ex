defmodule EdocApi.Validators.Email do
  @moduledoc """
  Shared email normalization and validation.
  Single source of truth for email handling across all schemas.
  """

  import Ecto.Changeset

  @email_regex ~r/^[^\s]+@[^\s]+\.[^\s]+$/

  @doc """
  Normalizes email: trims whitespace and converts to lowercase.

  ## Examples

      iex> EdocApi.Validators.Email.normalize("  User@Example.COM  ")
      "user@example.com"

      iex> EdocApi.Validators.Email.normalize(nil)
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end

  @doc """
  Validates email format on a changeset field.
  Only validates if the field has a value (email is optional in some contexts).
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      _ -> validate_format(changeset, field, @email_regex, message: "invalid email")
    end
  end

  @doc """
  Validates email format on a changeset field (strict version).
  Always validates the format, even if the field is nil.
  """
  @spec validate_required(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_required(changeset, field) do
    validate_format(changeset, field, @email_regex, message: "invalid email")
  end

  @doc """
  Returns the email format regex pattern.
  """
  def pattern, do: @email_regex
end
