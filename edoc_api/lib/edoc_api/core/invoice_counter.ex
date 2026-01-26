defmodule EdocApi.Core.InvoiceCounter do
  @moduledoc """
  Invoice counter schema for generating sequential invoice numbers.

  Supports multiple sequences per company through the `sequence_name` field.
  This allows for separate numbering sequences by currency, department, etc.

  ## Examples

      # Default sequence
      %InvoiceCounter{company_id: "123", sequence_name: "default", next_seq: 100}

      # Currency-specific sequence
      %InvoiceCounter{company_id: "123", sequence_name: "USD", next_seq: 50}

  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "invoice_counters" do
    field(:next_seq, :integer)
    field(:sequence_name, :string, default: "default")
    belongs_to(:company, EdocApi.Core.Company, primary_key: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(counter, attrs) do
    counter
    |> cast(attrs, [:next_seq, :company_id, :sequence_name])
    |> validate_required([:next_seq, :company_id])
    |> validate_inclusion(:sequence_name, valid_sequence_names())
  end

  @doc """
  Returns the default sequence name.
  """
  def default_sequence, do: "default"

  @doc """
  Returns all valid sequence names.
  Can be extended to support dynamic sequences.
  """
  def valid_sequence_names do
    # Predefined sequences + option for custom sequences
    ~w(default) ++ currency_sequences()
  end

  @doc """
  Returns currency-based sequence names.
  """
  def currency_sequences do
    ~w(KZT USD EUR RUB)
  end

  @doc """
  Generates a sequence name for a specific currency.
  """
  def currency_sequence(currency_code) do
    String.upcase(currency_code || "default")
  end
end
