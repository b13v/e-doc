defmodule EdocApi.Core.Buyer do
  @moduledoc """
  Schema for buyer (counterparty) entities.
  Buyers are counterparties that the seller creates and can select in contracts and invoices.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Validators.{BinIin, Email, String}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "buyers" do
    field(:name, :string)
    field(:legal_form, :string, default: "ТОО")
    field(:bin_iin, :string)
    field(:address, :string)
    field(:city, :string)
    field(:phone, :string)
    field(:email, :string)
    field(:director_name, :string)
    field(:director_title, :string)
    field(:basis, :string)

    belongs_to(:company, EdocApi.Core.Company)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name bin_iin)a
  @optional_fields ~w(
    legal_form
    address
    city
    phone
    email
    director_name
    director_title
    basis
  )a

  @doc """
  Creates a changeset for a buyer.
  """
  def changeset(buyer, attrs, company_id) do
    buyer
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> put_change(:company_id, company_id)
    |> validate_required(@required_fields ++ [:company_id])
    |> normalize_fields()
    |> BinIin.validate(:bin_iin)
    |> Email.validate(:email)
    |> validate_length(:name, min: 2, max: 255)
    |> unique_constraint(:bin_iin, name: :buyers_company_bin_iin_index)
  end

  @doc """
  Creates a changeset for updating a buyer.
  """
  def update_changeset(buyer, attrs) do
    buyer
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> normalize_fields()
    |> BinIin.validate(:bin_iin)
    |> Email.validate(:email)
    |> validate_length(:name, min: 2, max: 255)
    |> unique_constraint(:bin_iin, name: :buyers_company_bin_iin_index)
  end

  defp normalize_fields(changeset) do
    changeset
    |> update_change(:bin_iin, &BinIin.normalize/1)
    |> update_change(:email, &Email.normalize/1)
    |> update_change(:city, &String.normalize/1)
    |> update_change(:address, &String.normalize/1)
    |> update_change(:name, &String.normalize/1)
    |> update_change(:director_name, &String.normalize/1)
    |> update_change(:director_title, &String.normalize/1)
    |> update_change(:basis, &String.normalize/1)
  end
end
