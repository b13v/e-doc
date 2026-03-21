defmodule EdocApiWeb.Layouts do
  @moduledoc """
  Layouts for rendering HTML pages with htmx support.
  """
  use EdocApiWeb, :html

  @doc """
  The root layout wraps the entire HTML document.
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={assigns[:locale] || "ru"} class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title><%= assigns[:page_title] || "EdocAPI" %></title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>

        <!-- htmx (self-hosted) -->
        <script defer phx-track-static type="text/javascript" src={~p"/vendor/htmx.min.js"}></script>

        <!-- HTMX CSRF Token Configuration -->
        <script>
          document.addEventListener("DOMContentLoaded", function() {
            var csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
            if (csrfToken) {
              document.body.addEventListener('htmx:configRequest', function(evt) {
                evt.detail.headers['x-csrf-token'] = csrfToken;
              });
            }
          });
        </script>

        <!-- Tailwind CSS from CDN (pinned version) -->
        <script src="https://cdn.tailwindcss.com/3.4.14"></script>

        <style>
          /* Custom styles for htmx */
          [hx-indicator] { display: none; }
          [hx-indicator].htmx-request { display: inline; }
          .htmx-indicator { display: none; }
          .htmx-request .htmx-indicator { display: inline; }
          .htmx-request.htmx-indicator { display: inline; }
        </style>
      </head>
      <body class="bg-gray-50 text-gray-800 antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc """
  Public navigation for unauthenticated users
  """
  def public_nav(assigns) do
    ~H"""
    <nav class="flex items-center space-x-6">
      <a href="/" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("Home") %></a>
      <a href="/about" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("About") %></a>
      <%= locale_switcher(assigns) %>
      <a href="/login" class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700">
        <%= gettext("Sign In") %>
      </a>
    </nav>
    """
  end

  @doc """
  Authenticated user navigation
  """
  def auth_nav(assigns) do
    assigns = Map.put_new(assigns, :current_section, nil)

    ~H"""
    <div class="flex w-full flex-col items-stretch gap-3 lg:flex-row lg:items-center lg:justify-end">
      <nav class="hidden items-center gap-2 lg:flex" aria-label={gettext("Menu")}>
        <%= for {section, path} <- workspace_sections() do %>
          <% active? = section == @current_section %>
          <a
            href={path}
            aria-current={if active?, do: "page", else: nil}
            class={nav_link_class(active?)}
          >
            <%= section_label(section) %>
          </a>
        <% end %>
      </nav>

      <details class="rounded-2xl bg-white/80 ring-1 ring-stone-200 lg:hidden">
        <summary class="flex cursor-pointer list-none items-center justify-between px-4 py-3 text-sm font-semibold text-slate-900">
          <span><%= section_label(@current_section) %></span>
          <span class="text-slate-400">+</span>
        </summary>
        <div class="border-t border-stone-200 px-3 py-3">
          <div class="space-y-1">
            <%= for {section, path} <- workspace_sections() do %>
              <a
                href={path}
                aria-current={if section == @current_section, do: "page", else: nil}
                class={[
                  "block rounded-xl px-3 py-2 text-sm",
                  if(
                    section == @current_section,
                    do: "bg-stone-100 font-semibold text-slate-900",
                    else: "text-slate-600"
                  )
                ]}
              >
                <%= section_label(section) %>
              </a>
            <% end %>
          </div>
          <div class="mt-3 border-t border-stone-200 pt-3">
            <%= locale_switcher(assigns) %>
            <p class="mt-3 text-sm text-slate-500"><%= @current_user.email %></p>
            <form method="post" action="/logout" class="mt-3">
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <button
                type="submit"
                class="w-full rounded-xl border border-stone-200 px-3 py-2 text-left text-sm font-medium text-slate-600"
              >
                <%= gettext("Logout") %>
              </button>
            </form>
          </div>
        </div>
      </details>

      <div class="hidden items-center gap-3 lg:flex">
        <%= locale_switcher(assigns) %>
        <div class="flex items-center gap-3 rounded-full bg-white/85 px-3 py-2 text-sm shadow-sm ring-1 ring-stone-200">
          <span class="text-slate-500"><%= @current_user.email %></span>
          <form method="post" action="/logout">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button type="submit" class="font-medium text-slate-600 hover:text-slate-900">
              <%= gettext("Logout") %>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The app layout includes the header and main content area.
  """
  def app(assigns) do
    ~H"""
    <header class="border-b border-stone-200 bg-stone-50/95 backdrop-blur">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex flex-col gap-4 py-4 lg:flex-row lg:items-center lg:justify-between">
          <div class="flex items-center">
            <%= brand_logo(assigns) %>
          </div>
          <%= if assigns[:current_user] do %>
            <%= auth_nav(assigns) %>
          <% else %>
            <%= public_nav(assigns) %>
          <% end %>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      {@inner_content}
    </main>
    """
  end

  defp brand_logo(assigns) do
    ~H"""
    <a href="/" class="inline-flex items-center gap-2 text-xl font-extrabold text-[#0066cc]">
      <span class="flex h-10 w-10 items-center justify-center rounded-[10px] bg-gradient-to-br from-[#0066cc] to-[#00a651] text-white shadow-sm">
        <svg
          class="h-5 w-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M9 3h6l4 4v14H9a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z" />
          <path d="M15 3v4h4" />
          <path d="M11 12h6" />
          <path d="M11 16h6" />
        </svg>
      </span>
      <span>Edocly</span>
    </a>
    """
  end

  defp locale_switcher(assigns) do
    assigns =
      Map.merge(assigns, %{
        current_path: assigns[:current_path] || "/",
        locale: assigns[:locale] || "ru"
      })

    ~H"""
    <div class="inline-flex items-center rounded-full bg-stone-100 p-1 ring-1 ring-stone-200">
      <a
        href={locale_path("kk", @current_path)}
        class={[
          "rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide",
          if(@locale == "kk", do: "bg-white text-slate-900 shadow-sm", else: "text-slate-500")
        ]}
      >
        Қаз
      </a>
      <a
        href={locale_path("ru", @current_path)}
        class={[
          "rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide",
          if(@locale == "ru", do: "bg-white text-slate-900 shadow-sm", else: "text-slate-500")
        ]}
      >
        Рус
      </a>
    </div>
    """
  end

  defp section_label(:invoices), do: gettext("Invoices")
  defp section_label(:buyers), do: gettext("Buyers")
  defp section_label(:contracts), do: gettext("Contracts")
  defp section_label(:acts), do: gettext("Acts")
  defp section_label(:company), do: gettext("Company")

  defp section_label(_), do: gettext("Menu")

  defp nav_link_class(active?) do
    if active? do
      "inline-flex items-center rounded-full bg-white px-3 py-2 text-sm font-semibold text-slate-900 shadow-sm ring-1 ring-slate-200"
    else
      "inline-flex items-center rounded-full px-3 py-2 text-sm font-medium text-slate-500 hover:text-slate-900"
    end
  end

  defp workspace_sections do
    [
      {:invoices, "/invoices"},
      {:contracts, "/contracts"},
      {:acts, "/acts"},
      {:buyers, "/buyers"},
      {:company, "/company"}
    ]
  end

  defp locale_path(locale, current_path) do
    "/locale/#{locale}?return_to=#{URI.encode_www_form(current_path)}"
  end
end
