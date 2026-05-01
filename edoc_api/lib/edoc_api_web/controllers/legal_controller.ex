defmodule EdocApiWeb.LegalController do
  use EdocApiWeb, :controller

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy,
      page_title: localized_title(conn, "Политика конфиденциальности", "Құпиялылық саясаты"),
      locale: current_locale(conn)
    )
  end

  def terms_of_use(conn, _params) do
    render(conn, :terms_of_use,
      page_title: localized_title(conn, "Условия использования", "Пайдалану шарттары"),
      locale: current_locale(conn)
    )
  end

  defp localized_title(conn, ru, kk) do
    if current_locale(conn) == "kk", do: kk, else: ru
  end

  defp current_locale(conn), do: conn.assigns[:locale] || "ru"
end
