defmodule EdocApi.Repo.Migrations.NormalizeAndRestrictLegalForms do
  use Ecto.Migration

  def change do
    execute("""
    UPDATE companies
    SET legal_form = CASE
      WHEN legal_form = 'ТОО' THEN 'Товарищество с ограниченной ответственностью'
      WHEN legal_form = 'АО' THEN 'Акционерное общество'
      WHEN legal_form = 'ИП' THEN 'Индивидуальный предприниматель'
      WHEN legal_form IN ('ГКП', 'КХ') THEN 'Товарищество с ограниченной ответственностью'
      ELSE legal_form
    END
    WHERE legal_form IS NOT NULL;
    """)

    execute("""
    UPDATE buyers
    SET legal_form = CASE
      WHEN legal_form = 'ТОО' THEN 'Товарищество с ограниченной ответственностью'
      WHEN legal_form = 'АО' THEN 'Акционерное общество'
      WHEN legal_form = 'ИП' THEN 'Индивидуальный предприниматель'
      WHEN legal_form IN ('ГКП', 'КХ') THEN 'Товарищество с ограниченной ответственностью'
      ELSE legal_form
    END
    WHERE legal_form IS NOT NULL;
    """)

    execute("""
    UPDATE contracts
    SET buyer_legal_form = CASE
      WHEN buyer_legal_form = 'ТОО' THEN 'Товарищество с ограниченной ответственностью'
      WHEN buyer_legal_form = 'АО' THEN 'Акционерное общество'
      WHEN buyer_legal_form = 'ИП' THEN 'Индивидуальный предприниматель'
      WHEN buyer_legal_form IN ('ГКП', 'КХ') THEN 'Товарищество с ограниченной ответственностью'
      ELSE buyer_legal_form
    END
    WHERE buyer_legal_form IS NOT NULL;
    """)

    alter table(:buyers) do
      modify :legal_form, :string, default: "Товарищество с ограниченной ответственностью"
    end
  end
end
