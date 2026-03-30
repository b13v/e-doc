defmodule EdocApi.Core.InvoiceBankSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Validators.Iban

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_bank_snapshots" do
    field(:bank_name, :string)
    field(:bic, :string)
    field(:iban, :string)
    field(:kbe, :string)
    field(:knp, :string)

    belongs_to(:invoice, EdocApi.Core.Invoice)

    timestamps(type: :utc_datetime)
  end

  @required ~w(invoice_id bank_name bic iban kbe knp)a

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> unique_constraint(:invoice_id, name: :invoice_bank_snapshots_invoice_id_index)
    |> Iban.validate(:iban)
  end
end
