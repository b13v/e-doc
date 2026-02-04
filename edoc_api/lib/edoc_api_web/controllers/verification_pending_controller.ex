defmodule EdocApiWeb.VerificationPendingController do
  use EdocApiWeb, :controller

  def new(conn, %{"email" => email}) do
    render(conn, :new, email: email, page_title: "Verify Your Email")
  end

  def new(conn, _params) do
    conn
    |> put_flash(:error, "Please provide your email address")
    |> redirect(to: "/signup")
  end
end
