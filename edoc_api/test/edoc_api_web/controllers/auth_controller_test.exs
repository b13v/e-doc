defmodule EdocApiWeb.AuthControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApiWeb.Plugs.RateLimit

  setup do
    RateLimit.reset!()
    :ok
  end

  describe "login rate limiting" do
    test "returns 429 after credential limit is exceeded" do
      for _ <- 1..5 do
        conn =
          build_conn()
          |> post("/v1/auth/login", %{"email" => "missing@example.com", "password" => "bad-pass"})

        assert conn.status == 401
      end

      conn =
        build_conn()
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
  end
end
