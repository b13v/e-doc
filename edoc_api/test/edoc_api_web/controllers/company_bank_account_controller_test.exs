defmodule EdocApiWeb.CompanyBankAccountControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Payments

  import EdocApi.TestFixtures

  setup %{conn: conn} do
    user = create_user!()
    company = create_company!(user)

    {:ok, conn: authenticate(conn, user), user: user, company: company}
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "set_default/2" do
    test "sets bank account as default and unsets others", %{
      conn: conn,
      user: user,
      company: company
    } do
      account1 = create_company_bank_account!(company, %{"label" => "Account 1"})
      account2 = create_company_bank_account!(company, %{"label" => "Account 2"})

      # Set first account as default
      conn = put(conn, "/v1/company/bank-accounts/#{account1.id}/set-default", %{})
      assert response(conn, 200)

      # Verify first is default
      accounts = Payments.list_company_bank_accounts_for_user(user.id)
      assert Enum.find(accounts, fn a -> a.id == account1.id end).is_default == true
      assert Enum.find(accounts, fn a -> a.id == account2.id end).is_default == false

      # Set second account as default
      conn =
        build_conn()
        |> authenticate(user)
        |> put("/v1/company/bank-accounts/#{account2.id}/set-default", %{})

      assert response(conn, 200)

      # Verify second is now default and first is not
      accounts = Payments.list_company_bank_accounts_for_user(user.id)
      assert Enum.find(accounts, fn a -> a.id == account1.id end).is_default == false
      assert Enum.find(accounts, fn a -> a.id == account2.id end).is_default == true
    end

    test "returns 404 for non-existent bank account", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn = put(conn, "/v1/company/bank-accounts/#{fake_id}/set-default", %{})
      assert response(conn, 404)
    end

    test "returns 404 for bank account from different company", %{conn: conn} do
      other_user = create_user!()
      other_company = create_company!(other_user)
      other_account = create_company_bank_account!(other_company, %{"label" => "Other Account"})

      conn = put(conn, "/v1/company/bank-accounts/#{other_account.id}/set-default", %{})
      assert response(conn, 404)
    end
  end
end
