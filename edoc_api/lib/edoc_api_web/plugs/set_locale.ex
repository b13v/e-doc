defmodule EdocApiWeb.Plugs.SetLocale do
  @behaviour Plug

  import Plug.Conn

  alias Phoenix.Controller

  alias EdocApiWeb.Locale

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = resolve_locale(conn)

    Gettext.put_locale(EdocApiWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> assign(:current_path, Controller.current_path(conn))
  end

  defp resolve_locale(conn) do
    conn
    |> get_session(:locale)
    |> case do
      nil -> conn.cookies[Locale.cookie_name()]
      locale -> locale
    end
    |> Locale.normalize()
  end
end
