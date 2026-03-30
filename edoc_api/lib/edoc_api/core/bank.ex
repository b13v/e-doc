defmodule EdocApi.Core.Bank do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "banks" do
    field(:name, :string)
    field(:bic, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(bank, attrs) do
    bank
    |> cast(attrs, [:name, :bic])
    |> validate_required([:name, :bic])
    |> update_change(:name, &String.trim/1)
    |> update_change(:bic, &normalize_bic/1)
    |> validate_format(:bic, ~r/^[A-Z0-9]{6,11}$/, message: "BIC/SWIFT must be 6-11 chars A-Z0-9")
    |> unique_constraint(:bic)
  end

  defp normalize_bic(nil), do: nil
  defp normalize_bic(v), do: v |> String.trim() |> String.upcase()
end
