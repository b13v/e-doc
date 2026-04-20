defmodule EdocApi.Billing.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plans" do
    field(:code, :string)
    field(:name, :string)
    field(:price_kzt, :integer, default: 0)
    field(:monthly_document_limit, :integer)
    field(:included_users, :integer)
    field(:is_active, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :code,
      :name,
      :price_kzt,
      :monthly_document_limit,
      :included_users,
      :is_active
    ])
    |> update_change(:code, &normalize_code/1)
    |> validate_required([:code, :name, :price_kzt, :monthly_document_limit, :included_users])
    |> validate_format(:code, ~r/^[a-z][a-z0-9_]*$/)
    |> validate_number(:price_kzt, greater_than_or_equal_to: 0)
    |> validate_number(:monthly_document_limit, greater_than: 0)
    |> validate_number(:included_users, greater_than: 0)
    |> unique_constraint(:code)
  end

  defp normalize_code(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_code(value), do: value
end
