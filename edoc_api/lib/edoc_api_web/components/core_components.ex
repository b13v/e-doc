defmodule EdocApiWeb.CoreComponents do
  @moduledoc """
  Provides core components and helper functions for Phoenix HTML applications.

  This module includes basic components for rendering HTML with HEEx templates
  and helper functions used in templates.
  """
  use Phoenix.Component
  use Gettext, backend: EdocApiWeb.Gettext

  attr(:class, :string, default: nil)

  slot(:inner_block, required: true)

  def link(assigns) do
    ~H"""
    <a class={@class}><%= render_slot(@inner_block) %></a>
    """
  end

  @doc """
  Shared workspace page header with a primary action area.
  """
  attr(:title, :string, required: true)
  attr(:title_class, :string, default: nil)
  attr(:support_text, :string, default: nil)
  attr(:class, :string, default: nil)

  slot(:primary_action, required: true)
  slot(:secondary_content)

  def workspace_page_header(assigns) do
    ~H"""
    <header class={["flex flex-col gap-4 md:flex-row md:items-end md:justify-between", @class]}>
      <div class="min-w-0 space-y-2">
        <h1 class={["font-semibold tracking-tight text-slate-900", @title_class || "text-3xl"]}>
          <%= @title %>
        </h1>
        <p :if={@support_text} class="max-w-2xl text-sm leading-6 text-slate-600">
          <%= @support_text %>
        </p>
        <div :if={@secondary_content != []} class="text-sm text-slate-500">
          <%= render_slot(@secondary_content) %>
        </div>
      </div>
      <div class="flex shrink-0 items-center gap-3">
        <%= render_slot(@primary_action) %>
      </div>
    </header>
    """
  end

  @doc """
  Quiet support panel for workspace overview pages.
  """
  attr(:heading, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:class, :string, default: nil)

  slot(:inner_block, required: true)

  def workspace_support_panel(assigns) do
    ~H"""
    <aside class={["workspace-support-panel rounded-2xl border border-slate-200 bg-slate-50/80 p-5 dark:border-slate-700 dark:bg-slate-900/95", @class]}>
      <div class="space-y-1">
        <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-slate-700 dark:text-slate-100">
          <%= @heading %>
        </h2>
        <p :if={@subtitle} class="text-sm leading-6 text-slate-600 dark:text-slate-200"><%= @subtitle %></p>
      </div>
      <div class="mt-4 text-sm leading-6 text-slate-700 dark:text-slate-100 dark:text-slate-200">
        <%= render_slot(@inner_block) %>
      </div>
    </aside>
    """
  end

  @doc """
  Cleaner empty state with one clear next action.
  """
  attr(:title, :string, required: true)
  attr(:support_text, :string, required: true)
  attr(:action_label, :string, required: true)
  attr(:action_href, :string, required: true)
  attr(:class, :string, default: nil)

  def workspace_empty_state(assigns) do
    ~H"""
    <section class={["rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-12 text-center shadow-sm", @class]}>
      <div class="mx-auto max-w-lg space-y-4">
        <h2 class="text-2xl font-semibold tracking-tight text-slate-900"><%= @title %></h2>
        <p class="text-sm leading-6 text-slate-600"><%= @support_text %></p>
        <div>
          <a
            href={@action_href}
            class="inline-flex items-center rounded-full bg-slate-900 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-700"
          >
            <%= @action_label %>
          </a>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Presentational row actions for workspace overview tables.
  """
  attr(:primary, :map, required: true)
  attr(:secondary, :list, default: [])
  attr(:desktop_mode, :atom, default: :inline)
  attr(:mobile_mode, :atom, default: :overflow)
  attr(:class, :string, default: nil)

  def workspace_row_actions(assigns) do
    assigns = assign(assigns, :all_actions, [assigns.primary | assigns.secondary])

    ~H"""
    <div class={["relative flex items-center justify-end gap-2", @class]}>
      <details
        :if={@desktop_mode == :overflow}
        class="relative hidden md:block"
        data-row-actions-root
        ontoggle="window.positionWorkspaceRowActions && window.positionWorkspaceRowActions(this)"
      >
        <summary class="cursor-pointer list-none rounded-full border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:text-slate-900">
          <%= gettext("Actions") %>
        </summary>
        <div
          data-row-actions-menu
          class="fixed left-0 top-0 z-[80] hidden min-w-44 rounded-2xl border border-slate-200 bg-white p-2 shadow-lg"
        >
          <div class="flex flex-col items-stretch gap-1">
            <%= for action <- @all_actions do %>
              <.row_action action={action} tone={:mobile} />
            <% end %>
          </div>
        </div>
      </details>

      <details
        :if={@mobile_mode == :overflow}
        class="relative md:hidden"
        data-row-actions-root
        ontoggle="window.positionWorkspaceRowActions && window.positionWorkspaceRowActions(this)"
      >
        <summary class="cursor-pointer list-none rounded-full border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:text-slate-900">
          <%= gettext("Actions") %>
        </summary>
        <div
          data-row-actions-menu
          class="fixed left-0 top-0 z-[80] hidden min-w-44 rounded-2xl border border-slate-200 bg-white p-2 shadow-lg"
        >
          <div class="flex flex-col items-stretch gap-1">
            <%= for action <- @all_actions do %>
              <.row_action action={action} tone={:mobile} />
            <% end %>
          </div>
        </div>
      </details>
    </div>
    """
  end

  @doc """
  Render a consistent flash error summary for forms.
  """
  attr(:flash, :map, required: true)
  attr(:include_info, :boolean, default: true)
  attr(:class, :string, default: nil)

  def flash_error(assigns) do
    assigns =
      assigns
      |> assign(:show_info, assigns.include_info && assigns.flash["info"])
      |> assign(:show_error, assigns.flash["error"])

    ~H"""
    <div :if={@show_info || @show_error} class={["mb-4 space-y-3", @class]}>
      <div
        :if={@show_info}
        class="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-900 shadow-sm"
      >
        <p class="text-sm font-medium leading-6"><%= @flash["info"] %></p>
      </div>

      <div
        :if={@show_error}
        class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-rose-900 shadow-sm"
      >
        <p class="text-sm font-medium leading-6"><%= @flash["error"] %></p>
      </div>
    </div>
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
  def status_badge("draft"), do: badge(gettext("Draft"), "gray")
  def status_badge("issued"), do: badge(gettext("Issued"), "blue")
  def status_badge("signed"), do: badge(gettext("Signed"), "green")
  def status_badge("paid"), do: badge(gettext("Paid"), "green")
  def status_badge("void"), do: badge(gettext("Void"), "red")
  def status_badge(_), do: badge(gettext("Unknown"), "gray")

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

  attr(:action, :map, required: true)
  attr(:tone, :atom, default: :secondary)

  defp row_action(%{action: %{transport: :link} = action, tone: tone} = assigns) do
    assigns =
      assigns
      |> assign(:action, action)
      |> assign(:classes, action[:class] || row_action_classes(tone, action[:tone] || :default, :link))

    ~H"""
    <a href={@action.href} class={@classes}><%= @action.label %></a>
    """
  end

  defp row_action(%{action: %{transport: :form} = action, tone: tone} = assigns) do
    assigns =
      assigns
      |> assign(:action, action)
      |> assign(:classes, action[:class] || row_action_classes(tone, action[:tone] || :default, :form))
      |> assign(:form_method, form_method(action))
      |> assign(:csrf_token, csrf_token(action))
      |> assign(:method_override, method_override(action))

    ~H"""
    <form action={@action.action} method={@form_method} class={row_action_form_classes(@tone)}>
      <input :if={@csrf_token} type="hidden" name="_csrf_token" value={@csrf_token} />
      <input :if={@method_override} type="hidden" name="_method" value={@method_override} />
      <button
        type="submit"
        class={@classes}
        onclick={if @action[:confirm_text], do: "return confirm(#{inspect(@action.confirm_text)})", else: nil}
      >
        <%= @action.label %>
      </button>
    </form>
    """
  end

  defp row_action(%{action: %{transport: :htmx_delete} = action, tone: tone} = assigns) do
    assigns =
      assigns
      |> assign(:action, action)
      |> assign(:classes, action[:class] || row_action_classes(tone, action[:tone] || :danger, :htmx_delete))

    ~H"""
    <button
      type="button"
      hx-delete={@action.hx_delete}
      hx-confirm={@action[:confirm_text]}
      hx-target={"##{@action.row_dom_id}"}
      hx-swap="outerHTML"
      hx-on::after-request="if(event.detail.successful) window.location.reload()"
      class={@classes}
    >
      <%= @action.label %>
    </button>
    """
  end

  defp row_action_classes(:primary, _semantic_tone, :link),
    do: "text-sm font-semibold text-slate-900 transition hover:text-slate-700"

  defp row_action_classes(:primary, _semantic_tone, _transport),
    do: "text-sm font-semibold text-slate-900 transition hover:text-slate-700"

  defp row_action_classes(:secondary, _semantic_tone, :htmx_delete),
    do: "text-sm font-medium text-rose-700 transition hover:text-rose-900"

  defp row_action_classes(:secondary, _semantic_tone, _transport),
    do: "text-sm font-medium text-slate-600 transition hover:text-slate-900"

  defp row_action_classes(:mobile, :info, _transport),
    do:
      "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-sky-700 transition hover:bg-slate-100 hover:text-sky-900"

  defp row_action_classes(:mobile, :success, _transport),
    do:
      "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-emerald-700 transition hover:bg-slate-100 hover:text-emerald-900"

  defp row_action_classes(:mobile, :danger, _transport),
    do:
      "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-rose-700 transition hover:bg-slate-100 hover:text-rose-900"

  defp row_action_classes(:mobile, _semantic_tone, _transport),
    do:
      "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-900"

  defp row_action_form_classes(:mobile), do: "block"
  defp row_action_form_classes(_tone), do: "inline"

  defp form_method(%{method: :get}), do: "get"
  defp form_method(%{method: :post}), do: "post"
  defp form_method(_action), do: "post"

  defp csrf_token(%{method: :get}), do: nil
  defp csrf_token(_action), do: Phoenix.Controller.get_csrf_token()

  defp method_override(%{_method: override}), do: override

  defp method_override(%{method: method}) when method in [:put, :patch, :delete],
    do: Atom.to_string(method)

  defp method_override(_action), do: nil
end
