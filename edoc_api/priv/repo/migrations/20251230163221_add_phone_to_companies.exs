defmodule EdocApi.Repo.Migrations.AddPhoneToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add(:phone, :string)
    end
  end
end
