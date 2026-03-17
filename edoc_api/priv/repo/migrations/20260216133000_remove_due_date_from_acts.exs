defmodule EdocApi.Repo.Migrations.RemoveDueDateFromActs do
  use Ecto.Migration

  def change do
    alter table(:acts) do
      remove(:due_date)
    end
  end
end
