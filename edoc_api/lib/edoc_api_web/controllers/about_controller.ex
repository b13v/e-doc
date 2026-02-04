defmodule EdocApiWeb.AboutController do
  use EdocApiWeb, :controller

  def index(conn, _params) do
    render(conn, :index, page_title: "About")
  end
end
