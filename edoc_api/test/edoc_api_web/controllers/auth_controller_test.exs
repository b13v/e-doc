defmodule EdocApiWeb.AuthControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import Ecto.Query
  import EdocApi.TestFixtures
  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.EmailVerification
  alias EdocApi.EmailVerificationToken
  alias EdocApi.Monetization
  alias EdocApi.Repo
  alias EdocApiWeb.Plugs.RateLimit

  setup do
    RateLimit.reset!()
    Application.put_env(:edoc_api, RateLimit, trusted_proxies: [{127, 0, 0, 1}])

    original_mailer_config = Application.get_env(:edoc_api, EdocApi.Mailer, [])
    Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

    case Swoosh.Adapters.Local.Storage.Memory.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Swoosh.Adapters.Local.Storage.Memory.delete_all()

    on_exit(fn ->
      Application.delete_env(:edoc_api, RateLimit)
      Swoosh.Adapters.Local.Storage.Memory.delete_all()
      Application.put_env(:edoc_api, EdocApi.Mailer, original_mailer_config)
    end)

    :ok
  end

  describe "login rate limiting" do
    test "returns 429 after credential limit is exceeded" do
      client_ip = "203.0.113.10"
      exhaust_auth_credentials_limit(client_ip)

      conn =
        auth_conn(client_ip)
        |> post("/v1/auth/login", %{"email" => "missing@example.com", "password" => "bad-pass"})

      assert conn.status == 429
      assert json_response(conn, 429)["error"] == "rate_limited"
      assert get_resp_header(conn, "retry-after") != []
    end

    test "successful login returns access and refresh tokens" do
      user = create_user!()
      Accounts.mark_email_verified!(user.id)

      conn =
        build_conn()
        |> post("/v1/auth/login", %{"email" => user.email, "password" => "password123"})

      assert conn.status == 200

      body = json_response(conn, 200)
      assert is_binary(body["access_token"])
      assert is_binary(body["refresh_token"])
      assert body["user"]["id"] == user.id
    end

    test "successful login activates invited memberships" do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      invited = create_user!(%{"email" => "invitee@example.com"})
      Accounts.mark_email_verified!(invited.id)

      assert {:ok, _membership} =
               Monetization.invite_member(company.id, %{
                 "email" => invited.email,
                 "role" => "member"
               })

      conn =
        build_conn()
        |> post("/v1/auth/login", %{"email" => invited.email, "password" => "password123"})

      assert conn.status == 200
      assert Companies.get_company_by_user_id(invited.id).id == company.id
    end

    test "login keeps invite in pending_seat when active seats are full" do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      {:ok, _basic} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "basic"
        })

      first_user = create_user!(%{"email" => "first-login-seat@example.com"})
      second_user = create_user!(%{"email" => "second-login-seat@example.com"})
      Accounts.mark_email_verified!(first_user.id)
      Accounts.mark_email_verified!(second_user.id)

      assert {:ok, _first_invite} =
               Monetization.invite_member(company.id, %{
                 "email" => first_user.email,
                 "role" => "member"
               })

      assert {:ok, _second_invite} =
               Monetization.invite_member(company.id, %{
                 "email" => second_user.email,
                 "role" => "member"
               })

      conn =
        build_conn()
        |> post("/v1/auth/login", %{"email" => first_user.email, "password" => "password123"})

      assert conn.status == 200
      assert Companies.get_company_by_user_id(first_user.id).id == company.id

      {:ok, _starter} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "starter"
        })

      conn =
        build_conn()
        |> post("/v1/auth/login", %{"email" => second_user.email, "password" => "password123"})

      assert conn.status == 200
      assert Companies.get_company_by_user_id(second_user.id) == nil

      pending =
        Monetization.list_memberships(company.id)
        |> Enum.find(&(&1.invite_email == second_user.email))

      assert pending.status == "pending_seat"
    end

    test "returns generic invalid credentials when account is locked" do
      user = create_user!()
      Accounts.mark_email_verified!(user.id)

      for _ <- 1..5 do
        conn =
          build_conn()
          |> post("/v1/auth/login", %{"email" => user.email, "password" => "wrong-pass"})

        assert conn.status == 401
        assert json_response(conn, 401)["error"] == "invalid_credentials"
        assert get_resp_header(conn, "retry-after") == []
      end
    end
  end

  describe "refresh token flow" do
    test "returns new access and refresh tokens for valid refresh token" do
      user = create_user!()
      Accounts.mark_email_verified!(user.id)
      {:ok, refresh_token} = Accounts.issue_refresh_token(user.id)

      conn =
        build_conn()
        |> post("/v1/auth/refresh", %{"refresh_token" => refresh_token})

      assert conn.status == 200
      body = json_response(conn, 200)
      assert is_binary(body["access_token"])
      assert is_binary(body["refresh_token"])
      assert body["refresh_token"] != refresh_token
    end

    test "rejects invalid refresh token" do
      conn =
        build_conn()
        |> post("/v1/auth/refresh", %{"refresh_token" => "invalid-token"})

      assert conn.status == 401
      assert json_response(conn, 401)["error"] == "invalid_refresh_token"
    end
  end

  describe "resend verification behavior" do
    test "sends one verification email for an existing unverified account" do
      user = create_user!()

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "en"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200
      assert json_response(conn, 200)["message"] ==
               "Verification email sent. Please check your inbox."

      assert verification_email_count(user.email) == 1
    end

    test "throttles an immediate second resend for an existing unverified account" do
      user = create_user!()

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "en"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200
      assert json_response(conn, 200)["message"] ==
               "Verification email sent. Please check your inbox."

      assert verification_email_count(user.email) == 1

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "en"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200
      assert json_response(conn, 200)["message"] ==
               "Please wait before requesting another verification email."

      assert verification_email_count(user.email) == 1
    end

    test "allows resend after 60 seconds when under hourly cap" do
      user = create_user!()

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "en"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200
      assert json_response(conn, 200)["status"] == "sent"

      {:ok, latest} = EmailVerification.get_latest_token(user.id)
      cooldown_passed_at = DateTime.add(DateTime.utc_now(), -61, :second) |> DateTime.truncate(:second)

      from(t in EmailVerificationToken, where: t.id == ^latest.id)
      |> Repo.update_all(set: [inserted_at: cooldown_passed_at])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "en"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200
      assert json_response(conn, 200)["status"] == "sent"
      assert verification_email_count(user.email) == 2
    end

    test "blocks fourth resend within one hour" do
      user = create_user!()

      for age_in_seconds <- [180, 150, 120] do
        conn =
          build_conn()
          |> Plug.Test.init_test_session(%{locale: "en"})
          |> post("/v1/auth/resend-verification", %{"email" => user.email})

        assert conn.status == 200
        assert json_response(conn, 200)["status"] == "sent"

        {:ok, latest} = EmailVerification.get_latest_token(user.id)
        backdated_at = DateTime.add(DateTime.utc_now(), -age_in_seconds, :second) |> DateTime.truncate(:second)

        from(t in EmailVerificationToken, where: t.id == ^latest.id)
        |> Repo.update_all(set: [inserted_at: backdated_at])
      end

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "en"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200
      assert json_response(conn, 200)["status"] == "rate_limited"
      assert verification_email_count(user.email) == 3
    end

    test "returns localized rate-limit message in russian locale" do
      user = create_user!()

      _conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "ru"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "ru"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200

      assert json_response(conn, 200)["message"] ==
               "Подождите немного перед повторной отправкой письма для подтверждения."
    end

    test "returns localized rate-limit message in kazakh locale" do
      user = create_user!()

      _conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "kk"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{locale: "kk"})
        |> post("/v1/auth/resend-verification", %{"email" => user.email})

      assert conn.status == 200

      assert json_response(conn, 200)["message"] ==
               "Растау хатын қайта сұрамас бұрын сәл күтіңіз."
    end

    test "returns generic response for unknown email and rate limits repeated requests" do
      conn =
        build_conn()
        |> post("/v1/auth/resend-verification", %{"email" => "unknown@example.com"})

      assert conn.status == 200
      assert json_response(conn, 200)["success"] == true

      for _ <- 1..4 do
        conn =
          build_conn()
          |> post("/v1/auth/resend-verification", %{"email" => "unknown@example.com"})

        assert conn.status == 200
      end

      conn =
        build_conn()
        |> post("/v1/auth/resend-verification", %{"email" => "unknown@example.com"})

      assert conn.status == 429
      assert json_response(conn, 429)["error"] == "rate_limited"
    end
  end

  describe "signup enumeration protection" do
    test "returns generic accepted response when email already exists" do
      existing_user = create_user!()

      conn =
        build_conn()
        |> post("/v1/auth/signup", %{
          "email" => existing_user.email,
          "password" => "another-password-123"
        })

      assert conn.status == 202

      body = json_response(conn, 202)
      assert body["message"] =~ "verification instructions"
      refute Map.has_key?(body, "error")
    end

    test "resends verification email for invited existing unverified account" do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)
      invited_email = "invited-api-#{System.unique_integer([:positive])}@example.com"
      _existing_unverified_user = create_user!(%{"email" => invited_email})

      assert {:ok, _membership} =
               Monetization.invite_member(company.id, %{
                 "email" => invited_email,
                 "role" => "member"
               })

      conn =
        build_conn()
        |> post("/v1/auth/signup", %{
          "email" => invited_email,
          "password" => "another-password-123"
        })

      assert conn.status == 202
      assert json_response(conn, 202)["message"] =~ "verification instructions"
      assert verification_email_count(invited_email) == 1
    end
  end

  defp exhaust_auth_credentials_limit(client_ip) do
    opts = RateLimit.init(limit: 5, window_seconds: 60, action: "auth_credentials", subject: :ip)

    for _ <- 1..5 do
      conn = auth_conn(client_ip) |> RateLimit.call(opts)
      assert conn.status in [nil, 200]
    end
  end

  defp auth_conn(client_ip) do
    build_conn()
    |> put_req_header("x-forwarded-for", client_ip)
  end

  defp verification_email_count(email) do
    Swoosh.Adapters.Local.Storage.Memory.all()
    |> Enum.count(&verification_email_for?(&1, email))
  end

  defp verification_email_for?(sent, email) do
    Enum.any?(sent.to, fn {_name, addr} -> addr == email end) and
      String.contains?(sent.subject, "Edocly") and
      String.contains?(sent.text_body, "/verify-email?token=")
  end
end
