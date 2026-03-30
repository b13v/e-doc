defmodule EdocApi.AccountsTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Accounts.User
  alias EdocApi.Repo

  describe "authenticate_user/2 lockout" do
    test "locks account after repeated failed attempts" do
      user = create_user!()

      for _ <- 1..4 do
        assert {:error, :business_rule, %{rule: :invalid_credentials}} =
                 Accounts.authenticate_user(user.email, "wrong-password")
      end

      assert {:error, :business_rule, %{rule: :account_locked}} =
               Accounts.authenticate_user(user.email, "wrong-password")

      reloaded_user = Repo.get!(User, user.id)
      assert reloaded_user.failed_login_attempts >= 5
      assert %DateTime{} = reloaded_user.locked_until
    end

    test "successful authentication resets failed counters" do
      user = create_user!()

      user
      |> Ecto.Changeset.change(failed_login_attempts: 3, locked_until: nil)
      |> Repo.update!()

      assert {:ok, authenticated_user} =
               Accounts.authenticate_user(user.email, "password123")

      assert authenticated_user.failed_login_attempts == 0
      assert authenticated_user.locked_until == nil
    end
  end

  describe "refresh tokens" do
    test "rotates refresh token and revokes prior token" do
      user = create_user!()

      assert {:ok, refresh_token} = Accounts.issue_refresh_token(user.id)

      assert {:ok, rotated_user, replacement_refresh_token} =
               Accounts.rotate_refresh_token(refresh_token)

      assert rotated_user.id == user.id
      assert replacement_refresh_token != refresh_token

      assert {:error, :invalid_refresh_token} =
               Accounts.rotate_refresh_token(refresh_token)
    end

    test "revoked refresh token can no longer be rotated" do
      user = create_user!()

      assert {:ok, refresh_token} = Accounts.issue_refresh_token(user.id)
      assert :ok = Accounts.revoke_refresh_token(refresh_token)

      assert {:error, :invalid_refresh_token} =
               Accounts.rotate_refresh_token(refresh_token)
    end
  end
end
