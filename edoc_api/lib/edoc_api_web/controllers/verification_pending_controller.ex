defmodule EdocApiWeb.VerificationPendingController do
  use EdocApiWeb, :controller

  alias EdocApi.EmailVerification

  def new(conn, %{"email" => email}) do
    render(conn, :new, email: email, page_title: "Verify Your Email")
  end

  def new(conn, _params) do
    conn
    |> put_flash(:error, "Пожалуйста, укажите свой адрес электронной почты.")
    |> redirect(to: "/signup")
  end

  def verify(conn, %{"token" => token}) do
    case EmailVerification.verify_token(token) do
      {:ok, _user_id} ->
        conn
        |> put_flash(
          :info,
          "Адрес электронной почты успешно подтвержден! Теперь вы можете войти в систему."
        )
        |> redirect(to: "/login")

      {:error, :already_verified} ->
        conn
        |> put_flash(
          :info,
          "Адрес электронной почты уже подтвержден. Пожалуйста, войдите в систему."
        )
        |> redirect(to: "/login")

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_flash(
          :error,
          "Недействительный или просроченный токен подтверждения. Пожалуйста, запросите новый."
        )
        |> redirect(to: "/verify-email-pending")
    end
  end

  def verify(conn, _params) do
    conn
    |> put_flash(:error, "Отсутствует токен подтверждения.")
    |> redirect(to: "/signup")
  end
end
