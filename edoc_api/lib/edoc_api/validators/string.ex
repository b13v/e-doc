defmodule EdocApi.Validators.String do
  @moduledoc """
  Shared string normalization and validation helpers.

  Provides consistent string handling across all schemas, eliminating
  duplicated trimming and nil/empty string handling logic.

  ## Examples

      iex> String.normalize("  hello  ")
      "hello"

      iex> String.normalize("")
      nil

      iex> String.normalize(nil)
      nil

  """

  @doc """
  Normalizes a string value: trims whitespace and converts empty strings to nil.

  ## Examples

      iex> EdocApi.Validators.String.normalize(nil)
      nil

      iex> EdocApi.Validators.String.normalize("")
      nil

      iex> EdocApi.Validators.String.normalize("  hello  ")
      "hello"

      iex> EdocApi.Validators.String.normalize("   ")
      nil

  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  @doc """
  Trims whitespace from a string but keeps empty strings as empty strings.

  Use this when you need to distinguish between nil and "".

  ## Examples

      iex> EdocApi.Validators.String.trim(nil)
      nil

      iex> EdocApi.Validators.String.trim("")
      ""

      iex> EdocApi.Validators.String.trim("  hello  ")
      "hello"

  """
  @spec trim(String.t() | nil) :: String.t() | nil
  def trim(nil), do: nil
  def trim(value) when is_binary(value), do: String.trim(value)

  @doc """
  Converts a string to uppercase after trimming.

  ## Examples

      iex> EdocApi.Validators.String.upcase("  kzt  ")
      "KZT"

  """
  @spec upcase(String.t() | nil) :: String.t() | nil
  def upcase(nil), do: nil
  def upcase(value) when is_binary(value), do: value |> String.trim() |> String.upcase()

  @doc """
  Converts a string to lowercase after trimming.

  ## Examples

      iex> EdocApi.Validators.String.downcase("  HELLO  ")
      "hello"

  """
  @spec downcase(String.t() | nil) :: String.t() | nil
  def downcase(nil), do: nil
  def downcase(value) when is_binary(value), do: value |> String.trim() |> String.downcase()

  @doc """
  Capitalizes the first letter of a string after trimming.

  ## Examples

      iex> EdocApi.Validators.String.capitalize("  hello  ")
      "Hello"

  """
  @spec capitalize(String.t() | nil) :: String.t() | nil
  def capitalize(nil), do: nil
  def capitalize(value) when is_binary(value), do: value |> String.trim() |> String.capitalize()

  @doc """
  Checks if a string is blank (nil, empty, or only whitespace).

  ## Examples

      iex> EdocApi.Validators.String.blank?(nil)
      true

      iex> EdocApi.Validators.String.blank?("")
      true

      iex> EdocApi.Validators.String.blank?("   ")
      true

      iex> EdocApi.Validators.String.blank?("hello")
      false

  """
  @spec blank?(String.t() | nil) :: boolean()
  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""

  @doc """
  Ensures a value is present (not blank). Returns the normalized value or nil.

  ## Examples

      iex> EdocApi.Validators.String.presence(nil)
      nil

      iex> EdocApi.Validators.String.presence("  ")
      nil

      iex> EdocApi.Validators.String.presence("  hello  ")
      "hello"

  """
  @spec presence(String.t() | nil) :: String.t() | nil
  def presence(value), do: if(blank?(value), do: nil, else: normalize(value))

  @doc """
  Truncates a string to a maximum length, adding an ellipsis if truncated.

  ## Examples

      iex> EdocApi.Validators.String.truncate("hello world", 5)
      "he..."

      iex> EdocApi.Validators.String.truncate("hi", 5)
      "hi"

  """
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(nil, _length), do: ""

  def truncate(value, length) when is_binary(value) do
    if String.length(value) > length do
      String.slice(value, 0, max(length - 3, 0)) <> "..."
    else
      value
    end
  end

  @doc """
  Ecto changeset helper to normalize a string field.

  ## Usage in changesets

      changeset
      |> update_change(:name, &Validators.String.normalize/1)

  """
  @spec normalize_change(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def normalize_change(changeset, field) do
    Ecto.Changeset.update_change(changeset, field, &normalize/1)
  end
end
