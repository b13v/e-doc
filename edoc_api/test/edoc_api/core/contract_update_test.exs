defmodule EdocApi.Core.ContractUpdateTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Core
  alias EdocApi.Core.Contract
  alias EdocApi.Core.ContractItem
  alias EdocApi.Repo

  test "replaces contract items when update succeeds" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company)
    old_item = create_contract_item!(contract, %{"name" => "Old item"})

    items_attrs = [
      %{"name" => "New item", "qty" => "2", "unit_price" => "50.00"}
    ]

    assert {:ok, updated_contract} =
             Core.update_contract_for_user(
               user.id,
               contract.id,
               %{"city" => "Astana"},
               items_attrs
             )

    assert updated_contract.city == "Astana"
    assert length(updated_contract.contract_items) == 1
    assert Enum.at(updated_contract.contract_items, 0).name == "New item"
    refute Enum.at(updated_contract.contract_items, 0).id == old_item.id
  end

  test "rolls back contract update when any new item is invalid" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company)
    old_item = create_contract_item!(contract, %{"name" => "Existing item"})

    items_attrs = [
      %{"name" => "Broken item", "qty" => "0", "unit_price" => "10.00"}
    ]

    assert {:error, :validation, %{changeset: changeset}} =
             Core.update_contract_for_user(
               user.id,
               contract.id,
               %{"city" => "Shymkent"},
               items_attrs
             )

    assert errors_on(changeset)[:qty] == ["must be greater than 0"]

    reloaded_contract = Repo.get!(Contract, contract.id) |> Repo.preload(:contract_items)

    assert reloaded_contract.city == contract.city
    assert length(reloaded_contract.contract_items) == 1
    assert Enum.at(reloaded_contract.contract_items, 0).id == old_item.id
  end

  defp create_contract_item!(contract, attrs) do
    attrs =
      Map.merge(
        %{
          "name" => "Item",
          "qty" => "1",
          "unit_price" => "100.00"
        },
        attrs
      )

    %ContractItem{}
    |> ContractItem.changeset(attrs, contract.id)
    |> Repo.insert!()
  end
end
