defmodule EdocApi.Core.UnitOfMeasurement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "units_of_measurements" do
    field(:okei_code, :integer)
    field(:symbol, :string)
    field(:name, :string)
    field(:category, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [:okei_code, :symbol, :name, :category])
    |> validate_required([:okei_code, :symbol, :name])
    |> update_change(:symbol, &String.trim/1)
    |> update_change(:name, &String.trim/1)
    |> update_change(:category, fn
      nil -> nil
      value -> String.trim(value)
    end)
    |> unique_constraint(:symbol)
  end
end
