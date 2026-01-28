defmodule EdocApi.Core.Contract do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.ContractStatus

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contracts" do
    field(:number, :string)
    field(:date, :date)
    field(:title, :string)
    field(:status, :string, default: ContractStatus.default())
    field(:issued_at, :utc_datetime)
    field(:body_html, :string)

    belongs_to(:company, EdocApi.Core.Company)
    has_many(:invoices, EdocApi.Core.Invoice)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(number date)a
  @optional_fields ~w(title status issued_at body_html)a

  @doc """
  company_id is NOT accepted from attrs.
  It must be passed explicitly from the authenticated user context.
  """
  def changeset(contract, attrs, company_id) do
    contract
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> maybe_put_default_status()
    |> sanitize_body_html()
    |> put_change(:company_id, company_id)
    |> validate_required(@required_fields ++ [:company_id])
    |> validate_inclusion(:status, ContractStatus.all())
    |> unique_constraint(:number, name: :contracts_company_id_number_index)
  end

  defp maybe_put_default_status(changeset) do
    case get_field(changeset, :status) do
      nil -> put_change(changeset, :status, ContractStatus.default())
      _status -> changeset
    end
  end

  defp sanitize_body_html(changeset) do
    case get_change(changeset, :body_html) do
      nil ->
        changeset

      body_html ->
        sanitized = HtmlSanitizeEx.basic_html(body_html)
        put_change(changeset, :body_html, sanitized)
    end
  end
end
