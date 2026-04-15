defmodule EdocApi.ActsTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Acts
  alias EdocApi.ActStatus
  alias EdocApi.Buyers
  alias EdocApi.Monetization
  alias EdocApi.Repo

  describe "create_act_for_user/3" do
    test "creates draft act with items for valid buyer" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      attrs = %{
        "issue_date" => Date.utc_today(),
        "buyer_id" => buyer.id,
        "buyer_address" => "Buyer Address",
        "items" => [
          %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
        ]
      }

      assert {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)
      assert act.status == "draft"
      assert length(act.items) == 1
      assert Enum.at(act.items, 0).name == "Services"
    end

    test "blocks creating act when the trial document limit is exhausted" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      for _ <- 1..10 do
        assert {:ok, _quota} =
                 Monetization.consume_document_quota(
                   company.id,
                   "invoice",
                   Ecto.UUID.generate(),
                   "invoice_issued"
                 )
      end

      attrs = %{
        "issue_date" => Date.utc_today(),
        "buyer_id" => buyer.id,
        "buyer_address" => "Buyer Address",
        "items" => [
          %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
        ]
      }

      assert {:error, :business_rule, %{rule: :quota_exceeded, details: %{used: 10, limit: 10}}} =
               Acts.create_act_for_user(user.id, company.id, attrs)
    end
  end

  describe "next_act_number!/1" do
    test "uses a database aggregate and ignores non-numeric legacy act numbers" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      legacy_act = create_act!(user, company, buyer, ActStatus.draft())

      legacy_act
      |> Ecto.Changeset.change(number: "LEGACY-ACT")
      |> Repo.update!()

      numeric_act = create_act!(user, company, buyer, ActStatus.draft())

      numeric_act
      |> Ecto.Changeset.change(number: "00000000009")
      |> Repo.update!()

      query =
        capture_repo_query(fn ->
          assert Acts.next_act_number!(company.id) == "00000000010"
        end)

      assert String.contains?(String.downcase(query), "max(")
      assert String.contains?(String.downcase(query), "cast(")
      refute query =~ ~s(SELECT a0."number")
    end
  end

  describe "delete_act_for_user/2" do
    test "returns business rule error for non-draft acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      attrs = %{
        "issue_date" => Date.utc_today(),
        "buyer_id" => buyer.id,
        "buyer_address" => "Buyer Address",
        "items" => [
          %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
        ]
      }

      assert {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)

      act
      |> Ecto.Changeset.change(status: "issued")
      |> Repo.update!()

      assert {:error, :business_rule, %{rule: :cannot_delete_non_draft_act}} =
               Acts.delete_act_for_user(user.id, act.id)
    end
  end

  describe "sign_act_for_user/2" do
    test "marks an issued act as signed" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.issued())

      assert {:ok, signed} = Acts.sign_act_for_user(user.id, act.id)
      assert signed.status == ActStatus.signed()
    end

    test "returns business rule error for draft acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.draft())

      assert {:error, :business_rule, %{rule: :act_not_issued}} =
               Acts.sign_act_for_user(user.id, act.id)
    end

    test "returns business rule error for already signed acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.signed())

      assert {:error, :business_rule, %{rule: :act_already_signed}} =
               Acts.sign_act_for_user(user.id, act.id)
    end
  end

  describe "issue_act_for_user/2" do
    test "marks a draft act as issued" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.draft())

      assert {:ok, issued} = Acts.issue_act_for_user(user.id, act.id)
      assert issued.status == ActStatus.issued()
    end

    test "returns business rule error for non-draft acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.issued())

      assert {:error, :business_rule, %{rule: :act_not_editable}} =
               Acts.issue_act_for_user(user.id, act.id)
    end

    test "returns business rule error when monthly document quota is exceeded" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      {:ok, _sub} =
        EdocApi.Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "starter",
          "included_document_limit" => 1,
          "included_seat_limit" => 2
        })

      act_1 = create_act!(user, company, buyer, ActStatus.draft())
      act_2 = create_act!(user, company, buyer, ActStatus.draft())

      assert {:ok, issued} = Acts.issue_act_for_user(user.id, act_1.id)
      assert issued.status == ActStatus.issued()

      assert {:error, :business_rule, %{rule: :quota_exceeded, details: %{used: 1, limit: 1}}} =
               Acts.issue_act_for_user(user.id, act_2.id)
    end
  end

  describe "contract source eligibility" do
    test "returns only signed contracts without any acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      eligible_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-CON-ELIGIBLE",
          "buyer_id" => buyer.id
        })

      used_draft_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-CON-DRAFT",
          "buyer_id" => buyer.id
        })

      used_issued_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-CON-ISSUED",
          "buyer_id" => buyer.id
        })

      used_signed_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-CON-SIGNED",
          "buyer_id" => buyer.id
        })

      issued_only_contract =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "ACT-CON-ISSUED-ONLY",
          "buyer_id" => buyer.id
        })

      _draft_act =
        create_contract_act!(user, company, buyer, used_draft_contract.id, ActStatus.draft())

      _issued_act =
        create_contract_act!(user, company, buyer, used_issued_contract.id, ActStatus.issued())

      _signed_act =
        create_contract_act!(user, company, buyer, used_signed_contract.id, ActStatus.signed())

      contracts = Acts.list_signed_contracts_for_user(user.id)

      assert Enum.map(contracts, & &1.id) == [eligible_contract.id]

      assert {:ok, _contract} = Acts.get_signed_contract_for_user(user.id, eligible_contract.id)

      assert {:error, :not_found} =
               Acts.get_signed_contract_for_user(user.id, used_draft_contract.id)

      assert {:error, :not_found} =
               Acts.get_signed_contract_for_user(user.id, used_issued_contract.id)

      assert {:error, :not_found} =
               Acts.get_signed_contract_for_user(user.id, used_signed_contract.id)

      assert {:error, :not_found} =
               Acts.get_signed_contract_for_user(user.id, issued_only_contract.id)
    end
  end

  defp create_buyer!(company) do
    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    buyer
  end

  defp create_act!(user, company, buyer, status) do
    attrs = %{
      "issue_date" => Date.utc_today(),
      "buyer_id" => buyer.id,
      "buyer_address" => "Buyer Address",
      "items" => [
        %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
      ]
    }

    {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)

    act
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  defp create_contract_act!(user, company, buyer, contract_id, status) do
    attrs = %{
      "issue_date" => Date.utc_today(),
      "actual_date" => Date.utc_today(),
      "buyer_id" => buyer.id,
      "buyer_address" => "Buyer Address",
      "contract_id" => contract_id,
      "items" => [
        %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
      ]
    }

    {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)

    act
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  defp capture_repo_query(fun) when is_function(fun, 0) do
    test_pid = self()
    handler_id = {__MODULE__, :repo_query, System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      [:edoc_api, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        send(test_pid, {:repo_query, metadata.query})
      end,
      nil
    )

    try do
      fun.()

      receive do
        {:repo_query, query} -> query
      after
        500 -> flunk("expected next_act_number!/1 to execute a repo query")
      end
    after
      :telemetry.detach(handler_id)
    end
  end
end
