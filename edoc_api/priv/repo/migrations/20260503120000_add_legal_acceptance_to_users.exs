defmodule EdocApi.Repo.Migrations.AddLegalAcceptanceToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:terms_accepted_at, :utc_datetime)
      add(:privacy_accepted_at, :utc_datetime)
      add(:legal_acceptance_version, :string)
    end
  end
end
