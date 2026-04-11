defmodule EdocApiWeb.PasswordResetControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.PasswordReset

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

  test "GET /password/forgot renders forgot password form", %{conn: conn} do
    conn = get(conn, "/password/forgot")
    body = html_response(conn, 200)

    assert body =~ ~s(action="/password/forgot")
    assert body =~ "Email"
  end

  test "POST /password/forgot returns same neutral response for known and unknown email", %{
    conn: conn
  } do
    user = create_user!()

    known_conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> post("/password/forgot", %{"email" => user.email})

    unknown_conn =
      conn
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, true)
      |> post("/password/forgot", %{"email" => "missing@example.com"})

    assert redirected_to(known_conn) == "/password/forgot"
    assert redirected_to(unknown_conn) == "/password/forgot"

    assert Phoenix.Flash.get(known_conn.assigns.flash, :info) ==
             Phoenix.Flash.get(unknown_conn.assigns.flash, :info)
  end

  test "GET /password/reset with invalid token shows recovery CTA", %{conn: conn} do
    conn = get(conn, "/password/reset?token=invalid-token")
    body = html_response(conn, 200)

    assert body =~ "/password/forgot"
  end

  test "POST /password/reset with valid token redirects to login", %{conn: conn} do
    user = create_user!()
    token = request_reset_and_extract_token!(user.email)

    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> post("/password/reset", %{
        "token" => token,
        "password" => "new-password-123",
        "password_confirmation" => "new-password-123"
      })

    assert redirected_to(conn) == "/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :info)
  end

  test "POST /password/reset with mismatched confirmation renders localized validation error", %{
    conn: conn
  } do
    user = create_user!()
    token = request_reset_and_extract_token!(user.email)

    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> post("/password/reset", %{
        "token" => token,
        "password" => "new-password-123",
        "password_confirmation" => "different-password"
      })

    body = html_response(conn, 200)
    assert body =~ "пароль"
  end

  defp request_reset_and_extract_token!(email) do
    assert {:ok, :accepted} = PasswordReset.request_reset(email, "ru")

    sent =
      Swoosh.Adapters.Local.Storage.Memory.all()
      |> Enum.find(fn email_msg ->
        Enum.any?(email_msg.to, fn {_name, addr} -> addr == email end)
      end)

    [_, token] = Regex.run(~r/password\/reset\?token=([^\s<]+)/, sent.text_body)
    URI.decode(token)
  end
end
