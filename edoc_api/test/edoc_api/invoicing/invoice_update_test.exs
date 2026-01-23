defmodule EdocApi.Invoicing.InvoiceUpdateTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Invoicing
  import EdocApi.TestFixtures

  describe "update_invoice_for_user/3" do
    test "updates draft invoice successfully" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      updated_attrs = %{
        "service_name" => "Updated Service",
        "buyer_name" => "Updated Buyer",
        "vat_rate" => 16,
        "items" => [
          %{"name" => "Updated Item", "qty" => 2, "unit_price" => "200.00"}
        ]
      }

      assert {:ok, updated_invoice} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert updated_invoice.service_name == "Updated Service"
      assert updated_invoice.buyer_name == "Updated Buyer"
      assert updated_invoice.vat_rate == 16
      assert length(updated_invoice.items) == 1
      assert hd(updated_invoice.items).name == "Updated Item"
      assert hd(updated_invoice.items).qty == 2
    end

    test "replaces all items when items are provided" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      # Invoice starts with 1 item
      assert length(invoice.items) == 1

      # Update with 3 new items
      updated_attrs = %{
        "items" => [
          %{"name" => "Item 1", "qty" => 1, "unit_price" => "100.00"},
          %{"name" => "Item 2", "qty" => 2, "unit_price" => "50.00"},
          %{"name" => "Item 3", "qty" => 3, "unit_price" => "33.33"}
        ]
      }

      assert {:ok, updated_invoice} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert length(updated_invoice.items) == 3

      assert Enum.all?(updated_invoice.items, fn item ->
               Enum.member?(["Item 1", "Item 2", "Item 3"], item.name)
             end)
    end

    test "rejects update for issued invoice" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      {:ok, issued_invoice} =
        Invoicing.issue_invoice_for_user(user.id, invoice.id)

      updated_attrs = %{"service_name" => "Should not update"}

      assert {:error, :invoice_already_issued} =
               Invoicing.update_invoice_for_user(user.id, issued_invoice.id, updated_attrs)
    end

    test "rejects contract from another company on update" do
      user = create_user!()
      company = create_company!(user)
      other_user = create_user!()
      other_company = create_company!(other_user)
      other_contract = create_contract!(other_company)

      invoice = create_invoice_with_items!(user, company)

      updated_attrs = %{"contract_id" => other_contract.id}

      assert {:error, %Ecto.Changeset{} = cs} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert {"does not belong to company", _} = Keyword.get(cs.errors, :contract_id)
    end

    test "accepts valid contract from same company on update" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company)
      invoice = create_invoice_with_items!(user, company)

      updated_attrs = %{"contract_id" => contract.id}

      assert {:ok, updated_invoice} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert updated_invoice.contract_id == contract.id
    end

    test "rejects invalid contract_id (non-existent) on update" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      fake_contract_id = Ecto.UUID.generate()
      updated_attrs = %{"contract_id" => fake_contract_id}

      assert {:error, %Ecto.Changeset{} = cs} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert {"does not belong to company", _} = Keyword.get(cs.errors, :contract_id)
    end

    test "accepts nil contract_id on update (removes contract)" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company)
      invoice = create_invoice_with_items!(user, company, %{"contract_id" => contract.id})

      assert invoice.contract_id == contract.id

      updated_attrs = %{"contract_id" => nil}

      assert {:ok, updated_invoice} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert is_nil(updated_invoice.contract_id)
    end

    test "returns error for non-existent invoice" do
      user = create_user!()
      _company = create_company!(user)

      fake_invoice_id = Ecto.UUID.generate()
      updated_attrs = %{"service_name" => "Updated"}

      assert {:error, :invoice_not_found} =
               Invoicing.update_invoice_for_user(user.id, fake_invoice_id, updated_attrs)
    end

    test "keeps existing items when items not provided" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      original_items = Enum.map(invoice.items, &{&1.name, &1.qty})

      updated_attrs = %{"service_name" => "Updated Service"}

      assert {:ok, updated_invoice} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert length(updated_invoice.items) == length(invoice.items)

      Enum.each(updated_invoice.items, fn item ->
        assert Enum.member?(original_items, {item.name, item.qty})
      end)
    end

    test "updates all editable fields" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      updated_attrs = %{
        "service_name" => "New Service",
        "issue_date" => Date.utc_today() |> Date.add(1),
        "due_date" => Date.utc_today() |> Date.add(7),
        "currency" => "USD",
        "buyer_name" => "New Buyer",
        "buyer_bin_iin" => "999999999999",
        "buyer_address" => "New Address",
        "vat_rate" => 16
      }

      assert {:ok, updated_invoice} =
               Invoicing.update_invoice_for_user(user.id, invoice.id, updated_attrs)

      assert updated_invoice.service_name == "New Service"
      assert updated_invoice.currency == "USD"
      assert updated_invoice.buyer_name == "New Buyer"
      assert updated_invoice.buyer_bin_iin == "999999999999"
      assert updated_invoice.buyer_address == "New Address"
      assert updated_invoice.vat_rate == 16
    end
  end
end
