defmodule EdocApiWeb.PageController do
  use EdocApiWeb, :controller

  def home(conn, _params) do
    # Check if user is authenticated
    user = conn.assigns[:current_user]

    if user do
      # Redirect to invoices if authenticated
      redirect(conn, to: "/invoices")
    else
      # Show login page if not authenticated
      render(conn, :home, page_title: "Welcome to EdocAPI")
    end
  end
end
