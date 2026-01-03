defmodule EdocApi.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string)
      add(:legal_form, :string)
      add(:bin_iin, :string)
      add(:city, :string)
      add(:address, :string)
      add(:bank, :string)
      add(:iban, :string)
      add(:email, :string)
      add(:representative_name, :string)
      add(:representative_title, :string)
      add(:basis, :string)
      add(:user_id, references(:users, on_delete: :nothing, type: :binary_id))

      timestamps(type: :utc_datetime)
    end

    create(index(:companies, [:user_id]))
  end
end
