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
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title><%= assigns[:page_title] || "EdocAPI" %></title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>

        <!-- htmx from CDN -->
        <script src="https://unpkg.com/htmx.org@1.9.10"></script>

        <!-- Tailwind CSS from CDN for POC -->
        <script src="https://cdn.tailwindcss.com"></script>

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
  The app layout includes the header and main content area.
  """
  def app(assigns) do
    ~H"""
    <header class="bg-white shadow-sm border-b border-gray-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex items-center">
            <h1 class="text-xl font-bold text-gray-900">EdocAPI</h1>
          </div>
          <nav class="flex items-center space-x-8">
            <a href="/" class="text-gray-600 hover:text-gray-900 font-medium">Dashboard</a>
            <a href="/invoices" class="text-gray-600 hover:text-gray-900 font-medium">Invoices</a>
            <a href="/contracts" class="text-gray-600 hover:text-gray-900 font-medium">Contracts</a>
            <a href="/company" class="text-gray-600 hover:text-gray-900 font-medium">Company</a>
            <%= if assigns[:current_user] do %>
              <span class="text-gray-500 text-sm mr-2"><%= @current_user.email %></span>
              <form method="post" action="/logout" class="inline">
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                <button type="submit" class="text-gray-600 hover:text-gray-900 font-medium bg-transparent border-none cursor-pointer p-0">Logout</button>
              </form>
            <% else %>
              <a href="/login" class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700">
                Login
              </a>
            <% end %>
          </nav>
        </div>
      </div>
    </header>

    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      {@inner_content}
    </main>
    """
  end
end
