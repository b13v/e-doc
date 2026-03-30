defmodule EdocApi.Repo.Migrations.AddContractIssuanceFields do
  use Ecto.Migration

  def change do
    alter table(:contracts) do
      add(:status, :string, null: false, default: "draft")
      add(:issued_at, :utc_datetime)
      add(:body_html, :text)
    end

    execute("""
    UPDATE contracts
    SET status = 'issued',
        issued_at = COALESCE(date::timestamp, inserted_at)
    """)
  end
end
