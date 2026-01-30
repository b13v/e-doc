defmodule EdocApiWeb.CoreComponents do
  @moduledoc """
  Provides core components and helper functions for Phoenix HTML applications.

  This module includes basic components for rendering HTML with HEEx templates
  and helper functions used in templates.
  """
  use Phoenix.Component
  import Plug.Conn

  attr(:class, :string, default: nil)

  slot(:inner_block, required: true)

  def link(assigns) do
    ~H"""
    <a class={@class}><%= render_slot(@inner_block) %></a>
    """
  end

  @doc """
  Format a decimal as money with currency symbol.
  """
  def format_money(invoice, field \\ :total)

  def format_money(%{total: total, currency: currency}, :total) when is_struct(total, Decimal) do
    format_decimal(total) <> " " <> currency
  end

  def format_money(%{subtotal: subtotal, currency: currency}, :subtotal)
      when is_struct(subtotal, Decimal) do
    format_decimal(subtotal) <> " " <> currency
  end

  def format_money(%{vat: vat, currency: currency}, :vat) when is_struct(vat, Decimal) do
    format_decimal(vat) <> " " <> currency
  end

  def format_money(_, _), do: "-"

  @doc """
  Format a decimal value with thousand separators.
  """
  def format_decimal(nil), do: "0.00"

  def format_decimal(%Decimal{} = decimal) do
    decimal
    |> Decimal.to_string(:normal)
    |> format_decimal_string()
  end

  def format_decimal(value) when is_number(value) do
    value
    |> Decimal.from_float()
    |> Decimal.round(2)
    |> format_decimal()
  end

  defp format_decimal_string(string) do
    parts = String.split(string, ".")

    integer_part =
      parts
      |> Enum.at(0, "0")
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.join(" ")
      |> String.reverse()

    fractional_part = Enum.at(parts, 1, "00") |> String.pad_trailing(2, "0")

    integer_part <> "." <> fractional_part
  end

  @doc """
  Render a status badge with appropriate styling.
  """
  def status_badge("draft"), do: badge("Draft", "gray")
  def status_badge("issued"), do: badge("Issued", "blue")
  def status_badge("paid"), do: badge("Paid", "green")
  def status_badge("void"), do: badge("Void", "red")
  def status_badge(_), do: badge("Unknown", "gray")

  defp badge(text, color) do
    colors = %{
      "gray" => "bg-gray-100 text-gray-800",
      "blue" => "bg-blue-100 text-blue-800",
      "green" => "bg-green-100 text-green-800",
      "red" => "bg-red-100 text-red-800",
      "yellow" => "bg-yellow-100 text-yellow-800"
    }

    bg_class = Map.get(colors, color, "bg-gray-100 text-gray-800")

    assigns = %{text: text, bg_class: bg_class}

    ~H"""
    <span class={"inline-flex items-center rounded-md px-2 py-1 text-xs font-medium #{@bg_class}"}>
      <%= @text %>
    </span>
    """
  end

  @doc """
  Get the JWT token from the conn for htmx requests.
  Looks for token in session or assigns.
  """
  def get_token(conn) do
    # Try to get token from session or assigns
    # For the POC, we'll look for it in assigns (set by auth plug)
    # In production, you might store this in the session after login
    conn.assigns[:token] || conn.private[:guardian_token] || get_session(conn, :token) || ""
  end
end
