defmodule EdocApi.PasswordResetTest do
  use EdocApi.DataCase, async: false

  import ExUnit.CaptureLog
  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Auth.RefreshToken
  alias EdocApi.PasswordReset
  alias EdocApi.PasswordResetToken
  alias EdocApi.Repo

  defmodule FailingMailerAdapter do
    use Swoosh.Adapter

    def deliver(_email, _config), do: {:error, :simulated_delivery_failure}
    def deliver_many(_emails, _config), do: {:error, :simulated_delivery_failure}
  end

  setup do
    original_mailer_config = Application.get_env(:edoc_api, EdocApi.Mailer, [])
    Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

    case Swoosh.Adapters.Local.Storage.Memory.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Swoosh.Adapters.Local.Storage.Memory.delete_all()

    on_exit(fn ->
      Swoosh.Adapters.Local.Storage.Memory.delete_all()
      Application.put_env(:edoc_api, EdocApi.Mailer, original_mailer_config)
    end)

    :ok
  end

  test "password_reset_tokens table has required indexes" do
    indexes =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'password_reset_tokens'
        """,
        []
      ).rows

    names = Enum.map(indexes, &Enum.at(&1, 0))
    defs = Enum.map(indexes, &Enum.at(&1, 1))

    assert Enum.any?(names, &String.contains?(&1, "token_hash"))
    assert Enum.any?(names, &String.contains?(&1, "user_id"))
    assert Enum.any?(names, &String.contains?(&1, "expires_at"))
    assert Enum.any?(defs, &String.contains?(&1, "WHERE (used_at IS NULL)"))
  end

  test "request_reset/3 returns accepted for known and unknown email and sends only for known user" do
    user = create_user!()

    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")
    assert {:ok, :accepted} = PasswordReset.request_reset("missing@example.com", "ru")

    deliveries = Swoosh.Adapters.Local.Storage.Memory.all()
    assert Enum.count(deliveries, &email_for?(&1, user.email)) == 1
  end

  test "request_reset/3 normalizes email before lookup" do
    user = create_user!()

    assert {:ok, :accepted} =
             PasswordReset.request_reset("  #{String.upcase(user.email)}  ", "ru")

    deliveries = Swoosh.Adapters.Local.Storage.Memory.all()
    assert Enum.count(deliveries, &email_for?(&1, user.email)) == 1
  end

  test "request_reset/3 accepts mailer failures and logs a warning with context" do
    user = create_user!()
    original_mailer_config = Application.get_env(:edoc_api, EdocApi.Mailer, [])
    Application.put_env(:edoc_api, EdocApi.Mailer, adapter: FailingMailerAdapter)

    try do
      log =
        capture_log(fn ->
          assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")
        end)

      assert log =~ "Password reset email delivery failed"
      assert log =~ user.email
    after
      Application.put_env(:edoc_api, EdocApi.Mailer, original_mailer_config)
    end
  end

  test "request_reset/3 stores hashed token only and with 24h expiry" do
    user = create_user!()

    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")

    token_record = Repo.one!(from(t in PasswordResetToken, where: t.user_id == ^user.id))
    refute String.contains?(token_record.token_hash, "/password/reset?token=")

    diff_seconds = DateTime.diff(token_record.expires_at, DateTime.utc_now(), :second)
    assert diff_seconds > 23 * 3600
    assert diff_seconds <= 24 * 3600 + 30
  end

  test "request_reset/3 invalidates previous active token on new request" do
    user = create_user!()

    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")

    first_token =
      Repo.one!(
        from(t in PasswordResetToken,
          where: t.user_id == ^user.id,
          order_by: [asc: t.inserted_at]
        )
      )

    assert is_nil(first_token.used_at)

    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")

    first_token = Repo.get!(PasswordResetToken, first_token.id)
    refute is_nil(first_token.used_at)
  end

  test "verify_token/1 returns user_id and token_hash for valid token" do
    user = create_user!()
    user_id = user.id
    token = request_reset_and_extract_token!(user.email)

    assert {:ok, %{user_id: ^user_id, token_hash: token_hash}} = PasswordReset.verify_token(token)
    assert is_binary(token_hash)
    assert String.length(token_hash) >= 32
  end

  test "reset_password/3 returns validation_failed changeset for invalid password" do
    user = create_user!()
    token = request_reset_and_extract_token!(user.email)

    assert {:error, :validation_failed, %Ecto.Changeset{}} =
             PasswordReset.reset_password(token, "short", "short")
  end

  test "reset_password/3 consumes token once and revokes all refresh tokens" do
    user = create_user!()
    token = request_reset_and_extract_token!(user.email)
    {:ok, refresh_token_1} = Accounts.issue_refresh_token(user.id)
    {:ok, _refresh_token_2} = Accounts.issue_refresh_token(user.id)

    assert {:ok, :password_reset} =
             PasswordReset.reset_password(token, "new-password-123", "new-password-123")

    assert {:error, :invalid_or_expired} =
             PasswordReset.reset_password(token, "other-password-123", "other-password-123")

    refresh_rows = Repo.all(from(rt in RefreshToken, where: rt.user_id == ^user.id))
    assert Enum.all?(refresh_rows, &(not is_nil(&1.revoked_at)))

    assert {:error, :invalid_refresh_token} = Accounts.rotate_refresh_token(refresh_token_1)
  end

  test "concurrent reset uses single-winner token consumption" do
    user = create_user!()
    token = request_reset_and_extract_token!(user.email)

    task_a =
      Task.async(fn ->
        PasswordReset.reset_password(token, "parallel-pass-123", "parallel-pass-123")
      end)

    task_b =
      Task.async(fn ->
        PasswordReset.reset_password(token, "parallel-pass-123", "parallel-pass-123")
      end)

    results = [Task.await(task_a, 5_000), Task.await(task_b, 5_000)]

    assert Enum.count(results, &match?({:ok, :password_reset}, &1)) == 1
    assert Enum.count(results, &match?({:error, :invalid_or_expired}, &1)) == 1
  end

  test "request throttling for known users keeps accepted response" do
    user = create_user!()

    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")
    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")
    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")
    assert {:ok, :accepted} = PasswordReset.request_reset(user.email, "ru")
  end

  defp request_reset_and_extract_token!(email) do
    assert {:ok, :accepted} = PasswordReset.request_reset(email, "ru")

    sent =
      Swoosh.Adapters.Local.Storage.Memory.all()
      |> Enum.find(&email_for?(&1, email))

    [_, token] = Regex.run(~r/password\/reset\?token=([^\s<]+)/, sent.text_body)
    URI.decode(token)
  end

  defp email_for?(email, recipient) do
    Enum.any?(email.to, fn {_name, addr} -> addr == recipient end) and
      String.contains?(email.text_body || "", "/password/reset?token=")
  end
end
