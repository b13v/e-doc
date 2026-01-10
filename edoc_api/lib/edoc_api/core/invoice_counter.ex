defmodule EdocApi.Core.InvoiceCounter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "invoice_counters" do
    field(:next_seq, :integer)
    belongs_to(:company, EdocApi.Core.Company, primary_key: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(counter, attrs) do
    counter
    |> cast(attrs, [:next_seq, :company_id])
    |> validate_required([:next_seq, :company_id])
  end
end
