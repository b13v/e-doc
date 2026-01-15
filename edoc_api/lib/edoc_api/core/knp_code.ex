defmodule EdocApi.Core.KnpCode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "knp_codes" do
    field(:code, :string)
    field(:description, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(knp, attrs) do
    knp
    |> cast(attrs, [:code, :description])
    |> validate_required([:code])
    |> update_change(:code, &normalize_code/1)
    |> validate_format(:code, ~r/^\d{3}$/, message: "KNP must be 3 digits")
    |> unique_constraint(:code)
  end

  defp normalize_code(nil), do: nil
  defp normalize_code(v), do: v |> String.trim()
end
