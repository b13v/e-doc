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
    ~H"""
    <nav class="flex items-center space-x-6">
      <a href="/invoices" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("Invoices") %></a>
      <a href="/contracts" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("Contracts") %></a>
      <a href="/acts" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("Acts") %></a>
      <a href="/buyers" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("Buyers") %></a>
      <a href="/company" class="text-gray-600 hover:text-gray-900 font-medium"><%= gettext("Company") %></a>
      <%= locale_switcher(assigns) %>
      <span class="text-gray-500 text-sm"><%= @current_user.email %></span>
      <form method="post" action="/logout" class="inline">
        <input type="hidden" name="_method" value="delete" />
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <button type="submit" class="text-gray-600 hover:text-gray-900 font-medium bg-transparent border-none cursor-pointer p-0"><%= gettext("Logout") %></button>
      </form>
    </nav>
    """
  end

  @doc """
  The app layout includes the header and main content area.
  """
  def app(assigns) do
    ~H"""
    <header class="bg-white shadow-sm border-b border-gray-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
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

    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
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
    <div class="inline-flex items-center rounded-md bg-gray-100 p-1">
      <a
        href={locale_path("kk", @current_path)}
        class={[
          "rounded px-2 py-1 text-sm font-medium",
          if(@locale == "kk", do: "bg-white text-blue-600 shadow-sm", else: "text-gray-500")
        ]}
      >
        Қаз
      </a>
      <a
        href={locale_path("ru", @current_path)}
        class={[
          "rounded px-2 py-1 text-sm font-medium",
          if(@locale == "ru", do: "bg-white text-blue-600 shadow-sm", else: "text-gray-500")
        ]}
      >
        Рус
      </a>
    </div>
    """
  end

  defp locale_path(locale, current_path) do
    "/locale/#{locale}?return_to=#{URI.encode_www_form(current_path)}"
  end
end
