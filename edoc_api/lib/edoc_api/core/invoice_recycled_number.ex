defmodule EdocApi.Core.InvoiceRecycledNumber do
  @moduledoc """
  Schema for storing recycled invoice numbers.
  When an invoice is deleted, its number is stored here to be reused
  for future invoices before incrementing the counter.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_recycled_numbers" do
    field(:number, :string)
    field(:sequence_name, :string, default: "default")
    field(:deleted_at, :utc_datetime)

    belongs_to(:company, EdocApi.Core.Company)

    timestamps(type: :utc_datetime)
  end

  @required ~w(number company_id)a
  @optional ~w(sequence_name deleted_at)a

  def changeset(recycled_number, attrs) do
    recycled_number
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:number, is: 11)
    |> validate_format(:number, ~r/^\d{11}$/)
    |> unique_constraint([:company_id, :sequence_name, :number],
      name: :invoice_recycled_numbers_company_seq_num_index,
      message: "Number already in recycle pool"
    )
  end
end
