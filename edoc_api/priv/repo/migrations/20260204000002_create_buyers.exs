defmodule EdocApi.Repo.Migrations.CreateBuyers do
  use Ecto.Migration

  def change do
    create table(:buyers, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:name, :string, null: false)
      add(:legal_form, :string, default: "ТОО")
      add(:bin_iin, :string, null: false)
      add(:address, :string)
      add(:city, :string)
      add(:phone, :string)
      add(:email, :string)
      add(:director_name, :string)
      add(:director_title, :string)
      add(:basis, :string)

      timestamps(type: :utc_datetime)
    end

    create(index(:buyers, [:company_id]))
    create(unique_index(:buyers, [:company_id, :bin_iin], name: :buyers_company_bin_iin_index))
  end
end
