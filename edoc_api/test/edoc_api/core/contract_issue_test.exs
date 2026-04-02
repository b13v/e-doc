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

    assert {:error, :business_rule, %{rule: :contract_already_issued}} =
             Core.issue_contract_for_user(user.id, issued.id)
  end

  test "rejects issuing when monthly document quota is exceeded" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      EdocApi.Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_document_limit" => 1,
        "included_seat_limit" => 2
      })

    contract_1 = create_contract!(company)
    contract_2 = create_contract!(company)

    assert {:ok, issued} = Core.issue_contract_for_user(user.id, contract_1.id)
    assert issued.status == ContractStatus.issued()

    assert {:error, :business_rule, %{rule: :quota_exceeded, details: %{used: 1, limit: 1}}} =
             Core.issue_contract_for_user(user.id, contract_2.id)
  end

  test "marks an issued contract as signed and sets signed_at" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company, %{"status" => ContractStatus.issued()})

    assert {:ok, signed} = Core.sign_contract_for_user(user.id, contract.id)
    assert signed.status == ContractStatus.signed()
    assert signed.signed_at
  end

  test "returns error when signing a draft contract" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company)

    assert {:error, :business_rule, %{rule: :contract_not_issued}} =
             Core.sign_contract_for_user(user.id, contract.id)
  end

  test "returns error when contract already signed" do
    user = create_user!()
    company = create_company!(user)
    contract = create_contract!(company, %{"status" => ContractStatus.issued()})

    assert {:ok, signed} = Core.sign_contract_for_user(user.id, contract.id)

    assert {:error, :business_rule, %{rule: :contract_already_signed}} =
             Core.sign_contract_for_user(user.id, signed.id)
  end
end
