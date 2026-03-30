defmodule EdocApiWeb.Locale do
  @moduledoc false

  @default_locale "ru"
  @supported_locales ~w(ru kk)
  @cookie_name "locale"

  def default_locale, do: @default_locale
  def supported_locales, do: @supported_locales
  def cookie_name, do: @cookie_name

  def normalize(locale) when is_atom(locale), do: locale |> Atom.to_string() |> normalize()

  def normalize(locale) when is_binary(locale) do
    locale = locale |> String.trim() |> String.downcase()

    if locale in @supported_locales, do: locale, else: @default_locale
  end

  def normalize(_), do: @default_locale

  def valid?(locale) when is_binary(locale),
    do: String.trim(String.downcase(locale)) in @supported_locales

  def valid?(_), do: false

  def internal_return_path(path) when is_binary(path) do
    case URI.parse(path) do
      %URI{host: nil, scheme: nil, path: "/" <> _} -> path
      %URI{host: nil, scheme: nil, path: nil} -> "/"
      _ -> "/"
    end
  end

  def internal_return_path(_), do: "/"
end
