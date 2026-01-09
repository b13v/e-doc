defmodule EdocApiWeb.Router do
  use EdocApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :auth_api do
    plug(:accepts, ["json"])
    plug(EdocApiWeb.Plugs.Authenticate)
  end

  # Public API
  scope "/v1", EdocApiWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)

    post("/auth/signup", AuthController, :signup)
    post("/auth/login", AuthController, :login)
  end

  # Protected API (JWT required)
  scope "/v1", EdocApiWeb do
    pipe_through(:auth_api)

    get("/company", CompanyController, :show)
    put("/company", CompanyController, :upsert)
    get("/invoices", InvoiceController, :index)
    post("/invoices", InvoiceController, :create)
    get("/invoices/:id", InvoiceController, :show)

    get("/invoices/:id/pdf", InvoiceController, :pdf)
    # get "/invoices/:id/pdf/download", InvoiceController, :download_pdf
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:edoc_api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: EdocApiWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
