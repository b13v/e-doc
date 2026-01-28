defmodule EdocApi.Core.ContractIssueTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Core
  alias EdocApi.ContractStatus

  import EdocApi.TestFixtures

  test "issues a contract and sets issued_at" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company)

    assert {:ok, issued} = Core.issue_contract_for_user(user.id, contract.id)
    assert issued.status == ContractStatus.issued()
    assert issued.issued_at
  end

  test "returns error when contract already issued" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company)

    assert {:ok, issued} = Core.issue_contract_for_user(user.id, contract.id)
    assert {:error, :contract_already_issued} = Core.issue_contract_for_user(user.id, issued.id)
  end
end
