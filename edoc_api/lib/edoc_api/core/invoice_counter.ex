defmodule EdocApi.Core.InvoiceCounter do
  @moduledoc """
  Invoice counter schema for generating sequential invoice numbers.

  Each company has a single sequence for invoice numbering.
  All invoice numbers are generated as 11-digit format without prefixes.

  ## Examples

      %InvoiceCounter{company_id: "123", sequence_name: "default", next_seq: 100}

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
  Only supports the default sequence (no currency prefixes).
  """
  def valid_sequence_names do
    ~w(default)
  end
end
