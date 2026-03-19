defmodule EdocApiWeb.LocaleController do
  use EdocApiWeb, :controller

  alias EdocApiWeb.Locale

  def update(conn, %{"locale" => locale} = params) do
    locale = Locale.normalize(locale)
    return_to = Locale.internal_return_path(Map.get(params, "return_to", "/"))

    conn
    |> put_session(:locale, locale)
    |> put_resp_cookie(Locale.cookie_name(), locale,
      max_age: 31_536_000,
      same_site: "Lax",
      path: "/"
    )
    |> redirect(to: return_to)
  end
end
