defmodule EdocApi.Repo.Migrations.AddPaymentCodesToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add(:bank_id, references(:banks, type: :binary_id, on_delete: :nilify_all))
      add(:kbe_code_id, references(:kbe_codes, type: :binary_id, on_delete: :nilify_all))
      add(:knp_code_id, references(:knp_codes, type: :binary_id, on_delete: :nilify_all))
    end

    create(index(:companies, [:bank_id]))
    create(index(:companies, [:kbe_code_id]))
    create(index(:companies, [:knp_code_id]))
  end
end
