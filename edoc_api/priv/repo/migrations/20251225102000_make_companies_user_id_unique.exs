defmodule EdocApi.Repo.Migrations.MakeCompaniesUserIdUnique do
  use Ecto.Migration

  def up do
    # 1) удаляем существующий НЕуникальный индекс (если он есть)
    drop_if_exists(index(:companies, [:user_id], name: :companies_user_id_index))

    # 2) создаём уникальный индекс (можно оставить то же имя)
    create(unique_index(:companies, [:user_id], name: :companies_user_id_index))
  end

  def down do
    # откат: удаляем уникальный и создаём обычный
    drop_if_exists(index(:companies, [:user_id], name: :companies_user_id_index))
    create(index(:companies, [:user_id], name: :companies_user_id_index))
  end
end
