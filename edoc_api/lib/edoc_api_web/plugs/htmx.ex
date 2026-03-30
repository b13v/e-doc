defmodule EdocApiWeb.Plugs.Htmx do
  @moduledoc """
  Plug to detect htmx requests and set appropriate assigns.

  Based on: https://cosmicrose.dev/blog/htmx-elixir/
  """
  import Plug.Conn
  import Phoenix.Controller

  @doc """
  Detects if the request is from htmx and sets conn.assigns.htmx
  """
  def detect_htmx_request(conn, _opts) do
    if get_req_header(conn, "hx-request") == ["true"] do
      assign(conn, :htmx, %{
        request: true,
        boosted: get_req_header(conn, "hx-boosted") != [],
        current_url: List.first(get_req_header(conn, "hx-current-url")),
        history_restore_request: get_req_header(conn, "hx-history-restore-request") == ["true"],
        target: List.first(get_req_header(conn, "hx-target")),
        trigger: List.first(get_req_header(conn, "hx-trigger")),
        trigger_name: List.first(get_req_header(conn, "hx-trigger-name")),
        prompt: List.first(get_req_header(conn, "hx-prompt"))
      })
    else
      assign(conn, :htmx, %{request: false})
    end
  end

  @doc """
  Sets layout based on htmx request.

  - For htmx requests: no root layout, no app layout (fragments only)
  - For htmx boosted/history requests: app layout only (for navigation)
  - For regular requests: full root + app layout
  """
  def htmx_layout(conn, _opts) do
    if conn.assigns.htmx.request do
      # htmx request: return HTML fragment only
      conn
      |> put_root_layout(html: false)
      |> put_layout(html: false)
    else
      # Regular request: full layout
      conn
      |> put_root_layout(html: {EdocApiWeb.Layouts, :root})
      |> put_layout(html: {EdocApiWeb.Layouts, :app})
    end
  end
end

defmodule EdocApiWeb.Plugs.HtmxDetect do
  @moduledoc """
  Plug module wrapper for htmx request detection.
  """

  def init(opts), do: opts

  def call(conn, opts) do
    EdocApiWeb.Plugs.Htmx.detect_htmx_request(conn, opts)
  end
end

defmodule EdocApiWeb.Plugs.HtmxLayout do
  @moduledoc """
  Plug module wrapper for htmx layout handling.
  """

  def init(opts), do: opts

  def call(conn, opts) do
    EdocApiWeb.Plugs.Htmx.htmx_layout(conn, opts)
  end
end
