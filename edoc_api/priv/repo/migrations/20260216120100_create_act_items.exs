defmodule EdocApi.Repo.Migrations.CreateActItems do
  use Ecto.Migration

  def change do
    create table(:act_items, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:act_id, references(:acts, type: :binary_id, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:report_info, :string)
      add(:code, :string, null: false)
      add(:qty, :decimal, null: false)
      add(:unit_price, :decimal, null: false)
      add(:amount, :decimal, null: false)
      add(:vat_amount, :decimal, null: false)
      add(:actual_date, :date)

      timestamps(type: :utc_datetime)
    end

    create(index(:act_items, [:act_id]))
  end
end
